import Foundation

/// Where the app's hook receiver listens and the secret that proves a request came from our hooks.
public struct HookConnection: Equatable, Sendable {
    public var port: Int
    public var token: String

    public init(port: Int, token: String) {
        self.port = port
        self.token = token
    }
}

public enum SettingsError: Error, Equatable {
    /// The settings are not a JSON object of the expected shape. They must be left alone.
    case malformed
}

/// The pure transformation of Claude Code settings: add our hook entries, remove them.
public enum ClaudeSettings {
    /// Hook events the app subscribes to.
    public static let events = ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"]

    /// Ends every command we install. An entry is ours if and only if it carries this marker.
    static let marker = "# notch-orchestrator"

    /// The header that carries the token.
    public static let tokenHeader = "X-Notch-Token"

    /// A command hook rather than an HTTP hook: when the app is not running an HTTP hook prints a
    /// connection error into the session, while this exits quietly with status zero.
    static func command(for event: String, _ connection: HookConnection) -> String {
        "/usr/bin/curl -s -m 2 -o /dev/null -H '\(tokenHeader): \(connection.token)' "
            + "-H 'Content-Type: application/json' --data-binary @- "
            + "http://127.0.0.1:\(connection.port)/hook/\(event) 2>/dev/null || true \(marker)"
    }

    /// Returns `settings` with exactly one current entry of ours per event. Idempotent.
    public static func installing(_ connection: HookConnection, into settings: Data?) throws -> Data {
        var document = try Document(settings)
        try document.removeOurEntries()

        var hooks = document.root["hooks"] ?? .object([])
        for event in events {
            guard case .array(var groups) = hooks[event] ?? .array([]) else { throw SettingsError.malformed }
            let hook: OrderedJSON = .object([
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(command(for: event, connection))),
                .init(key: "timeout", value: .number("5")),
            ])
            groups.append(.object([.init(key: "hooks", value: .array([hook]))]))
            hooks[event] = .array(groups)
        }
        document.root["hooks"] = hooks
        return document.data
    }

    /// Returns `settings` without any entry of ours, and without the containers that only held them.
    public static func removing(from settings: Data) throws -> Data {
        var document = try Document(settings)
        try document.removeOurEntries()
        return document.data
    }

    /// Whether `settings` already contain exactly what `installing` would produce.
    public static func isInstalled(_ connection: HookConnection, in settings: Data?) -> Bool {
        guard let settings, let installed = try? installing(connection, into: settings) else { return false }
        return installed == settings
    }

    private struct Document {
        var root: OrderedJSON
        var endsWithNewline: Bool

        init(_ data: Data?) throws {
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            if text.allSatisfy(\.isWhitespace) {
                root = .object([])
                endsWithNewline = true
                return
            }
            guard let parsed = try? OrderedJSON(parsing: Data(text.utf8)), case .object = parsed else {
                throw SettingsError.malformed
            }
            root = parsed
            endsWithNewline = text.hasSuffix("\n")
        }

        var data: Data {
            Data((root.serialized() + (endsWithNewline ? "\n" : "")).utf8)
        }

        mutating func removeOurEntries() throws {
            guard let hooks = root["hooks"] else { return }
            guard case .object(let events) = hooks else { throw SettingsError.malformed }

            var keptEvents: [OrderedJSON.Member] = []
            var removedAnything = false
            for event in events {
                guard case .array(let groups) = event.value else { throw SettingsError.malformed }
                var keptGroups: [OrderedJSON] = []
                for group in groups {
                    guard case .array(let entries)? = group["hooks"] else {
                        keptGroups.append(group)
                        continue
                    }
                    let kept = entries.filter { !Self.isOurs($0) }
                    if kept.count == entries.count {
                        keptGroups.append(group)
                    } else {
                        removedAnything = true
                        if !kept.isEmpty {
                            var group = group
                            group["hooks"] = .array(kept)
                            keptGroups.append(group)
                        }
                    }
                }
                if !keptGroups.isEmpty || keptGroups.count == groups.count {
                    keptEvents.append(.init(key: event.key, value: .array(keptGroups)))
                }
            }
            // Containers are dropped only when removing our entries is what emptied them.
            root["hooks"] = keptEvents.isEmpty && removedAnything ? nil : .object(keptEvents)
        }

        private static func isOurs(_ hook: OrderedJSON) -> Bool {
            guard case .string(let command)? = hook["command"] else { return false }
            return command.hasSuffix(marker)
        }
    }
}
