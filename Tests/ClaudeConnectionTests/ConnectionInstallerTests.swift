import Foundation
import Testing
import ClaudeConnection

private let connection = HookConnection(port: 47800, token: "abc123")

/// Settings the way a real user has them: other options, their own hooks, a status line.
private let existingSettings = """
{
  "permissions": {
    "allow": [
      "Bash(npm run lint)"
    ],
    "defaultMode": "auto"
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "afplay /System/Library/Sounds/Glass.aiff"
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "echo \\"été ✓\\" >> ~/log.txt",
            "timeout": 1.50
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  },
  "cleanupPeriodDays": 30,
  "enabledPlugins": {},
  "alwaysThinkingEnabled": true
}

"""

private func commands(in settings: Data, event: String) throws -> [String] {
    let root = try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
    let hooks = try #require(root["hooks"] as? [String: Any])
    let groups = hooks[event] as? [[String: Any]] ?? []
    return groups.flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
}

@Suite struct InstallingIntoSettings {
    @Test(arguments: [nil, "", "{}", "  \n"] as [String?])
    func emptySettingsGetOneHookPerLifecycleEvent(original: String?) throws {
        let installed = try ClaudeSettings.installing(connection, into: original.map { Data($0.utf8) })

        for event in ["UserPromptSubmit", "Stop", "StopFailure", "SessionEnd"] {
            let commands = try commands(in: installed, event: event)
            #expect(commands.count == 1)
            #expect(commands[0].contains("http://127.0.0.1:47800/hook/\(event)"))
            #expect(commands[0].contains("X-Notch-Token: abc123"))
        }
    }

    @Test func theHookCommandCanNeverFailOrBlock() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        let command = try #require(try commands(in: installed, event: "Stop").first)

        // Short timeout, no output, and a zero exit status even when nothing is listening.
        #expect(command.contains("curl -s -m 2 -o /dev/null"))
        #expect(command.contains("|| true"))
    }

    @Test func existingHooksAndOptionsAreKept() throws {
        let installed = try ClaudeSettings.installing(connection, into: Data(existingSettings.utf8))
        let text = String(decoding: installed, as: UTF8.self)

        #expect(try commands(in: installed, event: "Stop").first == "afplay /System/Library/Sounds/Glass.aiff")
        #expect(try commands(in: installed, event: "Stop").count == 2)
        #expect(try commands(in: installed, event: "PreToolUse") == ["echo \"été ✓\" >> ~/log.txt"])
        #expect(text.contains("\"timeout\": 1.50"))
        #expect(text.contains("\"command\": \"~/.claude/statusline.sh\""))
        // Key order is the user's, not alphabetical.
        let permissions = try #require(text.range(of: "\"permissions\""))
        let cleanup = try #require(text.range(of: "\"cleanupPeriodDays\""))
        let thinking = try #require(text.range(of: "\"alwaysThinkingEnabled\""))
        #expect(permissions.lowerBound < cleanup.lowerBound && cleanup.lowerBound < thinking.lowerBound)
    }

    @Test func installingTwiceChangesNothingTheSecondTime() throws {
        let once = try ClaudeSettings.installing(connection, into: Data(existingSettings.utf8))
        let twice = try ClaudeSettings.installing(connection, into: once)

        #expect(twice == once)
    }

    @Test func installingAgainReplacesAStaleEntry() throws {
        let old = try ClaudeSettings.installing(HookConnection(port: 1111, token: "old"), into: Data(existingSettings.utf8))
        let repaired = try ClaudeSettings.installing(connection, into: old)

        #expect(repaired == (try ClaudeSettings.installing(connection, into: Data(existingSettings.utf8))))
        #expect(!String(decoding: repaired, as: UTF8.self).contains("1111"))
    }

    @Test func malformedSettingsAreRejected() {
        for broken in ["{ \"hooks\": ", "[1, 2]", "{\"hooks\": []}", "not json"] {
            #expect(throws: SettingsError.self) {
                try ClaudeSettings.installing(connection, into: Data(broken.utf8))
            }
        }
    }
}

