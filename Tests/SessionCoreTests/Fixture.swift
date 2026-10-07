import Foundation
import SessionCore

/// A hook event sequence recorded during the prototype (see fixtures/README.md).
struct Fixture {
    struct Step {
        let event: HookEvent
        /// `SessionStart` only: startup, resume, clear or compact.
        let source: String?
        let at: Date
    }

    let steps: [Step]

    init(_ name: String, file: StaticString = #filePath) throws {
        let root = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let url = root.appendingPathComponent("fixtures/\(name).jsonl")
        let timestamps = ISO8601DateFormatter()
        timestamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        var steps: [Step] = []
        for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
            guard let record = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  record["kind"] as? String == "request",
                  let payload = record["payload"] as? [String: Any],
                  let ts = record["ts"] as? String, let at = timestamps.date(from: ts)
            else { continue }
            let data = try JSONSerialization.data(withJSONObject: payload)
            if let event = HookEvent(payload: data) {
                steps.append(Step(event: event, source: payload["source"] as? String, at: at))
            }
        }
        self.steps = steps
    }

    /// Feeds steps into the core until `stop` returns true for a step (that step is fed too).
    @discardableResult
    func play(into core: inout SessionCore, through stop: (Step) -> Bool = { _ in false }) -> Date {
        var last = Date.distantPast
        for step in steps {
            core.handle(step.event, at: step.at)
            last = step.at
            if stop(step) { break }
        }
        return last
    }
}
