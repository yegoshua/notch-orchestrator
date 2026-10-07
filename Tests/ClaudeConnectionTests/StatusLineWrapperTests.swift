import Foundation
import Network
import Testing
import ClaudeConnection

/// Port 9 on the loopback interface: nothing listens there, as when the app is not running.
private let connection = HookConnection(
    port: 9, tokenHeaderFile: URL(fileURLWithPath: "/Users/me/Library/Application Support/notch/hook-header"))

private func settings(statusLine: String?) -> String {
    let member = statusLine.map { "  \"statusLine\": \($0),\n" } ?? ""
    return "{\n  \"model\": \"opus\",\n\(member)  \"cleanupPeriodDays\": 30\n}\n"
}

private func quoted(_ string: String) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    return String(decoding: try! encoder.encode(string), as: UTF8.self)
}

private func commandStatusLine(_ command: String) -> String {
    "{\n    \"type\": \"command\",\n    \"command\": \(quoted(command)),\n    \"padding\": 0\n  }"
}

private func statusLine(in settings: Data) throws -> [String: Any]? {
    let root = try #require(try JSONSerialization.jsonObject(with: settings) as? [String: Any])
    return root["statusLine"] as? [String: Any]
}

private func installedCommand(over previous: String?) throws -> String {
    let original = settings(statusLine: previous.map(commandStatusLine))
    let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))
    return try #require(try statusLine(in: installed)?["command"] as? String)
}

private struct Run {
    var output: String
    var errors: String
    var status: Int32
}

/// Runs a status line command the way Claude Code does: through a shell, with the payload on stdin.
private func run(_ command: String, shell: String = "/bin/sh", input: String) throws -> Run {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-c", command]
    let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = stderr
    try process.run()
    stdin.fileHandleForWriting.write(Data(input.utf8))
    try stdin.fileHandleForWriting.close()
    // Reading to the end also proves that nothing left running in the background holds the output open.
    let output = stdout.fileHandleForReading.readDataToEndOfFile()
    let errors = stderr.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return Run(
        output: String(decoding: output, as: UTF8.self), errors: String(decoding: errors, as: UTF8.self),
        status: process.terminationStatus)
}

private let payload = #"{"session_id": "e9952653", "rate_limits": {"five_hour": {"used_percentage": 29, "resets_at": 1791380400}}}"# + "\n"

@Suite struct InstallingTheStatusLineWrapper {
    @Test func settingsWithoutAStatusLineGetTheWrapper() throws {
        let installed = try ClaudeSettings.installing(connection, into: Data(settings(statusLine: nil).utf8))
        let statusLine = try #require(try statusLine(in: installed))
        let command = try #require(statusLine["command"] as? String)

        #expect(statusLine["type"] as? String == "command")
        #expect(command.contains("http://127.0.0.1:9/statusline"))
        #expect(command.contains("-H @'/Users/me/Library/Application Support/notch/hook-header'"))
    }

