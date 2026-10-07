import Foundation

public enum SessionState: Equatable, Sendable {
    case working
    case finishedTurn
    case failed
    /// Something is going on that could not be confirmed. Never counted and never "needs the user".
    case unknown

    /// Whether a session in this state is blocked on the user. States that wait for a permission
    /// or an answer belong here.
    public var needsUser: Bool { self == .failed }

    /// Position in the list: what needs the user, then what is busy, then what is done.
    var rank: Int {
        if needsUser { return 0 }
        switch self {
        case .working: return 1
        case .finishedTurn, .failed: return 2
        case .unknown: return 3
        }
    }
}

public struct Subagent: Equatable, Sendable {
    public var id: String
    public var type: String
    /// What it was asked to do, in the words of the session that launched it.
    public var task: String?
    /// The tool call it is in, if any.
    public var activity: String?
}

public struct Session: Equatable, Sendable {
    public var id: String
    public var state: SessionState
    /// When the session entered `state`. For a working session, when its turn began.
    public var since: Date
    public var cwd: String?
    public var title: String?
    /// The tool call the session itself is in, if any.
    public var activity: String?
    /// Running subagents, in the order they were launched.
    public var subagents: [Subagent]

    public var project: String? { cwd.map { ($0 as NSString).lastPathComponent } }
    public var needsUser: Bool { state.needsUser }
}

public struct Counters: Equatable, Sendable {
    public var working: Int
    public var finished: Int
    public var failed: Int

    public init(working: Int = 0, finished: Int = 0, failed: Int = 0) {
        self.working = working
        self.finished = finished
        self.failed = failed
    }
}

public struct Snapshot: Equatable, Sendable {
    /// Live sessions only: those that need the user, then working, then finished, then unknown;
    /// within each, oldest state change first.
    public var sessions: [Session]
    public var counters: Counters
}

public struct Settings: Equatable, Sendable {
    /// How long a session stays live after it finished its turn.
    public var livenessThreshold: TimeInterval
    /// How long a turn may show no sign of life before it stops counting as working, when no
    /// process confirms that it is still going.
    public var unconfirmedWorkTimeout: TimeInterval

    public init(livenessThreshold: TimeInterval = 600, unconfirmedWorkTimeout: TimeInterval = 180) {
        self.livenessThreshold = livenessThreshold
        self.unconfirmedWorkTimeout = unconfirmedWorkTimeout
    }
}

/// The single source of truth for session state. Pure: no UI, no system access, no clock of its own.
public struct SessionCore {
    public var settings: Settings
    private var records: [String: Record] = [:]
    /// When sessions that reported their end did so. An observation made before that moment
    /// describes a session that is no longer there.
    private var endedAt: [String: Date] = [:]

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    /// Everything known about a session. It is shown only once it has a state.
    private struct Record {
        var id: String
        var state: SessionState?
        var since: Date
        var lastEventAt: Date
        var cwd: String?
        var transcriptPath: String?
        var firstPrompt: String?
        var observedTitle: String?
        var activity: String?
        var subagents: [Subagent] = []
        /// Tasks of `Agent` calls whose subagent has not reported its start yet, oldest first.
        var pendingAgentTasks: [String?] = []

        mutating func enter(_ state: SessionState, at time: Date) {
            self.state = state
            since = time
        }

        mutating func endTurn() {
            activity = nil
            subagents = []
            pendingAgentTasks = []
        }
    }

    // MARK: Hook events

