import ClaudeConnection
import Foundation

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
        self.port = port > 0 ? port : Self.defaultPort
    }

    var installer: ConnectionInstaller {
        ConnectionInstaller(
            settings: claudeSettings,
            backup: supportDirectory.appendingPathComponent("claude-settings.backup.json")
        )
    }

    /// The secret shared with our hook entries. Created on first use, readable by the user only.
    func connection() throws -> HookConnection {
        let file = supportDirectory.appendingPathComponent("token")
        if let token = try? String(contentsOf: file, encoding: .utf8), !token.isEmpty {
            return HookConnection(port: port, token: token)
        }
        var bytes = [UInt8](repeating: 0, count: 24)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw CocoaError(.fileWriteUnknown)
        }
        let token = bytes.map { String(format: "%02x", $0) }.joined()
        try FileManager.default.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
        try Data(token.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return HookConnection(port: port, token: token)
    }

    /// Set once the user chose "Remove completely", so the next launch does not reconnect by itself.
    var connectionRemovedByUser: Bool {
        get { defaults.bool(forKey: "connectionRemovedByUser") }
        nonmutating set { defaults.set(newValue, forKey: "connectionRemovedByUser") }
    }

    var livenessMinutes: Int {
        get {
            let minutes = defaults.integer(forKey: "livenessMinutes")
            return minutes > 0 ? minutes : Self.defaultLivenessMinutes
        }
        nonmutating set { defaults.set(newValue, forKey: "livenessMinutes") }
    }
}
