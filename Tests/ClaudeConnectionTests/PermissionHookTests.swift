import Foundation
import Network
import Testing
import ClaudeConnection

private let headerPath = "/Users/me/Library/Application Support/notch/hook-header"

private func hooks(in settings: Data, event: String) throws -> [[String: Any]] {
    let root = try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
    let hooks = try #require(root["hooks"] as? [String: Any])
    return (hooks[event] as? [[String: Any]] ?? []).flatMap { $0["hooks"] as? [[String: Any]] ?? [] }
}

private func permissionCommand(port: Int, headerFile: String = headerPath) throws -> String {
    let connection = HookConnection(port: port, tokenHeaderFile: URL(fileURLWithPath: headerFile))
    let installed = try ClaudeSettings.installing(connection, into: nil)
    return try #require(try hooks(in: installed, event: "PermissionRequest").first?["command"] as? String)
}

private let existingSettings = """
{
  "hooks": {
    "PermissionRequest": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "~/bin/my-approver"
          }
        ]
      }
    ]
  },
  "model": "opus"
}

"""

@Suite struct InstallingThePermissionHook {
    private let connection = HookConnection(port: 47800, tokenHeaderFile: URL(fileURLWithPath: headerPath))

    @Test func permissionRequestsGetOneCommandHookThatPostsToTheReceiver() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        let entries = try hooks(in: installed, event: "PermissionRequest")
        let entry = try #require(entries.first)
        let command = try #require(entry["command"] as? String)

        #expect(entries.count == 1)
        #expect(entry["type"] as? String == "command")
        #expect(command.contains("http://127.0.0.1:47800/hook/PermissionRequest"))
        #expect(command.contains("-H @'\(headerPath)'"))
        #expect(!command.contains("X-Notch-Token"))
    }

    @Test func theCommandReturnsTheAnswerOnStandardOutputAndNothingElse() throws {
        let command = try permissionCommand(port: 47800)

        // The response body is the hook's output, so unlike the other hooks it is not thrown away.
        #expect(!command.contains("-o /dev/null"))
        #expect(command.hasPrefix("/usr/bin/curl -q -s "))
        #expect(command.contains("--noproxy '*'"))
        #expect(command.contains("2>/dev/null || true"))
    }

    @Test func curlGivesUpJustBeforeClaudeCodeWould() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        let entry = try #require(try hooks(in: installed, event: "PermissionRequest").first)
        let command = try #require(entry["command"] as? String)
        let timeout = try #require(entry["timeout"] as? Int)
        let limit = try #require(
            command.components(separatedBy: " -m ").dropFirst().first?.split(separator: " ").first.flatMap { Int($0) })

        #expect(timeout == ClaudeSettings.permissionHookTimeout)
        #expect(limit < timeout)
        #expect(limit >= timeout - 30)
    }

    @Test func theOtherHooksStayShortAndSilent() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        let entry = try #require(try hooks(in: installed, event: "PreToolUse").first)

        #expect(entry["timeout"] as? Int == 5)
        #expect((entry["command"] as? String)?.contains("-m 2 ") == true)
        #expect((entry["command"] as? String)?.contains("-o /dev/null") == true)
    }

    @Test func installingTwiceChangesNothingAndRemovalRestoresTheOriginalExactly() throws {
        let once = try ClaudeSettings.installing(connection, into: Data(existingSettings.utf8))
        let twice = try ClaudeSettings.installing(connection, into: once)

        #expect(twice == once)
        #expect(ClaudeSettings.isInstalled(connection, in: once))
        #expect(try hooks(in: once, event: "PermissionRequest").count == 2)
        #expect(try hooks(in: once, event: "PermissionRequest").first?["command"] as? String == "~/bin/my-approver")
        #expect(String(decoding: try ClaudeSettings.removing(from: once), as: UTF8.self) == existingSettings)
    }

    @Test func settingsFromBeforeThePermissionHookCountAsNotInstalled() throws {
        let installed = try ClaudeSettings.installing(connection, into: nil)
        var root = try #require(try JSONSerialization.jsonObject(with: installed) as? [String: Any])
        var hooks = try #require(root["hooks"] as? [String: Any])
        hooks["PermissionRequest"] = nil
        root["hooks"] = hooks
        let older = try JSONSerialization.data(withJSONObject: root)

        #expect(!ClaudeSettings.isInstalled(connection, in: older))
    }
}

private struct Run {
    var output: String
    var errors: String
    var status: Int32
    var seconds: Double
}

