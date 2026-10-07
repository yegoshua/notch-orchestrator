import Foundation
import SessionCore

/// A hook event sequence recorded during the prototype (see fixtures/README.md).
struct Fixture {
    struct Step {
        let event: HookEvent
        /// `SessionStart` only: startup, resume, clear or compact.
        let source: String?
        let at: Date
        /// `PermissionRequest` only: the identifier the held connection is known by.
        let requestID: String?
    }

    /// What the prototype receiver did with a held permission request.
    struct Response {
        let requestID: String
        /// The body it answered with; nil when it gave no decision or the client left first.
        let body: NSDictionary?
        /// True when the client closed the held connection before any answer.
        let clientDisconnected: Bool
        let at: Date
    }

    let steps: [Step]
    let responses: [Response]

    init(_ name: String, file: StaticString = #filePath) throws {
        let root = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("fixtures/\(name).jsonl")
        let timestamps = ISO8601DateFormatter()
        timestamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var steps: [Step] = []
        var responses: [Response] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let ts = record["ts"] as? String, let at = timestamps.date(from: ts),
                  let seq = record["seq"] as? Int
            else { continue }
            let requestID = record["event"] as? String == "PermissionRequest" ? "r\(seq)" : nil
            switch record["kind"] as? String {
            case "request":
                guard let payload = record["payload"] as? [String: Any] else { continue }
                let data = try JSONSerialization.data(withJSONObject: payload)
                if let event = HookEvent(payload: data) {
                    steps.append(Step(event: event, source: payload["source"] as? String, at: at, requestID: requestID))
                }
            case "response":
                guard let requestID, record["held"] as? Bool == true else { continue }
                responses.append(Response(
                    requestID: requestID, body: record["body"] as? NSDictionary,
                    clientDisconnected: record["resolved_by"] as? String == "client_disconnected", at: at))
            default:
                continue
            }
        }
        self.steps = steps
        self.responses = responses
    }

    /// Feeds steps into the core until `stop` returns true for a step (that step is fed too).
    /// Held connections the client dropped are reported at the moment the recording saw them go,
    /// unless `reportingDrops` is false, which is what the core sees when nobody notices the drop.
    /// `start` skips what an earlier call already fed.
    @discardableResult
    func play(
        into core: inout SessionCore, after start: Date = .distantPast, reportingDrops: Bool = true, through stop: (Step) -> Bool = { _ in false }
    ) -> Date {
        var last = Date.distantPast
        var drops = reportingDrops ? responses.filter(\.clientDisconnected) : []
        for step in steps where step.at > start {
            while let drop = drops.first, drop.at <= step.at {
                core.connectionDropped(drop.requestID, at: drop.at)
                drops.removeFirst()
            }
            core.handle(step.event, at: step.at, requestID: step.requestID)
            last = step.at
            if stop(step) { break }
        }
        return last
    }
}
