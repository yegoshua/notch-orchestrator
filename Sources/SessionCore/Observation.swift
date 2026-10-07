import Foundation

/// What the end of a session's transcript says about its current turn.
public struct TranscriptTail: Equatable, Sendable {
    public enum Turn: Equatable, Sendable {
        case inProgress
        /// The turn closed. Background agents that had not reported back yet may still reopen it;
        /// nil when the transcript does not say how many there were.
        case ended(pendingBackgroundAgents: Int?)
    }

    public var turn: Turn
    /// The time of the transcript entry that says so.
    public var at: Date

    public init(turn: Turn, at: Date) {
        self.turn = turn
        self.at = at
    }
}

/// What reconciliation found out about one session by looking at the system instead of listening
/// to hooks.
public struct Observation: Equatable, Sendable {
    public enum Process: Equatable, Sendable {
        case alive
        case dead
        /// No process could be tied to the session.
        case unknown
    }

    public var sessionID: String
    public var process: Process
    /// Nil when the transcript is missing, unreadable or says nothing about the turn.
    public var transcript: TranscriptTail?
    public var cwd: String?
    public var title: String?
    public var transcriptPath: String?
    /// Where the session runs; `unknown` when this look could not tell.
    public var location: SessionLocation
    /// How many tokens the transcript shows in the session's context; nil when it does not say.
    public var contextTokens: Int?

    public init(
        sessionID: String, process: Process, transcript: TranscriptTail? = nil,
        cwd: String? = nil, title: String? = nil, transcriptPath: String? = nil,
        location: SessionLocation = .unknown, contextTokens: Int? = nil
    ) {
        self.sessionID = sessionID
        self.process = process
        self.transcript = transcript
        self.cwd = cwd
        self.title = title
        self.transcriptPath = transcriptPath
        self.location = location
        self.contextTokens = contextTokens
    }
}