    @Test func anExistingStatusLineIsWrappedInPlaceWithItsOtherOptionsKept() throws {
        let original = settings(statusLine: commandStatusLine("~/.claude/statusline.sh"))
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))
        let text = String(decoding: installed, as: UTF8.self)
        let statusLine = try #require(try statusLine(in: installed))
        let command = try #require(statusLine["command"] as? String)

        #expect(command.contains("http://127.0.0.1:9/statusline"))
        #expect(command.contains("~/.claude/statusline.sh"))
        #expect(statusLine["padding"] as? Int == 0)
        // Still between the same neighbours, not moved to the end.
        let model = try #require(text.range(of: "\"model\""))
        let line = try #require(text.range(of: "\"statusLine\""))
        let cleanup = try #require(text.range(of: "\"cleanupPeriodDays\""))
        #expect(model.lowerBound < line.lowerBound && line.lowerBound < cleanup.lowerBound)
    }

    @Test func installingTwiceChangesNothingTheSecondTime() throws {
        for previous in [nil, commandStatusLine("~/.claude/statusline.sh")] {
            let once = try ClaudeSettings.installing(connection, into: Data(settings(statusLine: previous).utf8))
            let twice = try ClaudeSettings.installing(connection, into: once)

            #expect(twice == once)
            #expect(ClaudeSettings.isInstalled(connection, in: once))
        }
    }

    @Test func installingAgainReplacesAStaleWrapperWithoutNestingIt() throws {
        let original = Data(settings(statusLine: commandStatusLine("~/.claude/statusline.sh")).utf8)
        let moved = HookConnection(port: 1111, tokenHeaderFile: connection.tokenHeaderFile)
        let old = try ClaudeSettings.installing(moved, into: original)

        #expect(!ClaudeSettings.isInstalled(connection, in: old))
        #expect(try ClaudeSettings.installing(connection, into: old) == (try ClaudeSettings.installing(connection, into: original)))
    }

    @Test func theSecretIsNotInTheSettings() throws {
        let command = try installedCommand(over: nil)

        #expect(!command.contains("X-Notch-Token"))
    }

    @Test(arguments: [
        #""~/.claude/statusline.sh""#,
        "null",
        "{\n    \"type\": \"command\"\n  }",
        "{\n    \"type\": \"command\",\n    \"command\": 5\n  }",
    ])
    func aStatusLineOfAnUnknownShapeIsLeftAlone(statusLine: String) throws {
        let original = settings(statusLine: statusLine)
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))
        let before = try #require(try JSONSerialization.jsonObject(with: Data(original.utf8)) as? NSDictionary)
        let after = try #require(try JSONSerialization.jsonObject(with: installed) as? NSDictionary)

        #expect(try #require(after["statusLine"] as? NSObject) == before["statusLine"] as? NSObject)
        #expect(ClaudeSettings.isInstalled(connection, in: installed))
        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }
}

@Suite struct RemovingTheStatusLineWrapper {
    @Test func removalRestoresThePreviousStatusLineExactly() throws {
        let original = settings(statusLine: commandStatusLine("~/.claude/statusline.sh"))
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))

        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }

    @Test func removalLeavesNoStatusLineWhereThereWasNone() throws {
        let original = settings(statusLine: nil)
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))

        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }

    @Test(arguments: [
        "",
        "echo 'it''s' \"$HOME\" '\\''",
        "jq -r '.model.display_name' # my status line",
        "printf '%s\\n' \"a | b\" | eval 'cat'\nprintf second",
        "__notch_previous='x'; echo \\",
        "echo été ✓ # notch-orchestrator",
    ])
    func anyPreviousCommandComesBackCharacterForCharacter(previous: String) throws {
        let original = settings(statusLine: commandStatusLine(previous))
        let installed = try ClaudeSettings.installing(connection, into: Data(original.utf8))
        let again = try ClaudeSettings.installing(connection, into: installed)

        #expect(again == installed)
        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }

    @Test func aStatusLineTheUserSetAfterwardsIsNotTouched() throws {
        let original = settings(statusLine: commandStatusLine("~/bin/new-status # notch-orchestrator"))

        #expect(String(decoding: try ClaudeSettings.removing(from: Data(original.utf8)), as: UTF8.self) == original)
    }
}

/// The installed command, run for real with nothing listening on the port.
@Suite struct RunningTheStatusLineWrapper {
    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func thePreviousCommandsOutputIsShownUnchanged(shell: String) throws {
        let previous = "printf '  \\033[32m%s\\033[0m  \\n\\nline two' \"it's 100% fine\""
        let direct = try run(previous, shell: shell, input: payload)

        let wrapped = try run(try installedCommand(over: previous), shell: shell, input: payload)

        #expect(wrapped.output == direct.output)
        #expect(wrapped.output.contains("it's 100% fine"))
        #expect(wrapped.errors == "")
        #expect(wrapped.status == 0)
    }

