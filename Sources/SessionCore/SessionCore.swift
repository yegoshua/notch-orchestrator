import Foundation

public enum SessionState: Equatable, Sendable {
    case working
    case finishedTurn
}

public struct Session: Equatable, Sendable {
    public var id: String
    public var state: SessionState
    /// When the session entered `state`.
    public var since: Date
}

public struct Counters: Equatable, Sendable {
    public var working: Int
    public var finished: Int

    public init(working: Int = 0, finished: Int = 0) {
        self.working = working
        self.finished = finished
    }
}

public struct Snapshot: Equatable, Sendable {
    /// Live sessions only, oldest state change first.
    public var sessions: [Session]
    public var counters: Counters
}

public struct Settings: Equatable, Sendable {
    /// How long a session stays live after it finished its turn.
    public var livenessThreshold: TimeInterval

    public init(livenessThreshold: TimeInterval = 600) {
        self.livenessThreshold = livenessThreshold
    }
}

/// The single source of truth for session state. Pure: no UI, no system access, no clock of its own.
public struct SessionCore {
    public var settings: Settings
    private var sessions: [String: Session] = [:]

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public mutating func handle(_ event: HookEvent, at time: Date) {
        sessions = sessions.filter { isLive($0.value, at: time) }
        switch event.name {
        case "UserPromptSubmit":
            enter(.working, event, at: time)
        case "Stop":
            // Background subagents hand their result back as a new prompt, so the turn is not over yet.
            // Background commands may run forever (a dev server) and do not count.
            let subagentsRunning = event.backgroundTasks.contains { $0.type == "subagent" && $0.status == "running" }
            if !subagentsRunning {
                enter(.finishedTurn, event, at: time)
            }
        case "StopFailure":
            // Shown as finished until the session list distinguishes failed turns.
            enter(.finishedTurn, event, at: time)
        case "SessionEnd":
            sessions[event.sessionID] = nil
        default:
            break
        }
    }

    public func snapshot(at time: Date) -> Snapshot {
        let live = sessions.values
            .filter { isLive($0, at: time) }
            .sorted { ($0.since, $0.id) < ($1.since, $1.id) }
        return Snapshot(
            sessions: live,
            counters: Counters(
                working: live.filter { $0.state == .working }.count,
                finished: live.filter { $0.state == .finishedTurn }.count
            )
        )
    }

    private func isLive(_ session: Session, at time: Date) -> Bool {
        switch session.state {
        case .working: true
        case .finishedTurn: time.timeIntervalSince(session.since) < settings.livenessThreshold
        }
    }

    private mutating func enter(_ state: SessionState, _ event: HookEvent, at time: Date) {
        sessions[event.sessionID] = Session(id: event.sessionID, state: state, since: time)
    }
}
