import Foundation
import Testing
import SessionCore

/// Entries shaped like those Claude Code 2.1.236 wrote for the recorded sessions, cut down to the
/// fields the reader looks at.
private enum Entry {
    static let prompt = #"{"type":"user","timestamp":"2026-10-07T13:11:40.309Z","promptSource":"typed","permissionMode":"default","message":{"role":"user","content":"Run ./slow.sh 60 with the Bash tool."}}"#
    static let attachment = #"{"type":"attachment","timestamp":"2026-10-07T13:11:40.338Z","attachment":{}}"#
    static let lastPrompt = #"{"type":"last-prompt","lastPrompt":"Run ./slow.sh 60","leafUuid":"x"}"#
    static let title = #"{"type":"ai-title","aiTitle":"Run the slow script","sessionId":"0ae7294c"}"#
    static let toolUse = #"{"type":"assistant","timestamp":"2026-10-07T13:12:08.963Z","message":{"role":"assistant","stop_reason":"tool_use","content":[{"type":"tool_use","name":"Bash"}]}}"#
    static let toolResult = #"{"type":"user","timestamp":"2026-10-07T13:12:20.000Z","message":{"role":"user","content":[{"type":"tool_result","content":"ok"}]}}"#
    static let endTurn = #"{"type":"assistant","timestamp":"2026-10-07T13:13:47.167Z","message":{"role":"assistant","stop_reason":"end_turn","content":[{"type":"text","text":"Blue."}]}}"#
    static let stopHooks = #"{"type":"system","subtype":"stop_hook_summary","timestamp":"2026-10-07T13:13:47.196Z"}"#
    static let turnDuration = #"{"type":"system","subtype":"turn_duration","timestamp":"2026-10-07T13:13:47.197Z","durationMs":13000}"#
    static let turnDurationPending = #"{"type":"system","subtype":"turn_duration","timestamp":"2026-10-07T13:11:06.452Z","durationMs":7000,"pendingBackgroundAgentCount":2}"#
    static let snapshot = #"{"type":"file-history-snapshot","messageId":"m","snapshot":{}}"#
    static let slashCommand = #"{"type":"user","timestamp":"2026-10-07T13:14:05.685Z","message":{"role":"user","content":"/compact"}}"#
    static let compactBoundary = #"{"type":"system","subtype":"compact_boundary","timestamp":"2026-10-07T13:14:30.690Z"}"#
    static let compactSummary = #"{"type":"user","timestamp":"2026-10-07T13:14:30.521Z","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued"}}"#
    static let commandOutput = #"{"type":"user","timestamp":"2026-10-07T13:14:30.790Z","message":{"role":"user","content":"<local-command-stdout>Compacted</local-command-stdout>"}}"#
    static let sidechain = #"{"type":"assistant","isSidechain":true,"timestamp":"2026-10-07T13:20:00.000Z","message":{"role":"assistant","stop_reason":"tool_use","content":[]}}"#
    static let interrupted = #"{"type":"user","timestamp":"2026-10-07T12:59:37.008Z","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#

    static func time(_ text: String) -> Date {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: text)!
    }
}

private func tail(_ entries: String...) -> TranscriptTail? {
    TranscriptReader.tail(of: entries.joined(separator: "\n") + "\n")
}

private let ended = TranscriptTail.Turn.ended(pendingBackgroundAgents: 0)