    @Test func thePreviousCommandReceivesThePayloadUnchanged() throws {
        let wrapped = try run(try installedCommand(over: "cat"), input: payload)

        #expect(wrapped.output == payload)
    }

    @Test func thePreviousCommandsExitStatusAndErrorsAreItsOwn() throws {
        let wrapped = try run(try installedCommand(over: "echo partial; echo broken >&2; exit 3"), input: payload)

        #expect(wrapped.output == "partial\n")
        #expect(wrapped.errors == "broken\n")
        #expect(wrapped.status == 3)
    }

    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"])
    func withoutAPreviousCommandItPrintsNothingAndSucceeds(shell: String) throws {
        let wrapped = try run(try installedCommand(over: nil), shell: shell, input: payload)

        #expect(wrapped.output == "")
        #expect(wrapped.errors == "")
        #expect(wrapped.status == 0)
    }

    @Test func aHeaderFilePathWithAQuoteCannotBreakOutOfTheCommand() throws {
        let odd = HookConnection(port: 9, tokenHeaderFile: URL(fileURLWithPath: "/tmp/o'brien; echo injected/hook-header"))
        let original = settings(statusLine: commandStatusLine("echo mine"))
        let installed = try ClaudeSettings.installing(odd, into: Data(original.utf8))
        let command = try #require(try statusLine(in: installed)?["command"] as? String)

        let wrapped = try run(command, input: payload)

        #expect(wrapped.output == "mine\n")
        #expect(String(decoding: try ClaudeSettings.removing(from: installed), as: UTF8.self) == original)
    }
}

/// Stands in for the app's receiver: accepts posts on a free loopback port and keeps what arrived.
private final class RecordingServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "recording-server")
    private let ready = DispatchSemaphore(value: 0)
    private let arrived = DispatchSemaphore(value: 0)
    private var requests: [String] = []

    init() throws {
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

    /// The next request, head and body, or nil when none arrives in time.
    func nextRequest(within seconds: Double = 5) -> String? {
        guard arrived.wait(timeout: .now() + seconds) == .success else { return nil }
        return queue.sync { requests.removeFirst() }
    }

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
                self.arrived.signal()
                let response = "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            } else if isComplete || error != nil {
                connection.cancel()
            } else {
                self.read(connection, buffer: buffer)
            }
        }
    }
}

/// The installed command, run for real with a receiver listening.
@Suite struct ForwardingTheStatusLinePayload {
    @Test(arguments: ["/bin/sh", "/bin/bash", "/bin/zsh"], [nil, "echo mine"] as [String?])
    func thePayloadReachesTheReceiverWithTheTokenFromTheHeaderFile(shell: String, previous: String?) throws {
        let server = try RecordingServer()
        let headerFile = FileManager.default.temporaryDirectory.appendingPathComponent("notch header \(UUID().uuidString)")
        try Data("X-Notch-Token: s3cret\n".utf8).write(to: headerFile)
        defer { try? FileManager.default.removeItem(at: headerFile) }
        let original = settings(statusLine: previous.map(commandStatusLine))
        let installed = try ClaudeSettings.installing(
            HookConnection(port: server.port, tokenHeaderFile: headerFile), into: Data(original.utf8))
        let command = try #require(try statusLine(in: installed)?["command"] as? String)

        let wrapped = try run(command, shell: shell, input: payload)
        let request = try #require(server.nextRequest())

        #expect(request.hasPrefix("POST /statusline HTTP/1.1\r\n"))
        #expect(request.contains("X-Notch-Token: s3cret\r\n"))
        #expect(request.hasSuffix("\r\n\r\n" + payload))
        #expect(wrapped.output == (previous == nil ? "" : "mine\n"))
        #expect(wrapped.errors == "")
        #expect(!command.contains("s3cret"))
    }
}
