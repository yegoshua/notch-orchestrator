import AppKit
import Darwin
import SessionCore

extension AppConfig {
    /// Where the Claude desktop app keeps one record per Code session. The app only reads there.
    /// `-claudeDesktopSessionsDirectory …` points it elsewhere.
    var claudeDesktopSessionsDirectory: URL {
        UserDefaults.standard.string(forKey: "claudeDesktopSessionsDirectory").map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions")
    }
}

/// The desktop app's session records, `<account>/<organization>/local_<uuid>.json`. A record is
/// large and rewritten only while its session is active, so each file is read again only after it
/// changed. A missing directory or an unreadable file simply yields fewer records.
///
/// Not safe for concurrent use.
final class DesktopSessionRecords {
    private let directory: URL
    private var cache: [String: (modified: Date, record: DesktopSessionRecord?)] = [:]

    init(directory: URL) {
        self.directory = directory
    }

    func read() -> [DesktopSessionRecord] {
        let files = FileManager.default
        var seen: [String: (modified: Date, record: DesktopSessionRecord?)] = [:]
        // Several accounts and organizations mean several folders.
        for account in Self.folders(in: directory) {
            for organization in Self.folders(in: account) {
                let records = (try? files.contentsOfDirectory(
                    at: organization, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
                for file in records
                where file.pathExtension == "json" && file.lastPathComponent.hasPrefix("local_") {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                        .contentModificationDate ?? .distantPast
                    if let cached = cache[file.path], cached.modified == modified {
                        seen[file.path] = cached
                    } else {
                        seen[file.path] = (modified, (try? Data(contentsOf: file)).flatMap(DesktopSessionRecord.init(json:)))
                    }
                }
            }
        }
        cache = seen
        return seen.values.compactMap(\.record)
    }

    private static func folders(in directory: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }
}

/// Finds the program a CLI session runs in by walking up from its process.
enum ProcessHost {
    static let terminalBundleID = "com.apple.Terminal"
    private static let vsCodeBundleIDs = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium"]

    static func location(of pid: pid_t) -> SessionLocation {
        guard let process = info(pid) else { return .unknown }
        var current = pid_t(process.pbi_ppid)
        // The chain is a handful of processes long; the bound only guards against a cycle.
        for _ in 0..<32 {
            guard current > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: current), let bundleID = app.bundleIdentifier {
                if bundleID == terminalBundleID, let tty = terminalDevice(of: process) {
                    return .terminalApp(tty: tty)
                }
                // The integrated terminal hangs off a helper whose identifier extends the app's.
                if let code = vsCodeBundleIDs.first(where: { bundleID == $0 || bundleID.hasPrefix($0 + ".") }) {
                    return .vsCode(bundleID: code)
                }
                if app.activationPolicy == .regular {
                    return .application(name: app.localizedName ?? bundleID, bundleID: bundleID)
                }
            }
            guard let parent = info(current) else { break }
            current = pid_t(parent.pbi_ppid)
        }
        return .unknown
    }

    private static func info(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    /// The controlling terminal, the way Terminal.app names the device of a tab.
    private static func terminalDevice(of process: proc_bsdinfo) -> String? {
        guard process.e_tdev != UInt32.max, let name = devname(dev_t(bitPattern: process.e_tdev), S_IFCHR) else {
            return nil
        }
        return "/dev/" + String(cString: name)
    }
}

/// Takes the user to a session, as close as its location allows. What each location promises is
/// said by its `jumpTarget`; every jump falls back to bringing the application forward.
@MainActor
enum SessionJump {
    private static let claudeDesktopBundleID = "com.anthropic.claudefordesktop"

    static func jump(to location: SessionLocation, cwd: String?) {
        switch location {
        case .terminalApp(let tty):
            focusTerminalTab(tty)
        case .desktopApp(let sessionID):
            // The link the desktop app uses for its own "Continue" entries. An identifier it does
            // not know lands on its home screen, so the app comes forward either way.
            if sessionID.wholeMatch(of: #/local_[A-Za-z0-9-]{1,64}/#) != nil,
               let link = URL(string: "claude://code/continue?session=\(sessionID)") {
                NSWorkspace.shared.open(link)
            }
            // The app may turn the link down without a sign (signed out, links disabled), so it
            // is brought forward regardless: the click is never a dead end.
            activate(claudeDesktopBundleID)
        case .vsCode(let bundleID):
            // Opening the folder brings forward the window that already has it open.
            guard let cwd, let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                return activate(bundleID)
            }
            NSWorkspace.shared.open(
                [projectFolder(of: cwd)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        case .application(_, let bundleID):
            activate(bundleID)
        case .unknown:
            break
        }
    }

    /// The folder a window is most likely open on: the repository the session works in, since a
    /// session is often started further down. Opening a folder no window has would make a new one.
    private static func projectFolder(of cwd: String) -> URL {
        let start = URL(fileURLWithPath: cwd)
        var folder = start
        while folder.path != "/" {
            if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) { return folder }
            folder.deleteLastPathComponent()
        }
        return start
    }

    private static func activate(_ bundleID: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Asks Terminal for the tab on `tty`. The first time, macOS asks the user whether this app
    /// may control Terminal; refused or not found, Terminal is at least brought forward. Run as a
    /// separate process so that the system's question does not block the island.
    private static func focusTerminalTab(_ tty: String) {
        let script = """
            on run argv
                set wanted to item 1 of argv
                tell application "Terminal"
                    repeat with w in windows
                        repeat with t in tabs of w
                            if tty of t is wanted then
                                set selected tab of w to t
                                set frontmost of w to true
                                activate
                                return
                            end if
                        end repeat
                    end repeat
                end tell
                error "no tab on " & wanted
            end run
            """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script, tty]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { finished in
            guard finished.terminationStatus != 0 else { return }
            Task { @MainActor in activate(ProcessHost.terminalBundleID) }
        }
        do {
            try process.run()
        } catch {
            activate(ProcessHost.terminalBundleID)
        }
    }
}
