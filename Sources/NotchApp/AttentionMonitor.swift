import AppKit
import Carbon
import SessionCore

/// Finds out what the user is looking at and whether a Focus is on. Both are read on demand: the
/// answer has to be fresh at the moment a session asks for something.
@MainActor
final class AttentionMonitor {
    /// The application in front changed.
    var onChange: (() -> Void)?

    private var observer: NSObjectProtocol?
    private var focus = FocusReader()
    /// The last window in front that was not one of this app's own.
    private var lastFront: FrontWindow?
    private var askedToControlTerminal = false
    private lazy var selectedTab = NSAppleScript(source: """
        with timeout of 1 second
            tell application "Terminal" to get tty of selected tab of front window
        end timeout
        """)

    init() {
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
    }

    /// False when the Focus record cannot be read or understood, so no Focus is ever seen.
    var canReadFocus: Bool { focus.isReadable }

    /// `readingTerminalTab` asks Terminal which tab is selected when Terminal is in front. It
    /// costs an Apple event, so it is asked for only when a session in Terminal is concerned.
    func attention(readingTerminalTab: Bool) -> Attention {
        Attention(frontWindow: frontWindow(readingTerminalTab: readingTerminalTab), focusIsOn: focus.isOn())
    }

    private func frontWindow(readingTerminalTab: Bool) -> FrontWindow? {
        guard let app = NSWorkspace.shared.frontmostApplication, let bundleID = app.bundleIdentifier,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return lastFront }
        var front = FrontWindow(bundleID: bundleID)
        if readingTerminalTab, bundleID == SessionLocation.terminalBundleID {
            front.terminalTTY = selectedTerminalTab()
        }
        lastFront = front
        return front
    }

    /// The terminal device of the tab in front, when the user lets this app ask Terminal. The
    /// system's question to the user is put from another thread, once, and never waited for here.
    private func selectedTerminalTab() -> String? {
        let terminal = NSAppleEventDescriptor(bundleIdentifier: SessionLocation.terminalBundleID)
        switch AEDeterminePermissionToAutomateTarget(terminal.aeDesc, typeWildCard, typeWildCard, false) {
        case noErr:
            var error: NSDictionary?
            return selectedTab?.executeAndReturnError(&error).stringValue
        case OSStatus(errAEEventWouldRequireUserConsent) where !askedToControlTerminal:
            askedToControlTerminal = true
            DispatchQueue.global(qos: .utility).async {
                let terminal = NSAppleEventDescriptor(bundleIdentifier: SessionLocation.terminalBundleID)
                _ = AEDeterminePermissionToAutomateTarget(terminal.aeDesc, typeWildCard, typeWildCard, true)
            }
            return nil
        default:
            return nil
        }
    }
}

/// Reads the system's Focus record. macOS keeps it from apps without Full Disk Access; then no
/// Focus is seen, and asking again is left for much later.
private struct FocusReader {
    private static let file = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
    private static let freshFor: TimeInterval = 2
    private static let retryAfter: TimeInterval = 60

    private(set) var isReadable = true
    private var isOnNow = false
    private var readAt = Date.distantPast

    mutating func isOn() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(readAt) >= (isReadable ? Self.freshFor : Self.retryAfter) else { return isOnNow }
        readAt = now
        let state = (try? Data(contentsOf: Self.file)).flatMap(FocusRecord.isOn)
        isReadable = state != nil
        isOnNow = state ?? false
        return isOnNow
    }
}

/// The sound that goes with an interruption: one of the system's alert sounds, or none.
enum InterruptionSound {
    static let defaultName = "Glass"
    private static let key = "interruptionSound"

    /// The system's alert sounds by name.
    static let names: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        return files.map { ($0 as NSString).deletingPathExtension }.sorted()
    }()

    /// Nil when sounds are turned off.
    static var current: String? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: key) else { return defaultName }
            return stored.isEmpty ? nil : stored
        }
        set { UserDefaults.standard.set(newValue ?? "", forKey: key) }
    }

    @MainActor
    static func play() {
        guard let current else { return }
        NSSound(named: current)?.play()
    }
}
