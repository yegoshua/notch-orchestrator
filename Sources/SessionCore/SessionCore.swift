import Foundation

public enum SessionState: Equatable, Sendable {
    case working
    /// A tool call is held until the user allows or denies it.
    case waitingForPermission
    /// The agent asked a multiple-choice question.
    case waitingForAnswer
    case finishedTurn
    case failed
    /// Something is going on that could not be confirmed. Never counted and never "needs the user".
    case unknown

    /// Whether a session in this state is blocked on the user.
    public var needsUser: Bool { self == .failed || isWaiting }

    /// Whether the session waits for a permission or an answer.
    public var isWaiting: Bool { self == .waitingForPermission || self == .waitingForAnswer }

    /// Position in the list: what needs the user, then what is busy, then what is done.
    var rank: Int {
        if needsUser { return 0 }
        switch self {
        case .working, .waitingForPermission, .waitingForAnswer: return 1
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

/// How full a session's context is, as far as it is known.
public struct ContextUsage: Equatable, Sendable {
    /// What the last response was sent, counted from the transcript.
    public var tokens: Int?
    /// The share of the window, 0 to 100. Known only for sessions that run a status line: nothing
    /// else says how large the window is.
    public var usedPercentage: Double?

    public init(tokens: Int? = nil, usedPercentage: Double? = nil) {
        self.tokens = tokens
        self.usedPercentage = usedPercentage
    }
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
    /// Where the session runs, as far as reconciliation found out.
    public var location: SessionLocation = .unknown
    /// Nil while nothing is known about it.
    public var context: ContextUsage?
    /// The CI of what the session pushed last. Nil when it pushed nothing, or nothing with a pipeline.
    public var ci: SessionCI?

    public var origin: SessionOrigin { location.origin }
    public var project: String? { cwd.map { ($0 as NSString).lastPathComponent } }
    public var needsUser: Bool { state.needsUser }
}

public struct Counters: Equatable, Sendable {
    /// Sessions waiting for a permission or an answer.
    public var waiting: Int
    public var working: Int
    public var finished: Int
    public var failed: Int

    public init(waiting: Int = 0, working: Int = 0, finished: Int = 0, failed: Int = 0) {
        self.waiting = waiting
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
    /// Requests waiting for the user's decision, across all sessions, in the order they arrived.
    public var requests: [PendingRequest]
    /// Those of them the island is to put before the user by itself, expanded. The others wait
    /// to be looked for: their session is in front, or the user asked for quiet.
    public var raised: [PendingRequest]
    /// Merge requests that sessions pushed to and that no session in the list shows any more,
    /// by repository and number.
    public var mergeRequests: [FollowedMergeRequest] = []
}

public struct Settings: Equatable, Sendable {
    /// How long a session stays live after it finished its turn.
    public var livenessThreshold: TimeInterval
    /// How long a turn may show no sign of life before it stops counting as working, when no
    /// process confirms that it is still going.
    public var unconfirmedWorkTimeout: TimeInterval
    /// How long a request may go unanswered before it is given back to Claude Code's own dialog
    /// with no decision. Has to stay well below the time Claude Code lets the hook wait.
    public var requestTimeout: TimeInterval
    public var interruptionMode: InterruptionMode
    /// How long the pipeline of a push is looked for before the push is taken to have none.
    public var pipelineLookupTimeout: TimeInterval
    /// How long a running pipeline may go without being seen running before it is unknown.
    public var pipelineConfirmationTimeout: TimeInterval
    /// How often a followed merge request is asked about while nothing of it is running.
    public var mergeRequestInterval: TimeInterval

    public init(
        livenessThreshold: TimeInterval = 600, unconfirmedWorkTimeout: TimeInterval = 180,
        requestTimeout: TimeInterval = 300, interruptionMode: InterruptionMode = .smart,
        pipelineLookupTimeout: TimeInterval = 120, pipelineConfirmationTimeout: TimeInterval = 300,
        mergeRequestInterval: TimeInterval = 240
    ) {
        self.livenessThreshold = livenessThreshold
        self.unconfirmedWorkTimeout = unconfirmedWorkTimeout
        self.requestTimeout = requestTimeout
        self.interruptionMode = interruptionMode
        self.pipelineLookupTimeout = pipelineLookupTimeout
        self.pipelineConfirmationTimeout = pipelineConfirmationTimeout
        self.mergeRequestInterval = mergeRequestInterval
    }
}

/// The single source of truth for session state. Pure: no UI, no system access, no clock of its own.
public struct SessionCore {
    public var settings: Settings
    private var records: [String: Record] = [:]
    /// When sessions that reported their end did so. An observation made before that moment
    /// describes a session that is no longer there.
    private var endedAt: [String: Date] = [:]
    /// Ends of requests nobody has collected yet.
    private var resolutions: [Resolution] = []
    /// Numbers requests in the order they arrived; two may arrive in the same instant.
    private var requestCount = 0
    private var attention = Attention()
    /// Interruptions nobody has collected yet.
    private var interruptions: [Interruption] = []
    /// The merge requests sessions pushed to. They outlive their sessions.
    private var mergeRequests: [FollowedMergeRequest.ID: TrackedMergeRequest] = [:]

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
        var location = SessionLocation.unknown
        var context = ContextUsage()
        var activity: String?
        var subagents: [Subagent] = []
        /// Tasks of `Agent` calls whose subagent has not reported its start yet, oldest first.
        var pendingAgentTasks: [String?] = []
        /// Requests not known to be settled, oldest first, including those handed back to the
        /// session's own dialog. While there is one the session waits.
        var requests: [Request] = []
        /// When the turn began that the session will go back to once it stops waiting.
        var interruptedTurnBegan: Date?
        /// The state is `unknown` because a request ran out of time. The transcript still ending
        /// in that tool call is then no sign of work.
        var gaveUpWaiting = false
        /// The CI of the push the session is followed for: its latest.
        var ci: FollowedCI?
        /// The requests the desktop app tied to the session.
        var desktopRequests: [RequestLink] = []

        mutating func enter(_ state: SessionState, at time: Date) {
            self.state = state
            since = time
            gaveUpWaiting = false
        }

        /// Brings the state in line with the open requests: waiting while there is one, back in
        /// the interrupted turn when the last one went.
        mutating func requestsChanged(at time: Date) {
            if let oldest = requests.first {
                if state?.isWaiting != true {
                    interruptedTurnBegan = state == .working ? since : nil
                    since = time
                }
                state = oldest.questions.isEmpty ? .waitingForPermission : .waitingForAnswer
                gaveUpWaiting = false
            } else if state?.isWaiting == true {
                enter(.working, at: interruptedTurnBegan ?? time)
            }
        }

        mutating func endTurn() {
            activity = nil
            subagents = []
            pendingAgentTasks = []
        }
    }

    /// The CI of a push as the core keeps it.
    private struct FollowedCI {
        /// Nil until the repository was read after the push.
        var push: Push?
        var state = CIState.pending
        var url: String?
        /// The request of the pushed branch, as looked up on the host.
        var request: RequestLink?
        /// When the push was reported, and after that when its pipeline was last seen.
        var confirmedAt: Date
        /// When the pipeline reached the state it stays in.
        var endedAt: Date?
        /// When a push was reported that the repository has not been read for yet.
        var unreadSince: Date?
        /// The request of this push was taken up to be followed, or found not to be one to
        /// follow. Once per push: a request the user stopped following stays so until the next.
        var requestWasTakenUp = false
    }

    /// A followed merge request as the core keeps it.
    private struct TrackedMergeRequest {
        var shown: FollowedMergeRequest
        /// When the host was last asked about it. Nil while it never was since it came to be
        /// followed, since the app started, or since a session pushed to it.
        var askedAt: Date?
    }

    /// A request as the core keeps it.
    private struct Request {
        var id: String
        var order: Int
        /// The subagent that asked; nil for the session itself.
        var agentID: String?
        var toolName: String
        var input: JSONValue?
        var questions: [Question]
        var arrivedAt: Date
        /// Set once the user left the request to the session's own dialog. Its connection is
        /// released by then; what remains is the knowledge that the session waits.
        var handedBackAt: Date?
        /// Put before the user by the island itself.
        var isRaised = false
        /// Its session has been seen in front since it asked, so the user has seen its own dialog.
        var wasSeenInFront = false
        /// A sound has been made for it. There is never a second one.
        var wasAnnounced = false
    }

    // MARK: Hook events

    /// Takes in a hook event. A `PermissionRequest` whose connection is held open comes with the
    /// `requestID` its resolution is to carry.
    public mutating func handle(_ event: HookEvent, at time: Date, requestID: String? = nil) {
        advance(to: time)
        defer { reviewRequests() }
        if event.name == "SessionEnd" {
            release(records[event.sessionID]?.requests ?? [])
            records[event.sessionID] = nil
            endedAt[event.sessionID] = time
            return
        }

        var record = records[event.sessionID]
            ?? Record(id: event.sessionID, since: time, lastEventAt: time)
        let stateBefore = record.state
        record.lastEventAt = time
        record.cwd = event.cwd ?? record.cwd
        record.transcriptPath = event.transcriptPath ?? record.transcriptPath
        let subagentID = event.agentID.flatMap { $0.isEmpty ? nil : $0 }
        settle(&record, by: event, from: subagentID, at: time)

        switch event.name {
        case "PermissionRequest":
            guard let requestID else { break }
            guard let tool = event.tool else {
                // Nothing to show the user: Claude Code's own dialog has to do.
                resolutions.append(Resolution(requestID: requestID, outcome: .noDecision))
                break
            }
            requestCount += 1
            record.requests.append(Request(
                id: requestID, order: requestCount, agentID: subagentID, toolName: tool.name, input: tool.input,
                questions: RequestPresentation.questions(tool: tool.name, input: tool.input), arrivedAt: time))
            record.requestsChanged(at: time)
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
                // A call that starts next to one that waits for permission changes nothing about the wait.
                if record.state != .working, record.requests.isEmpty { record.enter(.working, at: time) }
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
            // What was known describes the context before it was rewritten.
            record.context = ContextUsage()
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
        // A push counts once it returned, whichever agent of the session made it. Which commit
        // went out is for the repository to say.
        if event.name == "PostToolUse", let tool = event.tool, tool.name == "Bash",
           let command = tool.input?["command"]?.string ?? tool.subject, PushCommand.isPush(command) {
            if record.ci == nil { record.ci = FollowedCI(confirmedAt: time) }
            record.ci?.unreadSince = time
        }
        // A subagent may still be asking when its session's own turn moves on.
        record.requestsChanged(at: time)
        records[event.sessionID] = record
        if record.state != stateBefore { announceTurnEnd(of: record) }
    }

    /// Removes the requests `event` shows to be settled outside the app. The request payload has
    /// no call identifier and nothing cancels a held hook when the human answers in the session,
    /// so this is the only way to learn of it.
    private mutating func settle(_ record: inout Record, by event: HookEvent, from subagentID: String?, at time: Date) {
        guard !record.requests.isEmpty else { return }
        var settled: [Request] = []
        func take(where isSettled: (Request) -> Bool) {
            settled += record.requests.filter(isSettled)
            record.requests.removeAll(where: isSettled)
        }
        switch event.name {
        case "PostToolUse":
            // The call ran, so it was allowed. Another agent of the session making the same call
            // says nothing about this one.
            if let tool = event.tool, let index = record.requests.firstIndex(where: {
                $0.agentID == subagentID && RequestPresentation.isSameCall($0.toolName, $0.input, as: tool)
            }) {
                settled.append(record.requests.remove(at: index))
            }
        case "PostToolBatch":
            // Every call of the batch has run or was refused.
            take { $0.agentID == subagentID }
        case "UserPromptSubmit":
            // A prompt Claude Code submits itself continues the turn and settles nothing. One the
            // human typed means no dialog is open any more, whoever had asked.
            if event.prompt?.hasPrefix("<task-notification>") == true { return }
            take { _ in true }
        case "Stop", "StopFailure":
            take { $0.agentID == nil }
        case "SubagentStop":
            take { $0.agentID != nil && $0.agentID == subagentID }
        case "SessionStart" where event.source != "compact":
            take { _ in true }
        default:
            return
        }
        release(settled)
        record.requestsChanged(at: time)
    }

    // MARK: Requests

    /// Applies the user's decision to a request in the queue. A request that is no longer there,
    /// or a decision that does not fit it, changes nothing.
    public mutating func decide(_ decision: Decision, on requestID: String, at time: Date) {
        advance(to: time)
        defer { reviewRequests() }
        guard let (sessionID, index) = locate(requestID), var record = records[sessionID] else { return }
        let request = record.requests[index]
        let outcome: Outcome
        switch decision {
        case .handBack:
            record.requests[index].handedBackAt = time
            resolutions.append(Resolution(requestID: requestID, outcome: .noDecision))
            records[sessionID] = record
            return
        case .allow:
            // A question is answered, not allowed.
            guard request.questions.isEmpty else { return }
            outcome = .allow(updatedInput: nil)
        case .deny(let explanation):
            let message = explanation?.trimmingCharacters(in: .whitespacesAndNewlines)
            outcome = .deny(message: message?.isEmpty == false ? message : nil)
        case .answer(let choices):
            guard let input = RequestPresentation.answered(request.input, questions: request.questions, with: choices)
            else { return }
            outcome = .allow(updatedInput: input)
        }
        record.requests.remove(at: index)
        resolutions.append(Resolution(requestID: requestID, outcome: outcome))
        // The decision is news about the session as much as a hook is.
        record.lastEventAt = max(record.lastEventAt, time)
        record.requestsChanged(at: time)
        records[sessionID] = record
    }

    /// Whether the core still tracks the request: the caller owes it a held connection only then.
    public func isOpen(_ requestID: String) -> Bool {
        locate(requestID) != nil
    }

    /// The client closed the held connection of a request before any answer: the human refused
    /// the call in the session's own dialog, or the session is gone.
    public mutating func connectionDropped(_ requestID: String, at time: Date) {
        advance(to: time)
        defer { reviewRequests() }
        guard let (sessionID, index) = locate(requestID), var record = records[sessionID] else { return }
        release([record.requests.remove(at: index)])
        record.requestsChanged(at: time)
        records[sessionID] = record
    }

    /// Lets time pass: a request nobody answered in time is given back with no decision, never
    /// answered for the user, and its session is from then on unknown rather than waiting.
    public mutating func advance(to time: Date) {
        for id in Array(records.keys) {
            guard var record = records[id], !record.requests.isEmpty else { continue }
            func deadline(_ request: Request) -> Date {
                (request.handedBackAt ?? request.arrivedAt).addingTimeInterval(settings.requestTimeout)
            }
            let expired = record.requests.filter { deadline($0) <= time }
            guard let gaveUpAt = expired.map(deadline).max() else { continue }
            record.requests.removeAll { deadline($0) <= time }
            release(expired)
            if record.requests.isEmpty {
                record.enter(.unknown, at: gaveUpAt)
                record.gaveUpWaiting = true
                record.activity = nil
            } else {
                record.requestsChanged(at: time)
            }
            records[id] = record
        }
        for id in Array(records.keys) {
            guard var ci = records[id]?.ci else { continue }
            if let unread = ci.unreadSince, time.timeIntervalSince(unread) >= settings.pipelineLookupTimeout {
                // The repository would not say what was pushed.
                ci.unreadSince = nil
            }
            switch ci.state {
            case .pending where time.timeIntervalSince(ci.confirmedAt) >= settings.pipelineLookupTimeout:
                // No pipeline ever appeared: the repository has no CI, or none for this push.
                records[id]?.ci = nil
                continue
            case .running where time.timeIntervalSince(ci.confirmedAt) >= settings.pipelineConfirmationTimeout:
                ci.state = .unknown
                ci.endedAt = ci.confirmedAt.addingTimeInterval(settings.pipelineConfirmationTimeout)
            default:
                break
            }
            records[id]?.ci = ci
        }
        prune(at: time)
        reviewRequests()
    }

    /// Hands out, once, the ends of requests reached since the last call. Whoever holds the
    /// connections collects them after every input and delivers each to its connection.
    public mutating func drainResolutions() -> [Resolution] {
        defer { resolutions = [] }
        return resolutions
    }

    /// A request still in the queue.
    private func locate(_ requestID: String) -> (sessionID: String, index: Int)? {
        for record in records.values {
            if let index = record.requests.firstIndex(where: { $0.id == requestID && $0.handedBackAt == nil }) {
                return (record.id, index)
            }
        }
        return nil
    }

    /// Requests that went without the user deciding: their connections, where still held, are let
    /// go with no decision. One that was handed back has been let go already.
    private mutating func release(_ requests: [Request]) {
        resolutions += requests.filter { $0.handedBackAt == nil }
            .map { Resolution(requestID: $0.id, outcome: .noDecision) }
    }

    /// Takes in how full a session's context window is. A session the core does not track is
    /// not made up from it.
    public mutating func handle(_ report: ContextReport) {
        records[report.sessionID]?.context.usedPercentage = report.usedPercentage
    }

    // MARK: Interruptions

    /// Takes in what the user is looking at and whether a Focus is on.
    public mutating func attend(_ attention: Attention, at time: Date) {
        advance(to: time)
        self.attention = attention
        reviewRequests()
    }

    /// Hands out, once, what the island is to do by itself since the last call.
    public mutating func drainInterruptions() -> [Interruption] {
        defer { interruptions = [] }
        return interruptions
    }

    /// A Focus asks for quiet whatever the user chose for other times.
    private var mode: InterruptionMode {
        attention.focusIsOn ? .quiet : settings.interruptionMode
    }

    private enum Frontness {
        case notInFront
        /// Its application is in front and no other session runs there, so it is taken to be the
        /// one the user looks at. They may as well be in another window of that application.
        case assumed
        /// Terminal said that the session's tab is the one in front.
        case seen
    }

    /// Whether the user is looking at the session. Only Terminal says which of its tabs is in
    /// front; of any other application, and of Terminal when it does not say, that can only be
    /// assumed, and only of a session that is alone there.
    private func frontness(of record: Record) -> Frontness {
        guard let front = attention.frontWindow, let bundleID = record.location.bundleID, bundleID == front.bundleID
        else { return .notInFront }
        if case .terminalApp(let tty) = record.location, let frontTTY = front.terminalTTY {
            return tty == frontTTY ? .seen : .notInFront
        }
        let isAlone = !records.values.contains {
            $0.id != record.id && $0.state != nil && $0.location.bundleID == bundleID
        }
        return isAlone ? .assumed : .notInFront
    }

    /// Whether something about a session interrupts the user in `mode`.
    private static func interrupts(in mode: InterruptionMode, _ frontness: Frontness) -> Bool {
        mode == .loud || (mode == .smart && frontness == .notInFront)
    }

    /// Decides anew which requests the island puts before the user. Run after every input: a
    /// request, the front window, the Focus and the mode all bear on it.
    private mutating func reviewRequests() {
        let mode = mode
        var raised: [(order: Int, interruption: Interruption)] = []
        for (id, var record) in records where !record.requests.isEmpty {
            let frontness = frontness(of: record)
            for index in record.requests.indices where record.requests[index].handedBackAt == nil {
                var request = record.requests[index]
                request.wasSeenInFront = request.wasSeenInFront || frontness == .seen
                let raise = Self.interrupts(in: mode, frontness)
                if raise, !request.isRaised {
                    // Coming up again, or after the user saw the session's own dialog, is no news.
                    // A session only assumed to be in front may never have shown it to them.
                    let sound = !request.wasAnnounced && (mode == .loud || !request.wasSeenInFront)
                    request.wasAnnounced = request.wasAnnounced || sound
                    raised.append((request.order, .expand(requestID: request.id, sound: sound)))
                }
                request.isRaised = raise
                record.requests[index] = request
            }
            records[id] = record
        }
        interruptions += raised.sorted { $0.order < $1.order }.map(\.interruption)
    }

    /// The line for a turn that has just ended, unless the user is looking at the session anyway.
    private mutating func announceTurnEnd(of record: Record) {
        guard record.state == .finishedTurn || record.state == .failed else { return }
        let mode = mode
        guard Self.interrupts(in: mode, frontness(of: record)) else { return }
        let line = TransientLine(
            sessionID: record.id, title: Self.title(record), project: Self.project(record),
            kind: record.state == .failed ? .failed : .finished)
        interruptions.append(.line(line, sound: mode == .loud))
    }

    // MARK: Pipelines

    /// Pushes to look at: those whose repository has to be read, those whose pipeline is still
    /// to be found or still running, and those whose host could not be asked.
    public var followedPushes: [FollowedPush] {
        records.values.compactMap { record -> FollowedPush? in
            guard let ci = record.ci, Self.isLookedUp(ci.state) || ci.unreadSince != nil else { return nil }
            var lacksAccess = false
            if case .noAccess = ci.state { lacksAccess = true }
            return FollowedPush(
                sessionID: record.id, cwd: record.cwd, push: ci.unreadSince == nil ? ci.push : nil,
                request: Self.request(of: record), lacksAccess: lacksAccess)
        }
        .sorted { $0.sessionID < $1.sessionID }
    }

    /// Takes in what the repository showed at `time`, after a session's push. Only a push the
    /// hooks reported is followed, and a look from before that push says nothing about it. The
    /// same commit pushed again keeps the pipeline it has.
    public mutating func handle(_ push: Push, readAt time: Date) {
        advance(to: time)
        guard var ci = records[push.sessionID]?.ci, let pushedAt = ci.unreadSince, pushedAt <= time else { return }
        if ci.push?.commit != push.commit { ci = FollowedCI(push: push, confirmedAt: pushedAt) }
        ci.unreadSince = nil
        records[push.sessionID]?.ci = ci
    }

    /// A host that could not be asked may be asked again: the user may have signed in since.
    private static func isLookedUp(_ state: CIState) -> Bool {
        if case .noAccess = state { return true }
        return state.isFollowed
    }

    /// Takes in what the git host said about a session's push. What it says about a commit the
    /// session is no longer followed for is ignored, and so is anything after the pipeline ended.
    public mutating func reconcile(_ observation: PipelineObservation, observedAt time: Date) {
        advance(to: time)
        guard var record = records[observation.sessionID], var ci = record.ci, let push = ci.push,
              push.commit == observation.commit
        else { return }
        if let request = observation.request { ci.request = request }
        let before = ci.state
        if Self.isLookedUp(before) {
            switch observation.lookup {
            case .found(let pipeline):
                ci.confirmedAt = time
                ci.url = pipeline.url
                switch pipeline.state {
                case .running(let stage): ci.state = .running(stage: stage)
                case .passed: ci.state = .passed
                case .failed:
                    ci.state = .failed
                    ci.url = pipeline.failedJobURL ?? pipeline.url
                case .unknown: ci.state = .unknown
                }
            case .noPipeline:
                // The host answers after all: the wait for a pipeline begins now.
                if !before.isFollowed {
                    ci.state = .pending
                    ci.confirmedAt = time
                }
            case .noAccess:
                // A pipeline that was seen running is on a host that can be reached: one lookup
                // that fails is no reason to give it up.
                if before == .pending { ci.state = .noAccess(host: push.remote.host) }
            case .unknown:
                // The same goes for one answer that could not be read. A pipeline nobody
                // confirms any more turns unknown by itself.
                if before == .pending { ci.state = .unknown }
            }
            if ci.state.isFollowed {
                ci.endedAt = nil
            } else if before.isFollowed {
                ci.endedAt = time
            }
        }
        record.ci = ci
        takeUpRequest(of: &record)
        records[observation.sessionID] = record
        if ci.state != before { announcePipelineEnd(of: record) }
    }

    /// The line for a pipeline that has just passed or failed. Unlike the end of a turn it is
    /// news also to somebody looking at the session: its window does not show it.
    private mutating func announcePipelineEnd(of record: Record) {
        let kind: TransientLine.Kind
        switch record.ci?.state {
        case .passed: kind = .ciPassed
        case .failed: kind = .ciFailed
        default: return
        }
        let mode = mode
        guard mode != .quiet else { return }
        let line = TransientLine(
            sessionID: record.id, title: Self.title(record), project: Self.project(record), kind: kind)
        interruptions.append(.line(line, sound: mode == .loud))
    }

    /// The request of the pushed branch: the one found on the host, else the one the desktop
    /// app recorded for that branch.
    private static func request(of record: Record) -> RequestLink? {
        guard let ci = record.ci else { return nil }
        if let request = ci.request { return request }
        guard let branch = ci.push?.branch else { return nil }
        return record.desktopRequests.last { $0.branch == branch }
    }

    // MARK: Merge requests

    /// Starts following the request of the session's push once it is known, or carries on with
    /// it when it is followed already. Only an open one, and only on GitLab so far.
    private mutating func takeUpRequest(of record: inout Record) {
        guard var ci = record.ci, !ci.requestWasTakenUp, let push = ci.push,
              let request = Self.request(of: record)
        else { return }
        ci.requestWasTakenUp = true
        record.ci = ci
        let state = request.state?.lowercased()
        guard push.remote.provider == .gitLab, state == nil || state == "opened" || state == "open" else { return }
        let id = FollowedMergeRequest.ID(remote: push.remote, number: request.number)
        var tracked = mergeRequests[id] ?? TrackedMergeRequest(
            shown: FollowedMergeRequest(remote: push.remote, number: request.number, url: request.url))
        tracked.shown.branch = request.branch ?? tracked.shown.branch
        // What was pushed is news about it.
        tracked.askedAt = nil
        mergeRequests[id] = tracked
    }

    /// Every followed merge request, shown by a session or not: what is to be kept across a restart.
    public var followedMergeRequests: [FollowedMergeRequest] {
        mergeRequests.values.map(\.shown).sorted { ($0.remote.path, $0.number) < ($1.remote.path, $1.number) }
    }

    /// Takes back merge requests that were followed before the app quit. How they stand is not
    /// known any more and is asked at once.
    public mutating func restore(_ stored: [FollowedMergeRequest]) {
        for var request in stored where mergeRequests[request.id] == nil {
            request.ci = nil
            request.pipelineURL = nil
            mergeRequests[request.id] = TrackedMergeRequest(shown: request)
        }
    }

    /// The merge requests the host is to be asked about at `time`: one with a pipeline running
    /// every time, the others once in a while.
    public func mergeRequestsToAsk(at time: Date) -> [FollowedMergeRequest.ID] {
        mergeRequests.values.filter { tracked in
            guard let askedAt = tracked.askedAt else { return true }
            return tracked.shown.ci?.isFollowed == true || time.timeIntervalSince(askedAt) >= settings.mergeRequestInterval
        }
        .map(\.shown).sorted { ($0.remote.path, $0.number) < ($1.remote.path, $1.number) }.map(\.id)
    }

    /// Takes in what the git host said about a followed merge request. One that was merged or
    /// closed is followed no longer.
    public mutating func reconcile(_ observation: MergeRequestObservation, observedAt time: Date) {
        guard var tracked = mergeRequests[observation.id] else { return }
        tracked.askedAt = time
        switch observation.lookup {
        case .found(let status):
            guard status.state == .open else {
                mergeRequests[observation.id] = nil
                return
            }
            tracked.shown.title = status.title ?? tracked.shown.title
            tracked.shown.url = status.url
            tracked.shown.branch = status.branch ?? tracked.shown.branch
            tracked.shown.pipelineURL = nil
            switch status.pipeline {
            case .found(let pipeline):
                tracked.shown.pipelineURL = pipeline.url
                switch pipeline.state {
                case .running(let stage): tracked.shown.ci = .running(stage: stage)
                case .passed: tracked.shown.ci = .passed
                case .failed:
                    tracked.shown.ci = .failed
                    tracked.shown.pipelineURL = pipeline.failedJobURL ?? pipeline.url
                case .unknown: tracked.shown.ci = .unknown
                }
            case .noPipeline: tracked.shown.ci = nil
            case .noAccess: tracked.shown.ci = .noAccess(host: observation.id.remote.host)
            case .unknown: tracked.shown.ci = .unknown
            }
        case .noAccess:
            tracked.shown.ci = .noAccess(host: observation.id.remote.host)
            tracked.shown.pipelineURL = nil
        case .unknown:
            tracked.shown.ci = .unknown
            tracked.shown.pipelineURL = nil
        }
        mergeRequests[observation.id] = tracked
    }

    /// The user does not want to hear of this merge request any more. A session that pushes to
    /// it again brings it back.
    public mutating func stopFollowing(_ id: FollowedMergeRequest.ID) {
        mergeRequests[id] = nil
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
            release(known?.requests ?? [])
            records[observation.sessionID] = nil
            reviewRequests()
            return
        }

        var record = known ?? Record(id: observation.sessionID, since: time, lastEventAt: time)
        record.cwd = record.cwd ?? observation.cwd
        record.transcriptPath = record.transcriptPath ?? observation.transcriptPath
        record.observedTitle = observation.title ?? record.observedTitle
        // A look that found nothing says nothing about where the session runs.
        if observation.location != .unknown { record.location = observation.location }
        if let tokens = observation.contextTokens { record.context.tokens = tokens }
        if !observation.requests.isEmpty { record.desktopRequests = observation.requests }

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
            case (.inProgress, .working), (.inProgress, .waitingForPermission), (.inProgress, .waitingForAnswer):
                // A call that waits for the user is in progress as far as the transcript can tell.
                break
            case (.inProgress, nil) where known == nil, (.inProgress, .unknown) where !record.gaveUpWaiting:
                record.enter(confirmed ? .working : .unknown, at: tail.at)
            case (.inProgress, _) where tail.at > record.since:
                // A turn the hooks did not announce.
                record.enter(confirmed ? .working : .unknown, at: tail.at)
            case (.ended, .working) where closed && tail.at >= record.since,
                 (.ended, .waitingForPermission) where closed && tail.at >= record.since,
                 (.ended, .waitingForAnswer) where closed && tail.at >= record.since,
                 (.ended, .unknown) where closed:
                // A turn the hooks did not close. Whatever it was asking went with it.
                release(record.requests)
                record.requests = []
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
        // A session found at launch ended its turn before anybody was listening.
        if let before = known?.state, before == .working || before.isWaiting { announceTurnEnd(of: record) }
        prune(at: time)
        reviewRequests()
    }

    /// Sessions reconciliation should look at: every one the core tracks, shown or not.
    public var trackedSessions: [(id: String, transcriptPath: String?)] {
        records.values.map { ($0.id, $0.transcriptPath) }
    }

    // MARK: Snapshot

    public func snapshot(at time: Date) -> Snapshot {
        // Requests run out of time whether or not anybody told the core that time has passed.
        var current = self
        current.advance(to: time)
        return current.currentSnapshot(at: time)
    }

    private func currentSnapshot(at time: Date) -> Snapshot {
        var queue: [(order: Int, isRaised: Bool, request: PendingRequest)] = []
        for record in records.values {
            for request in record.requests where request.handedBackAt == nil {
                let shown = PendingRequest(
                    id: request.id, sessionID: record.id, sessionTitle: Self.title(record),
                    project: Self.project(record),
                    toolName: request.toolName, detail: RequestPresentation.detail(of: request.input),
                    summary: RequestPresentation.summary(of: request.input),
                    excerpt: RequestPresentation.excerpt(of: request.input), questions: request.questions,
                    arrivedAt: request.arrivedAt, location: record.location)
                queue.append((request.order, request.isRaised, shown))
            }
        }
        queue.sort { $0.order < $1.order }
        let live = records.values
            .compactMap { record -> Session? in
                guard let state = record.state, isLive(record, in: state, at: time) else { return nil }
                return Session(
                    id: record.id, state: state, since: record.since, cwd: record.cwd,
                    title: Self.title(record), activity: record.activity,
                    subagents: record.subagents, location: record.location,
                    context: record.context == ContextUsage() ? nil : record.context,
                    ci: record.ci.map { SessionCI(state: $0.state, url: $0.url, request: Self.request(of: record)) })
            }
            .sorted { ($0.state.rank, $0.since, $0.id) < ($1.state.rank, $1.since, $1.id) }
        // A merge request is in a session's row while that session is in the list.
        let inRows = Set(records.values.compactMap { record -> FollowedMergeRequest.ID? in
            guard let state = record.state, isLive(record, in: state, at: time),
                  let remote = record.ci?.push?.remote, let request = Self.request(of: record)
            else { return nil }
            return FollowedMergeRequest.ID(remote: remote, number: request.number)
        })
        return Snapshot(
            sessions: live,
            counters: Counters(
                waiting: live.filter { $0.state.isWaiting }.count,
                working: live.filter { $0.state == .working }.count,
                finished: live.filter { $0.state == .finishedTurn }.count,
                failed: live.filter { $0.state == .failed }.count
            ),
            requests: queue.map(\.request),
            raised: queue.filter(\.isRaised).map(\.request),
            mergeRequests: followedMergeRequests.filter { !inRows.contains($0.id) }
        )
    }

    /// A session whose pipeline is still followed is live however long ago its turn ended; once
    /// the pipeline ended, the threshold counts from that moment.
    private func isLive(_ record: Record, in state: SessionState, at time: Date) -> Bool {
        if record.ci?.state.isFollowed == true { return true }
        switch state {
        case .working, .waitingForPermission, .waitingForAnswer:
            return true
        case .finishedTurn, .failed, .unknown:
            let since = max(record.since, record.ci?.endedAt ?? record.since)
            return time.timeIntervalSince(since) < settings.livenessThreshold
        }
    }

    /// Forgets sessions that stopped being live, and sessions that never had a turn and went quiet.
    private mutating func prune(at time: Date) {
        records = records.filter { _, record in
            if let state = record.state { return isLive(record, in: state, at: time) }
            return time.timeIntervalSince(record.lastEventAt) < settings.livenessThreshold
        }
        endedAt = endedAt.filter { time.timeIntervalSince($0.value) < settings.livenessThreshold }
    }

    private static let compacting = "Compacting"

    private static func title(_ record: Record) -> String? { record.observedTitle ?? record.firstPrompt }

    private static func project(_ record: Record) -> String? {
        record.cwd.map { ($0 as NSString).lastPathComponent }
    }

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