    public mutating func handle(_ event: HookEvent, at time: Date) {
        prune(at: time)
        if event.name == "SessionEnd" {
            records[event.sessionID] = nil
            endedAt[event.sessionID] = time
            return
        }

        var record = records[event.sessionID]
            ?? Record(id: event.sessionID, since: time, lastEventAt: time)
        record.lastEventAt = time
        record.cwd = event.cwd ?? record.cwd
        record.transcriptPath = event.transcriptPath ?? record.transcriptPath
        let subagentID = event.agentID.flatMap { $0.isEmpty ? nil : $0 }

        switch event.name {
        case "SessionStart":
            if event.source == "compact" {
                record.activity = nil
            } else if record.state == .working {
                // A fresh start of a session we believed to be mid-turn: that turn died with its
                // process and never reported its end. Whatever the transcript says about it is
                // older than this moment and no longer counts.
                record.state = nil
                record.since = time
                record.endTurn()
            }
        case "UserPromptSubmit":
            // Claude Code submits a prompt of its own when background work reports back.
            let continuesTurn = event.prompt?.hasPrefix("<task-notification>") == true
            if !continuesTurn {
                record.pendingAgentTasks = []
                if record.firstPrompt == nil { record.firstPrompt = event.prompt.flatMap(Self.headline) }
            }
            if record.state != .working || !continuesTurn { record.enter(.working, at: time) }
            record.activity = nil
        case "PreToolUse":
            let activity = event.tool.map(Self.describe)
            if let subagentID {
                if let index = record.subagents.firstIndex(where: { $0.id == subagentID }) {
                    record.subagents[index].activity = activity
                } else if let type = event.agentType, !type.isEmpty {
                    record.subagents.append(Subagent(id: subagentID, type: type, activity: activity))
                }
                if record.state == nil { record.enter(.working, at: time) }
            } else {
                if let tool = event.tool, tool.name == "Agent" || tool.name == "Task" {
                    record.pendingAgentTasks.append(tool.subject)
                }
                record.activity = activity
                if record.state != .working { record.enter(.working, at: time) }
            }
        case "PostToolUse", "PostToolBatch":
            // A denied call reports no `PostToolUse` of its own, only the end of its batch.
            if let subagentID {
                if let index = record.subagents.firstIndex(where: { $0.id == subagentID }) {
                    record.subagents[index].activity = nil
                }
            } else {
                record.activity = nil
                // A turn written off as unconfirmed turns out to be going on.
                if record.state == .unknown { record.enter(.working, at: time) }
                // Every subagent of the batch has started by now: what is left was never launched.
                if event.name == "PostToolBatch" { record.pendingAgentTasks = [] }
            }
        case "SubagentStart":
            // An empty type is Claude Code's internal helper agent, not something the user launched.
            if let subagentID, let type = event.agentType, !type.isEmpty,
               !record.subagents.contains(where: { $0.id == subagentID }) {
                let task = record.pendingAgentTasks.isEmpty ? nil : record.pendingAgentTasks.removeFirst()
                record.subagents.append(Subagent(id: subagentID, type: type, task: task))
            }
        case "SubagentStop":
            record.subagents.removeAll { $0.id == subagentID }
        case "PreCompact":
            record.activity = Self.compacting
        case "PostCompact":
            if record.activity == Self.compacting { record.activity = nil }
        case "Stop":
            // Background subagents hand their result back as a new prompt, so the turn is not over yet.
            // Background commands may run forever (a dev server) and do not count.
            let running = event.backgroundTasks.filter { $0.type == "subagent" && $0.status == "running" }
            if running.isEmpty {
                record.enter(.finishedTurn, at: time)
                record.endTurn()
            } else {
                record.activity = nil
                record.pendingAgentTasks = []
                // One without an identifier keeps the turn open but cannot be followed or listed.
                record.subagents = running.filter { !$0.id.isEmpty }.map { task in
                    var subagent = record.subagents.first { $0.id == task.id }
                        ?? Subagent(id: task.id, type: task.agentType ?? "")
                    subagent.task = task.description ?? subagent.task
                    return subagent
                }
            }
        case "StopFailure":
            record.enter(.failed, at: time)
            record.endTurn()
        default:
            break
        }
        records[event.sessionID] = record
    }

    // MARK: Reconciliation

