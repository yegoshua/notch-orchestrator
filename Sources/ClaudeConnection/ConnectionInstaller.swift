import Foundation

/// Applies the settings transformation to the settings file on disk.
public struct ConnectionInstaller: Sendable {
    public var settings: URL
    public var backup: URL

    public init(settings: URL, backup: URL) {
        self.settings = settings
        self.backup = backup
    }

    /// Adds or refreshes our entries. The file as it was before our first change is kept at `backup`.
    public func install(_ connection: HookConnection) throws {
        let original = try read()
        let installed = try ClaudeSettings.installing(connection, into: original)
        guard installed != original else { return }

        if let original, !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.createDirectory(
                at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try write(installed)
    }

    /// Deletes every entry we added.
    public func remove() throws {
        guard let original = try read() else { return }
        let removed = try ClaudeSettings.removing(from: original)
        guard removed != original else { return }
        try write(removed)
    }

    public func isInstalled(_ connection: HookConnection) -> Bool {
        ClaudeSettings.isInstalled(connection, in: try? read())
    }

    /// Nil only when there is no file. A file that exists but cannot be read is an error:
    /// treating it as absent would overwrite it.
    private func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: settings.path) else { return nil }
        return try Data(contentsOf: settings)
    }

    /// Settings hold the token and may be a symlink into a dotfiles repository: keep both properties.
    private func write(_ data: Data) throws {
        let files = FileManager.default
        let target = settings.resolvingSymlinksInPath()
        let permissions = (try? files.attributesOfItem(atPath: target.path))?[.posixPermissions] ?? 0o600
        try files.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
        try files.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
    }
}
