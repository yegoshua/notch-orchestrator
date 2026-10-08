import ClaudeConnection
import Foundation
import SessionCore

/// How the list shows the CI of what a session pushed.
enum CIView: String {
    /// A mark in the session's own row.
    case compact
    /// A line of its own under the session, with the branch.
    case detailed
}

/// Where the app keeps its own files and how it reaches Claude Code.
/// Every value can be overridden from the command line (`-claudeSettingsPath …`) for development,
/// so a debug build never has to touch the real user settings.
struct AppConfig {
    static let defaultPort = 47800
    static let defaultLivenessMinutes = 10

    let supportDirectory: URL
    let claudeSettings: URL
    let port: Int
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let home = FileManager.default.homeDirectoryForCurrentUser
        supportDirectory = defaults.string(forKey: "supportDirectory").map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent("Library/Application Support/notch-orchestrator")
        claudeSettings = defaults.string(forKey: "claudeSettingsPath").map { URL(fileURLWithPath: $0) }
            ?? home.appendingPathComponent(".claude/settings.json")
        let port = defaults.integer(forKey: "port")
        self.port = (1...65535).contains(port) ? port : Self.defaultPort
    }

    var installer: ConnectionInstaller {
        ConnectionInstaller(
            settings: claudeSettings,
            backup: supportDirectory.appendingPathComponent("claude-settings.backup.json")
        )
    }

    var connection: HookConnection {
        HookConnection(port: port, tokenHeaderFile: supportDirectory.appendingPathComponent("hook-header"))
    }

    /// The last known usage limits, kept across restarts.
    var usageLimitsFile: URL { supportDirectory.appendingPathComponent("usage-limits.json") }

    /// The merge requests that are followed, kept across restarts.
    var mergeRequestsFile: URL { supportDirectory.appendingPathComponent("merge-requests.json") }

    /// The secret our hook entries send. Created on first use and kept in a file only the user can
    /// read, in the form curl takes as a header file.
    func token() throws -> String {
        let file = connection.tokenHeaderFile
        let prefix = "\(ClaudeSettings.tokenHeader): "
        if let line = try? String(contentsOf: file, encoding: .utf8), line.hasPrefix(prefix) {
            let token = line.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Data("\(prefix)\(token)\n".utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return token
    }

    /// Set once the user chose "Remove completely", so the next launch does not reconnect by itself.
    var connectionRemovedByUser: Bool {
        get { defaults.bool(forKey: "connectionRemovedByUser") }
        nonmutating set { defaults.set(newValue, forKey: "connectionRemovedByUser") }
    }

    /// How long a request card waits before the request goes back to Claude Code's own dialog.
    /// `-requestTimeoutSeconds` shortens it for a check by hand; it can never reach the time
    /// Claude Code lets the hook wait.
    var requestTimeout: TimeInterval {
        let seconds = defaults.integer(forKey: "requestTimeoutSeconds")
        let longest = ClaudeSettings.permissionHookTimeout - 60
        return TimeInterval(seconds > 0 ? min(seconds, longest) : min(300, longest))
    }

    /// Smart unless the user chose otherwise.
    var interruptionMode: InterruptionMode {
        get { defaults.string(forKey: "interruptionMode").flatMap(InterruptionMode.init) ?? .smart }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "interruptionMode") }
    }

    /// A Focus silences the island unless the user chose otherwise.
    var respectsFocus: Bool {
        get { defaults.object(forKey: "respectsFocus") == nil || defaults.bool(forKey: "respectsFocus") }
        nonmutating set { defaults.set(newValue, forKey: "respectsFocus") }
    }

    /// GitLab hosts of the user's own that the setup checks beside gitlab.com.
    var gitLabHosts: [String] {
        get { defaults.stringArray(forKey: "gitLabHosts") ?? [] }
        nonmutating set { defaults.set(newValue, forKey: "gitLabHosts") }
    }

    /// Set once the GitLab setup opened by itself, so that it does so only once.
    var gitLabSetupWasOffered: Bool {
        get { defaults.bool(forKey: "gitLabSetupWasOffered") }
        nonmutating set { defaults.set(newValue, forKey: "gitLabSetupWasOffered") }
    }

    /// A line of its own unless the user chose otherwise.
    var ciView: CIView {
        get { defaults.string(forKey: "ciView").flatMap(CIView.init) ?? .detailed }
        nonmutating set { defaults.set(newValue.rawValue, forKey: "ciView") }
    }

    var livenessMinutes: Int {
        get {
            let minutes = defaults.integer(forKey: "livenessMinutes")
            return minutes > 0 ? minutes : Self.defaultLivenessMinutes
        }
        nonmutating set { defaults.set(newValue, forKey: "livenessMinutes") }
    }
}
