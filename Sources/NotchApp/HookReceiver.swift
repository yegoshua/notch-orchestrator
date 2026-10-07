import ClaudeConnection
import Foundation
import Network

/// A local HTTP server bound to the loopback interface that accepts hook posts from Claude Code.
final class HookReceiver {
    private let listener: NWListener
    private let token: String
    private let onPayload: @MainActor (Data) -> Void
    private let onStatusLine: @MainActor (Data) -> Void
    private let queue = DispatchQueue(label: "hook-receiver")

    init(
        port: Int, token: String,
        onStatusLine: @escaping @MainActor (Data) -> Void = { _ in },
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
