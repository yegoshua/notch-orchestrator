import ClaudeConnection
import Foundation
import Network

/// A local HTTP server bound to the loopback interface that accepts hook posts from Claude Code.
final class HookReceiver {
    private let listener: NWListener
    private let token: String
    private let onPayload: @MainActor (Data) -> Void
    private let onStatusLine: @MainActor (Data) -> Void
    private let onPermissionRequest: @MainActor (Data, HeldRequest) -> Void
    private let queue = DispatchQueue(label: "hook-receiver")

    init(
        port: Int, token: String,
        onStatusLine: @escaping @MainActor (Data) -> Void = { _ in },
        onPermissionRequest: @escaping @MainActor (Data, HeldRequest) -> Void = { _, held in held.respond(with: Data()) },
        onPayload: @escaping @MainActor (Data) -> Void
    ) throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        listener = try NWListener(using: parameters)
        self.token = token
        self.onPayload = onPayload
        self.onStatusLine = onStatusLine
        self.onPermissionRequest = onPermissionRequest
    }

    func start(onFailure: @escaping @MainActor (NWError) -> Void) {
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.read(connection, buffer: Data())
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error), .waiting(let error): Task { @MainActor in onFailure(error) }
            default: break
            }
        }
        listener.start(queue: queue)
    }

    private func read(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            buffer.append(data ?? Data())
            switch HTTPRequest.parse(buffer) {
            case .complete(let request):
                self.respond(to: request, on: connection)
            case .incomplete where !isComplete && error == nil && buffer.count < 8 << 20:
                self.read(connection, buffer: buffer)
            case .incomplete, .invalid:
                self.send(status: "400 Bad Request", on: connection)
            }
        }
    }

    private func respond(to request: HTTPRequest, on connection: NWConnection) {
        guard request.headers[ClaudeSettings.tokenHeader.lowercased()] == token else {
            send(status: "401 Unauthorized", on: connection)
            return
        }
        // The status line wrapper posts what Claude Code gave the status line.
        if request.method == "POST", request.path == ClaudeSettings.statusLinePath {
            let payload = request.body
            Task { @MainActor in self.onStatusLine(payload) }
            send(status: "200 OK", on: connection)
            return
        }
        guard request.method == "POST", request.path.hasPrefix("/hook/") else {
            send(status: "404 Not Found", on: connection)
            return
        }
        let body = request.body
        // A permission request is not answered here: its connection stays open until the user
        // decides, the request is settled elsewhere, or the app gives up waiting.
        if request.path == "/hook/\(ClaudeSettings.permissionEvent)" {
            let held = HeldRequest(connection: connection, queue: queue)
            held.watchForClientLeaving()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.onPermissionRequest(body, held) }
            }
            return
        }
        Task { @MainActor in self.onPayload(body) }
        send(status: "200 OK", on: connection)
    }

    private func send(status: String, on connection: NWConnection) {
        let response = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

/// The open connection of a permission hook that waits for its answer.
final class HeldRequest: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    /// Answered, or abandoned by the client. Touched on `queue` only.
    private var isFinished = false
    /// Called once if the client closes the connection before any answer.
    @MainActor var onClientGone: (() -> Void)?

    fileprivate init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    /// Answers the hook and closes the connection. An empty body is "no decision". Does nothing
    /// when the connection was already answered or the client is gone.
    func respond(with body: Data) {
        queue.async {
            guard !self.isFinished else { return }
            self.isFinished = true
            let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                + "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
            self.connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in
                self.connection.cancel()
            })
        }
    }

    /// The client has sent its whole request, so the only thing left to read is the end of the
    /// connection: curl exiting or being killed.
    fileprivate func watchForClientLeaving() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { _, _, isComplete, error in
            guard !self.isFinished else { return }
            guard isComplete || error != nil else {
                self.watchForClientLeaving()
                return
            }
            self.isFinished = true
            self.connection.cancel()
            // The main queue keeps this behind the delivery of the request itself.
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.onClientGone?() }
            }
        }
    }
}

struct HTTPRequest {
    enum ParseResult {
        case complete(HTTPRequest)
        case incomplete
        case invalid
    }

    var method: String
    var path: String
    /// Header names are lowercased.
    var headers: [String: String]
    var body: Data

    static func parse(_ data: Data) -> ParseResult {
        guard let headEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return .incomplete }
        let lines = String(decoding: data[data.startIndex..<headEnd.lowerBound], as: UTF8.self)
            .components(separatedBy: "\r\n")
        let requestLine = lines[0].split(separator: " ")
        guard requestLine.count == 3 else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = headers["content-length"].flatMap(Int.init) ?? 0
        let body = data[headEnd.upperBound...]
        guard length >= 0, body.count >= length else { return length < 0 ? .invalid : .incomplete }
        return .complete(HTTPRequest(
            method: String(requestLine[0]), path: String(requestLine[1]),
            headers: headers, body: Data(body.prefix(length))))
    }
}