    /// Takes in what was observed about a session at `time`. Where it contradicts the hooks it wins,
    /// unless the hooks have spoken since: an observation is only as good as the moment it was made.
    /// A session the core has never heard of is rebuilt from the observation alone.
    public mutating func reconcile(_ observation: Observation, observedAt time: Date) {
        let known = records[observation.sessionID]
        if let known, known.lastEventAt > time { return }
        if known == nil, let ended = endedAt[observation.sessionID], ended >= time { return }
        if observation.process == .dead {
            records[observation.sessionID] = nil
            return
        }

        var record = known ?? Record(id: observation.sessionID, since: time, lastEventAt: time)
        record.cwd = record.cwd ?? observation.cwd
        record.transcriptPath = record.transcriptPath ?? observation.transcriptPath
        record.observedTitle = observation.title ?? record.observedTitle

        if let tail = observation.transcript {
            // Without a process behind it, a turn in progress is a guess.
            let confirmed = observation.process == .alive
            // The turn is over for good: no background agent is left to reopen it. When the
            // transcript does not count them, the subagents the hooks reported stand in.
            let closed: Bool
            switch tail.turn {
            case .inProgress: closed = false
            case .ended(let pending): closed = pending == 0 || (pending == nil && record.subagents.isEmpty)
            }
            switch (tail.turn, record.state) {
            case (.inProgress, .working):
                break
            case (.inProgress, nil) where known == nil, (.inProgress, .unknown):
                record.enter(confirmed ? .working : .unknown, at: tail.at)
            case (.inProgress, _) where tail.at > record.since:
                // A turn the hooks did not announce.
                record.enter(confirmed ? .working : .unknown, at: tail.at)
            case (.ended, .working) where closed && tail.at >= record.since,
                 (.ended, .unknown) where closed:
                // A turn the hooks did not close.
                record.enter(.finishedTurn, at: tail.at)
                record.endTurn()
            case (.ended, nil) where known == nil && closed:
                record.enter(.finishedTurn, at: tail.at)
            case (.ended, nil) where known == nil:
                // Background agents may or may not still be running: nothing here confirms either.
                record.enter(.unknown, at: tail.at)
            default:
                break
            }
        }
        // The hooks announced a turn, but no process stands behind it: it counts as working only
        // while a hook or the transcript has shown life recently.
        if observation.process != .alive, record.state == .working {
            var lastSign = record.lastEventAt
            if let tail = observation.transcript, tail.turn == .inProgress { lastSign = max(lastSign, tail.at) }
            if time.timeIntervalSince(lastSign) >= settings.unconfirmedWorkTimeout {
                record.enter(.unknown, at: lastSign)
                record.activity = nil
            }
        }
        // Only a session with something to show is worth remembering.
        if known != nil || record.state != nil { records[observation.sessionID] = record }
        prune(at: time)
    }

    /// Sessions reconciliation should look at: every one the core tracks, shown or not.
    public var trackedSessions: [(id: String, transcriptPath: String?)] {
        records.values.map { ($0.id, $0.transcriptPath) }
    }

    // MARK: Snapshot

    public func snapshot(at time: Date) -> Snapshot {
        let live = records.values
            .compactMap { record -> Session? in
                guard let state = record.state, isLive(state, since: record.since, at: time) else { return nil }
                return Session(
                    id: record.id, state: state, since: record.since, cwd: record.cwd,
                    title: record.observedTitle ?? record.firstPrompt, activity: record.activity,
                    subagents: record.subagents)
            }
            .sorted { ($0.state.rank, $0.since, $0.id) < ($1.state.rank, $1.since, $1.id) }
        return Snapshot(
            sessions: live,
            counters: Counters(
                working: live.filter { $0.state == .working }.count,
                finished: live.filter { $0.state == .finishedTurn }.count,
                failed: live.filter { $0.state == .failed }.count
            )
        )
    }

    private func isLive(_ state: SessionState, since: Date, at time: Date) -> Bool {
        switch state {
        case .working: true
        case .finishedTurn, .failed, .unknown: time.timeIntervalSince(since) < settings.livenessThreshold
        }
    }

    /// Forgets sessions that stopped being live, and sessions that never had a turn and went quiet.
    private mutating func prune(at time: Date) {
        records = records.filter { _, record in
            if let state = record.state { return isLive(state, since: record.since, at: time) }
            return time.timeIntervalSince(record.lastEventAt) < settings.livenessThreshold
        }
        endedAt = endedAt.filter { time.timeIntervalSince($0.value) < settings.livenessThreshold }
    }

    private static let compacting = "Compacting"

    private static func describe(_ tool: HookEvent.Tool) -> String {
        guard let subject = tool.subject.flatMap(headline) else { return tool.name }
        return "\(tool.name): \(subject)"
    }

    /// The first non-empty line, cut to a length that fits one row.
    private static func headline(_ text: String) -> String? {
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 120 ? line.prefix(119) + "…" : line
    }
}
