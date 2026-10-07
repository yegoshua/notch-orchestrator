import Foundation

/// The status line wrapper: a command registered as Claude Code's `statusLine` that hands the
/// status line payload (which carries the usage limits) to the app and then runs the status line
/// command the user had before, whose output is what Claude Code displays.
///
/// Like the hook entries it is silent and harmless when the app is not running, and the secret is
/// read from the header file, never written into the settings or onto a command line.
extension ClaudeSettings {
    /// Where the wrapper posts the status line payload.
    public static let statusLinePath = "/statusline"

    private static let previousVariable = "__notch_previous"
    private static let inputVariable = "__notch_input"

    /// The wrapper command, chaining to `previous` when there was a status line command before.
    ///
    /// - The payload is read once and given to both curl and the previous command. The `x` keeps
    ///   command substitution from eating a trailing newline, so the previous command reads exactly
    ///   what Claude Code wrote.
    /// - curl runs in the background with its output discarded: the status line is never delayed by
    ///   the app, and nothing curl prints can reach the status line.
    /// - The previous command is kept as one quoted string and run with `eval` in the same shell
    ///   that Claude Code started, as the last thing the wrapper does, so its output, its errors and
    ///   its exit status are its own. Keeping it as a string is also what lets removal restore it
    ///   character for character.
    static func statusLineCommand(_ connection: HookConnection, chainingTo previous: String?) -> String {
        let forward = "\(inputVariable)=$(cat; printf x); \(inputVariable)=${\(inputVariable)%x}; "
            + "printf '%s' \"$\(inputVariable)\" | "
            + "/usr/bin/curl -q -s -m 2 --noproxy '*' -o /dev/null -H @\(shellQuoted(connection.tokenHeaderFile.path)) "
            + "-H 'Content-Type: application/json' --data-binary @- "
            + "http://127.0.0.1:\(connection.port)\(statusLinePath) >/dev/null 2>&1 &"
        guard let previous else { return "\(forward) \(marker)" }
        return "\(previousVariable)=\(shellQuoted(previous)); \(forward) "
            + "printf '%s' \"$\(inputVariable)\" | eval \"$\(previousVariable)\" \(marker)"
    }

    /// Puts the wrapper in place of the current status line command. Expects that a wrapper of ours
    /// was removed first. A `statusLine` we do not understand is left alone: it cannot be chained to.
    static func installStatusLine(_ connection: HookConnection, in root: inout OrderedJSON) {
        guard let statusLine = root["statusLine"] else {
            root["statusLine"] = .object([
                .init(key: "type", value: .string("command")),
                .init(key: "command", value: .string(statusLineCommand(connection, chainingTo: nil))),
            ])
            return
        }
        guard case .object = statusLine, case .string(let previous)? = statusLine["command"] else { return }
        var wrapped = statusLine
        wrapped["command"] = .string(statusLineCommand(connection, chainingTo: previous))
        root["statusLine"] = wrapped
    }

    /// Puts back the status line command the wrapper chained to, or removes the `statusLine` we added.
    static func removeStatusLine(from root: inout OrderedJSON) {
        guard let statusLine = root["statusLine"], case .string(let command)? = statusLine["command"],
              let wrapper = WrappedStatusLine(command)
        else { return }
        if let previous = wrapper.previous {
            var restored = statusLine
            restored["command"] = .string(previous)
            root["statusLine"] = restored
        } else {
            root["statusLine"] = nil
        }
    }

    /// Whether the status line in `settings` is our wrapper, so that usage limits reach the app.
    /// False while the hooks are installed means a `statusLine` we could not chain to.
    public static func forwardsUsageLimits(in settings: Data?) -> Bool {
        guard let settings, let root = try? OrderedJSON(parsing: settings),
              case .string(let command)? = root["statusLine"]?["command"]
        else { return false }
        return WrappedStatusLine(command) != nil
    }

    /// A status line command recognised as our wrapper.
    private struct WrappedStatusLine {
        /// The command it chains to; nil when there was no status line before.
        var previous: String?

        init?(_ command: String) {
            guard command.hasSuffix(" \(ClaudeSettings.marker)") else { return nil }
            let assignment = "\(ClaudeSettings.inputVariable)="
            if command.hasPrefix(assignment) { return }

            let opening = "\(ClaudeSettings.previousVariable)='"
            guard command.hasPrefix(opening) else { return nil }
            // The inverse of `shellQuoted`: a quote followed by `\''` is a quote of the original,
            // any other quote closes the string.
            var rest = command.dropFirst(opening.count)
            var previous = ""
            while let character = rest.first, character != "'" || rest.hasPrefix("'\\''") {
                previous.append(character)
                rest = rest.dropFirst(character == "'" ? 4 : 1)
            }
            guard rest.hasPrefix("'; \(assignment)") else { return nil }
            self.previous = previous
        }
    }

    private static func shellQuoted(_ string: String) -> String {
        "'" + string.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
