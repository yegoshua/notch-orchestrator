import Foundation

/// One Claude Code hook invocation, reduced to the fields the session core reads.
public struct HookEvent: Equatable, Sendable {
    public struct BackgroundTask: Equatable, Sendable {
        public var type: String
        public var status: String

        public init(type: String, status: String) {
            self.type = type
            self.status = status
        }
    }

    public var name: String
    public var sessionID: String
    /// `Stop` only: work that outlives the turn.
    public var backgroundTasks: [BackgroundTask]

    public init(
        name: String, sessionID: String, backgroundTasks: [BackgroundTask] = []
    ) {
        self.name = name
        self.sessionID = sessionID
        self.backgroundTasks = backgroundTasks
    }

    /// Decodes the JSON body Claude Code passes to a hook. Returns nil when it is not a hook payload.
    public init?(payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String
        else { return nil }
        let tasks = (object["background_tasks"] as? [[String: Any]] ?? []).map {
            BackgroundTask(type: $0["type"] as? String ?? "", status: $0["status"] as? String ?? "")
        }
        self.init(
            name: name, sessionID: sessionID, backgroundTasks: tasks
        )
    }
}
