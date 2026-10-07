import Foundation
import Testing
import SessionCore

@Suite struct SessionListFromRecordedCLISessions {
    @Test func aSessionCarriesItsProjectTitleStateActivityAndStartOfTurn() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core) { $0.event.name == "PreToolUse" }
        let prompted = fixture.steps.first { $0.event.name == "UserPromptSubmit" }!.at

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.project == "sandbox")
        #expect(session.title == "Run ./slow.sh 60 with the Bash tool. Do nothing else.")
        #expect(session.state == .working)
        #expect(session.activity == "Bash: ./slow.sh 60")
        #expect(session.since == prompted)
    }

    @Test func activityClearsWhenTheToolCallReturns() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-permission-native-yes").play(into: &core) { $0.event.name == "PostToolUse" }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.state == .working)
        #expect(session.activity == nil)
    }

    @Test func activityClearsWhenTheToolCallWasDenied() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-permission-deny").play(into: &core) { $0.event.name == "PostToolBatch" }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.state == .working)
        #expect(session.activity == nil)
    }

    @Test func runningSubagentsAreListedUnderTheirSessionWithWhatEachDoes() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-subagents").play(into: &core) { $0.event.name == "Stop" }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.state == .working)
        #expect(session.subagents.map(\.id) == ["a3e5a8f6dae3fd3d7", "a92591c7cb56fdca0"])
        #expect(session.subagents.map(\.type) == ["general-purpose", "general-purpose"])
        #expect(session.subagents.map(\.task) == ["Count lines in colors.txt", "Read first line of notes.txt"])
        // Only the first one has made a tool call so far, and that call has returned.
        #expect(session.subagents.map(\.activity) == [nil, nil])
    }

    @Test func aSubagentShowsTheToolItIsRunning() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-subagents").play(into: &core) {
            $0.event.name == "PreToolUse" && $0.event.agentID == "a92591c7cb56fdca0"
        }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.subagents.last?.activity == "Read: notes.txt")
        // A subagent's tool call is not the session's own activity.
        #expect(session.activity == nil)
    }

    @Test func aSubagentLeavesTheListWhenItStops() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-subagents").play(into: &core) {
            $0.event.name == "SubagentStop" && $0.event.agentID == "a3e5a8f6dae3fd3d7"
        }

        #expect(core.snapshot(at: at).sessions.first?.subagents.map(\.id) == ["a92591c7cb56fdca0"])
    }

    @Test func theInternalHelperAgentIsNeverListedAsASubagent() throws {
        let fixture = try Fixture("cli/cli-subagents")
        var core = SessionCore()
        var seen: Set<String> = []
        for step in fixture.steps {
            core.handle(step.event, at: step.at)
            seen.formUnion(core.snapshot(at: step.at).sessions.flatMap(\.subagents).map(\.id))
        }

        #expect(seen == ["a3e5a8f6dae3fd3d7", "a92591c7cb56fdca0"])
    }

    @Test func aSubagentResultComingBackDoesNotRestartTheTurnClock() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-subagents")
        let firstPrompt = fixture.steps.first { $0.event.name == "UserPromptSubmit" }!.at
        let at = fixture.play(into: &core) { $0.event.prompt?.hasPrefix("<task-notification>") == true }

        let session = try #require(core.snapshot(at: at).sessions.first)
        #expect(session.since == firstPrompt)
        #expect(session.title?.hasPrefix("Launch two general-purpose subagents") == true)
    }

    @Test func aNewPromptRestartsTheTurnClock() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-compaction")
        let lastPrompt = fixture.steps.last { $0.event.name == "UserPromptSubmit" }!.at
        fixture.play(into: &core) { $0.at == lastPrompt }

        #expect(core.snapshot(at: lastPrompt).sessions.first?.since == lastPrompt)
    }

    @Test func compactingShowsAsActivityOnlyWhileItRuns() throws {
        let fixture = try Fixture("cli/cli-compaction")
        var core = SessionCore()
        let during = fixture.play(into: &core) { $0.event.name == "PreCompact" }
        #expect(core.snapshot(at: during).sessions.first?.activity == "Compacting")

        var core2 = SessionCore()
        let after = fixture.play(into: &core2) { $0.event.name == "PostCompact" }
        #expect(core2.snapshot(at: after).sessions.first?.activity == nil)
    }

    @Test func aFailedTurnIsFailedAndNeedsTheUser() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: t)
        core.handle(HookEvent(name: "StopFailure", sessionID: "s"), at: t + 1)

        let snapshot = core.snapshot(at: t + 1)
        #expect(snapshot.sessions.first?.state == .failed)
        #expect(snapshot.sessions.first?.needsUser == true)
        #expect(snapshot.counters == Counters(working: 0, finished: 0, failed: 1))
        #expect(core.snapshot(at: t + 601).sessions.isEmpty)
    }

    @Test func sessionsThatNeedTheUserComeFirstThenWorkingThenFinished() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        core.handle(HookEvent(name: "Stop", sessionID: "b"), at: t)
        for id in ["a", "c", "d"] {
            core.handle(HookEvent(name: "UserPromptSubmit", sessionID: id), at: t + 1)
        }
        core.handle(HookEvent(name: "StopFailure", sessionID: "d"), at: t + 2)

        let sessions = core.snapshot(at: t + 3).sessions
        #expect(sessions.map(\.id) == ["d", "a", "c", "b"])
        #expect(sessions.map(\.needsUser) == [true, false, false, false])
    }

    @Test func aToolCallRevealsAWorkingSessionWhoseStartWasMissed() throws {
        // The app started in the middle of a turn: the prompt was never seen.
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-yes")
        let call = fixture.steps.first { $0.event.name == "PreToolUse" }!
        core.handle(call.event, at: call.at)

        let session = try #require(core.snapshot(at: call.at).sessions.first)
        #expect(session.state == .working)
        #expect(session.activity == "Bash: ./slow.sh 20")
        #expect(session.project == "sandbox")
        #expect(session.title == nil)
    }
}