@Suite struct TranscriptTails {
    @Test func aPromptWithNoAnswerYetIsATurnInProgress() {
        #expect(tail(Entry.snapshot, Entry.prompt, Entry.attachment, Entry.lastPrompt, Entry.title)
            == TranscriptTail(turn: .inProgress, at: Entry.time("2026-10-07T13:11:40.309Z")))
    }

    @Test func aToolCallOrItsResultIsATurnInProgress() {
        #expect(tail(Entry.prompt, Entry.toolUse, Entry.snapshot)?.turn == .inProgress)
        #expect(tail(Entry.prompt, Entry.toolUse, Entry.toolResult)
            == TranscriptTail(turn: .inProgress, at: Entry.time("2026-10-07T13:12:20.000Z")))
    }

    @Test func aRecordedTurnDurationEndsTheTurn() {
        #expect(tail(Entry.prompt, Entry.endTurn, Entry.stopHooks, Entry.turnDuration, Entry.lastPrompt, Entry.snapshot)
            == TranscriptTail(turn: ended, at: Entry.time("2026-10-07T13:13:47.197Z")))
    }

    /// Sessions in the desktop app (2.1.289) write no turn duration at all.
    @Test func aFinalAnswerEndsTheTurnWithoutSayingWhatStillRunsInTheBackground() {
        #expect(tail(Entry.prompt, Entry.endTurn, Entry.stopHooks)
            == TranscriptTail(
                turn: .ended(pendingBackgroundAgents: nil), at: Entry.time("2026-10-07T13:13:47.167Z")))
    }

    @Test func aTurnThatEndedWithBackgroundAgentsSaysHowMany() {
        #expect(tail(Entry.prompt, Entry.endTurn, Entry.turnDurationPending)?.turn
            == .ended(pendingBackgroundAgents: 2))
    }

    @Test func anInterruptedTurnHasEnded() {
        #expect(tail(Entry.prompt, Entry.toolUse, Entry.interrupted)?.turn == .ended(pendingBackgroundAgents: nil))
    }

    @Test func slashCommandsAndTheirOutputAreNotTurns() {
        #expect(tail(Entry.prompt, Entry.endTurn, Entry.turnDuration, Entry.slashCommand, Entry.commandOutput)?.turn
            == ended)
    }

    @Test func nothingIsConcludedAcrossACompactionBoundary() {
        #expect(tail(
            Entry.prompt, Entry.endTurn, Entry.turnDuration, Entry.slashCommand,
            Entry.compactBoundary, Entry.compactSummary, Entry.commandOutput, Entry.attachment) == nil)
    }

    @Test func aTurnAfterCompactionIsReadNormally() {
        #expect(tail(Entry.compactBoundary, Entry.compactSummary, Entry.prompt)?.turn == .inProgress)
    }

    @Test func subagentEntriesDoNotSpeakForTheSession() {
        #expect(tail(Entry.prompt, Entry.endTurn, Entry.turnDuration, Entry.sidechain)?.turn == ended)
    }

    @Test func aCutOffFirstLineAndGarbageAreSkipped() {
        let text = #"e":"assistant","message":{"stop_reason":"tool_use"}}"# + "\n" + Entry.prompt + "\nnot json\n"
        #expect(TranscriptReader.tail(of: text)?.turn == .inProgress)
    }

    @Test func anEmptyTranscriptSaysNothing() {
        #expect(TranscriptReader.tail(of: "") == nil)
        #expect(tail(Entry.snapshot, Entry.lastPrompt) == nil)
    }

    @Test func theTitleIsTheLatestOneWritten() {
        let text = [Entry.title, Entry.prompt, #"{"type":"ai-title","aiTitle":"Slow script, second try"}"#, Entry.endTurn]
            .joined(separator: "\n")
        #expect(TranscriptReader.title(in: text) == "Slow script, second try")
        #expect(TranscriptReader.title(in: Entry.prompt) == nil)
    }
}

@Suite struct ContextInATranscript {
    private static let response = #"{"type":"assistant","timestamp":"2026-10-07T13:12:08.963Z","message":{"role":"assistant","stop_reason":"tool_use","usage":{"input_tokens":2,"cache_creation_input_tokens":282,"cache_read_input_tokens":265952,"output_tokens":437}}}"#
    private static let earlier = #"{"type":"assistant","timestamp":"2026-10-07T13:11:08.963Z","message":{"role":"assistant","usage":{"input_tokens":10,"cache_read_input_tokens":90,"output_tokens":5000}}}"#
    private static let subagent = #"{"type":"assistant","isSidechain":true,"timestamp":"2026-10-07T13:13:00.000Z","message":{"role":"assistant","usage":{"input_tokens":7,"output_tokens":1}}}"#
    private static let synthetic = #"{"type":"assistant","timestamp":"2026-10-07T13:13:30.000Z","message":{"role":"assistant","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0}}}"#
    private static let compacted = #"{"type":"system","subtype":"compact_boundary","timestamp":"2026-10-07T13:14:30.690Z","compactMetadata":{"trigger":"manual","preTokens":55094,"postTokens":6811}}"#
    private static let compactedSilently = #"{"type":"system","subtype":"compact_boundary","timestamp":"2026-10-07T13:14:30.690Z"}"#

    @Test func theContextIsWhatTheLastResponseWasSent() {
        let text = [Self.earlier, Self.response, Self.subagent, Self.synthetic].joined(separator: "\n")

        #expect(TranscriptReader.contextTokens(in: text) == 266_236)
    }

    @Test func afterACompactionItIsWhatTheCompactionLeft() {
        #expect(TranscriptReader.contextTokens(in: [Self.response, Self.compacted].joined(separator: "\n")) == 6811)
        #expect(TranscriptReader.contextTokens(in: [Self.response, Self.compactedSilently].joined(separator: "\n")) == nil)
        #expect(TranscriptReader.contextTokens(in: [Self.compacted, Self.earlier].joined(separator: "\n")) == 100)
    }

    @Test func aTranscriptWithoutAResponseSaysNothing() {
        #expect(TranscriptReader.contextTokens(in: "") == nil)
        #expect(TranscriptReader.contextTokens(in: [Self.subagent, Self.synthetic, #"{"usage" not json"#].joined(separator: "\n")) == nil)
    }
}