@Suite struct RemovingFromSettings {
    @Test func removalAfterInstallRestoresTheOriginalExactly() throws {
        let installed = try ClaudeSettings.installing(connection, into: Data(existingSettings.utf8))
        let removed = try ClaudeSettings.removing(from: installed)

        #expect(String(decoding: removed, as: UTF8.self) == existingSettings)
    }

    @Test func removalFromSettingsThatHadNoHooksLeavesNoTrace() throws {
        let original = "{\n  \"model\": \"opus\"\n}\n"
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))

        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }

    @Test func removalWithoutAnInstallChangesNothing() throws {
        let removed = try ClaudeSettings.removing(from: Data(existingSettings.utf8))

        #expect(String(decoding: removed, as: UTF8.self) == existingSettings)
    }

    @Test func aHookTheUserAddedNextToOursSurvivesRemoval() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        let ours = try #require(try commands(in: installed, event: "Stop").first)
        let shared = """
        {"hooks": {"Stop": [{"hooks": [{"type": "command", "command": "say done"}, \
        {"type": "command", "command": \(String(decoding: try JSONEncoder().encode(ours), as: UTF8.self))}]}]}}
        """

        let removed = try ClaudeSettings.removing(from: Data(shared.utf8))

        #expect(try commands(in: removed, event: "Stop") == ["say done"])
    }
}

@Suite struct InstallingIntoTheSettingsFile {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func aBackupOfTheOriginalIsTakenBeforeTheFirstChangeOnly() throws {
        let directory = try temporaryDirectory()
        let installer = ConnectionInstaller(
            settings: directory.appendingPathComponent("settings.json"),
            backup: directory.appendingPathComponent("settings.backup.json")
        )
        try Data(existingSettings.utf8).write(to: installer.settings)

        try installer.install(connection)
        try installer.install(HookConnection(port: 2222, token: "other"))

        #expect(try String(contentsOf: installer.backup, encoding: .utf8) == existingSettings)
        #expect(installer.isInstalled(HookConnection(port: 2222, token: "other")))
        #expect(!installer.isInstalled(connection))
    }

    @Test func aMissingSettingsFileIsCreatedAndRemovalEmptiesItAgain() throws {
        let directory = try temporaryDirectory()
        let installer = ConnectionInstaller(
            settings: directory.appendingPathComponent(".claude/settings.json"),
            backup: directory.appendingPathComponent("backup.json")
        )

        try installer.install(connection)
        #expect(installer.isInstalled(connection))
        #expect(!FileManager.default.fileExists(atPath: installer.backup.path))

        try installer.remove()
        #expect(!installer.isInstalled(connection))
        #expect(try String(contentsOf: installer.settings, encoding: .utf8) == "{}\n")
    }

    @Test func aMalformedSettingsFileIsLeftUntouched() throws {
        let directory = try temporaryDirectory()
        let installer = ConnectionInstaller(
            settings: directory.appendingPathComponent("settings.json"),
            backup: directory.appendingPathComponent("backup.json")
        )
        let broken = "{ \"hooks\": { oops"
        try Data(broken.utf8).write(to: installer.settings)

        #expect(throws: SettingsError.self) { try installer.install(connection) }
        #expect(throws: SettingsError.self) { try installer.remove() }

        #expect(try String(contentsOf: installer.settings, encoding: .utf8) == broken)
        #expect(!FileManager.default.fileExists(atPath: installer.backup.path))
    }

    @Test func theSettingsFileStaysPrivateAndASymlinkStaysASymlink() throws {
        let directory = try temporaryDirectory()
        let real = directory.appendingPathComponent("dotfiles-settings.json")
        let link = directory.appendingPathComponent("settings.json")
        try Data(existingSettings.utf8).write(to: real)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: real.path)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        let installer = ConnectionInstaller(settings: link, backup: directory.appendingPathComponent("backup.json"))

        try installer.install(connection)

        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
        #expect(ClaudeSettings.isInstalled(connection, in: try Data(contentsOf: real)))
        let permissions = try FileManager.default.attributesOfItem(atPath: real.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
    }
}