@Suite struct ContextOfASession {
    private static let t = Date(timeIntervalSince1970: 1_000)

    private func working() -> SessionCore {
        var core = SessionCore()
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s", cwd: "/work/project"), at: Self.t)
        return core
    }

    @Test func nothingIsKnownAboutItAtFirst() {
        #expect(working().snapshot(at: Self.t).sessions.first?.context == nil)
    }

    @Test func theTranscriptGivesItsTokens() {
        var core = working()
        core.reconcile(Observation(sessionID: "s", process: .alive, contextTokens: 266_236), observedAt: Self.t)
        // A look that could not read the transcript takes nothing away.
        core.reconcile(Observation(sessionID: "s", process: .alive), observedAt: Self.t + 5)

        #expect(core.snapshot(at: Self.t + 5).sessions.first?.context == ContextUsage(tokens: 266_236))
    }

    @Test func theStatusLineGivesItsShareOfTheWindow() throws {
        var core = working()
        let payload = #"{"session_id": "s", "context_window": {"context_window_size": 200000, "used_percentage": 27.4}}"#
        core.handle(try #require(ContextReport(statusLinePayload: Data(payload.utf8))))
        core.reconcile(Observation(sessionID: "s", process: .alive, contextTokens: 54_800), observedAt: Self.t)

        #expect(core.snapshot(at: Self.t).sessions.first?.context == ContextUsage(tokens: 54_800, usedPercentage: 27.4))
    }

    @Test(arguments: [
        #"{"session_id": "s"}"#, #"{"session_id": "s", "context_window": {"used_percentage": null}}"#,
        #"{"context_window": {"used_percentage": 12}}"#, "not json",
    ])
    func aPayloadThatDoesNotSayIsNoReport(payload: String) {
        #expect(ContextReport(statusLinePayload: Data(payload.utf8)) == nil)
    }

    @Test func aReportAboutASessionNobodyTracksMakesNoSession() {
        var core = SessionCore()
        core.handle(ContextReport(sessionID: "ghost", usedPercentage: 50))

        #expect(core.snapshot(at: Self.t).sessions.isEmpty)
    }

    @Test func aCompactionForgetsWhatWasKnown() {
        var core = working()
        core.reconcile(Observation(sessionID: "s", process: .alive, contextTokens: 180_000), observedAt: Self.t)
        core.handle(ContextReport(sessionID: "s", usedPercentage: 90))

        core.handle(HookEvent(name: "PostCompact", sessionID: "s"), at: Self.t + 60)

        #expect(core.snapshot(at: Self.t + 60).sessions.first?.context == nil)
    }
}