/// Runs a hook command the way Claude Code does: through a shell, with the payload on stdin.
private func run(_ command: String, shell: String = "/bin/sh", input: String) throws -> Run {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-c", command]
    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    let started = Date()
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errors = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Run(
        output: String(decoding: output, as: UTF8.self), errors: String(decoding: errors, as: UTF8.self),
        status: process.terminationStatus, seconds: Date().timeIntervalSince(started))
}

/// Stands in for the app's receiver: holds each post for a while, then answers with a fixed body.
private final class HoldingServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "holding-server")
    private let ready = DispatchSemaphore(value: 0)
    private let status: String
    private let body: String
    private let hold: Double
    private var requests: [String] = []

    init(status: String = "200 OK", body: String, hold: Double = 0.3) throws {
        self.status = status
        self.body = body
        self.hold = hold
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        listener = try NWListener(using: parameters)
        listener.stateUpdateHandler = { [ready] state in
            if case .ready = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success else { throw CocoaError(.featureUnsupported) }
    }

    var port: Int { Int(listener.port?.rawValue ?? 0) }
    var received: [String] { queue.sync { requests } }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            let buffer = buffer + (data ?? Data())
            let text = String(decoding: buffer, as: UTF8.self)
            let parts = text.components(separatedBy: "\r\n\r\n")
            let length = parts[0].components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)) }
            if parts.count > 1, let length, buffer.count >= parts[0].utf8.count + 4 + length {
                self.requests.append(text)
                let response = "HTTP/1.1 \(self.status)\r\nContent-Type: application/json\r\n"
                    + "Content-Length: \(self.body.utf8.count)\r\nConnection: close\r\n\r\n\(self.body)"
                self.queue.asyncAfter(deadline: .now() + self.hold) {
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
                }
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }
}

private let request = #"{"session_id": "c7e6b405", "hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": {"command": "./hello.sh"}}"# + "\n"
private let allow = #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#

/// The installed command, run for real against a listener on the loopback interface.
@Suite struct RunningThePermissionHook {
    private func headerFile() throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notch header \(UUID().uuidString)")
        try Data("X-Notch-Token: s3cret\n".utf8).write(to: file)
        return file
    }

    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func theAnswerOfTheReceiverIsExactlyWhatTheHookPrints(shell: String) throws {
        let server = try HoldingServer(body: allow)
        let header = try headerFile()
        defer { try? FileManager.default.removeItem(at: header) }
        let command = try permissionCommand(port: server.port, headerFile: header.path)

        let result = try run(command, shell: shell, input: request)

        #expect(result.output == allow)
        #expect(result.errors == "")
        #expect(result.status == 0)
        // It waited for the answer instead of giving up after the two seconds the other hooks get.
        #expect(result.seconds >= 0.3)
        let received = try #require(server.received.first)
        #expect(received.hasPrefix("POST /hook/PermissionRequest HTTP/1.1\r\n"))
        #expect(received.contains("X-Notch-Token: s3cret\r\n"))
        #expect(received.hasSuffix("\r\n\r\n" + request))
        #expect(!command.contains("s3cret"))
    }

    /// Whatever answers with an error is not the app deciding: its body must not reach Claude Code.
    @Test(arguments: ["401 Unauthorized", "500 Internal Server Error"])
    func theBodyOfAnErrorResponseIsNotPrinted(status: String) throws {
        let server = try HoldingServer(status: status, body: allow, hold: 0)
        let header = try headerFile()
        defer { try? FileManager.default.removeItem(at: header) }

        let result = try run(try permissionCommand(port: server.port, headerFile: header.path), input: request)

        #expect(result.output == "")
        #expect(result.errors == "")
        #expect(result.status == 0)
    }

    @Test func anEmptyAnswerPrintsNothingSoClaudeCodeKeepsItsOwnDialog() throws {
        let server = try HoldingServer(body: "", hold: 0)
        let header = try headerFile()
        defer { try? FileManager.default.removeItem(at: header) }

        let result = try run(try permissionCommand(port: server.port, headerFile: header.path), input: request)

        #expect(result.output == "")
        #expect(result.errors == "")
        #expect(result.status == 0)
    }

    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func withNothingListeningItPrintsNothingAndSucceedsAtOnce(shell: String) throws {
        // Port 9 on the loopback interface: nothing listens there, as when the app is not running.
        let result = try run(try permissionCommand(port: 9), shell: shell, input: request)

        #expect(result.output == "")
        #expect(result.errors == "")
        #expect(result.status == 0)
        #expect(result.seconds < 2)
    }

    @Test func aHeaderFilePathWithAQuoteCannotBreakOutOfTheCommand() throws {
        let result = try run(
            try permissionCommand(port: 9, headerFile: "/tmp/o'brien; echo injected/hook-header"), input: request)

        #expect(result.output == "")
        #expect(result.status == 0)
    }
}
