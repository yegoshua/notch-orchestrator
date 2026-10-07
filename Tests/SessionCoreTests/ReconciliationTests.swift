import Foundation
import Testing
import SessionCore

private func observation(
    _ id: String, _ process: Observation.Process, _ turn: TranscriptTail.Turn? = nil, at: Date = .distantPast,
    cwd: String? = nil, title: String? = nil
) -> Observation {
    Observation(
        sessionID: id, process: process, transcript: turn.map { TranscriptTail(turn: $0, at: at) },
        cwd: cwd, title: title)
}

private let turnEnded = TranscriptTail.Turn.ended(pendingBackgroundAgents: 0)

/// Final events that never arrive, taken from recorded sessions, and what reconciliation makes of them.
@Suite struct LostEvents {
    @Test func aKilledSessionStaysWorkingForHooksAlone() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-killed").play(into: &core)

        // The recording simply stops: there is no Stop and no SessionEnd.
        #expect(core.snapshot(at: at + 3600).counters == Counters(working: 1))
    }

    @Test func aSessionWhoseProcessDiedIsGone() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core)
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .dead, .inProgress, at: at), observedAt: at + 5)

        #expect(core.snapshot(at: at + 5).sessions.isEmpty)
    }

    @Test func resumingAKilledSessionEndsItsInterruptedTurn() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-resumed-after-kill").play(into: &core) { $0.source == "resume" }

        #expect(core.snapshot(at: at).sessions.isEmpty)
    }

    @Test func aTurnInterruptedWithoutAStopIsFinishedOnceTheTranscriptSaysSo() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let id = fixture.steps[0].event.sessionID
        #expect(core.snapshot(at: asked).counters == Counters(working: 1))

        // The human pressed No and Esc: the transcript closes the turn, no hook says so.
        core.reconcile(observation(id, .alive, turnEnded, at: asked + 2), observedAt: asked + 5)

        let session = try #require(core.snapshot(at: asked + 5).sessions.first)
        #expect(session.state == .finishedTurn)
        #expect(session.since == asked + 2)
        #expect(session.activity == nil)
    }

    @Test func theNextPromptAfterALostStopStartsANewTurn() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        let prompts = fixture.steps.filter { $0.event.name == "UserPromptSubmit" }
        fixture.play(into: &core) { $0.at == prompts[1].at }

        let session = try #require(core.snapshot(at: prompts[1].at).sessions.first)
        #expect(session.state == .working)
        #expect(session.since == prompts[1].at)
        #expect(session.activity == nil)
    }

    @Test func aLostStopDoesNotLeaveTheSessionWorking() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-yes")
        // Everything up to the Stop, which is taken to be lost.
        let at = fixture.play(into: &core) { $0.event.name == "PostToolBatch" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .alive, turnEnded, at: at + 1), observedAt: at + 5)

        #expect(core.snapshot(at: at + 5).counters == Counters(finished: 1))
    }

    @Test func resumeAndCompactionNeverNeedTheUser() throws {
        for name in ["cli/cli-resumed", "cli/cli-resumed-after-kill", "cli/cli-compaction", "cli/cli-clear"] {
            var core = SessionCore()
            for step in try Fixture(name).steps {
                core.handle(step.event, at: step.at)
                let snapshot = core.snapshot(at: step.at)
                #expect(!snapshot.sessions.contains { $0.needsUser }, "\(name) at \(step.event.name)")
                #expect(snapshot.counters.failed == 0)
            }
        }
    }

    @Test func compactionAfterAFinishedTurnLeavesItFinishedWithNoStop() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-compaction").play(into: &core) { $0.event.name == "PostCompact" }

        #expect(core.snapshot(at: at).sessions.map(\.state) == [.finishedTurn])
    }
}

@Suite struct AppRestartMidSession {
    let now = Date(timeIntervalSince1970: 100_000)

    @Test func liveSessionsAreRebuiltFromObservationsAlone() {
        var core = SessionCore()
        core.reconcile(
            observation("busy", .alive, .inProgress, at: now - 40, cwd: "/work/api", title: "Fix the login bug"),
            observedAt: now)
        core.reconcile(observation("done", .alive, turnEnded, at: now - 90, cwd: "/work/web"), observedAt: now)

        let sessions = core.snapshot(at: now).sessions
        #expect(sessions.map(\.id) == ["busy", "done"])
        #expect(sessions.map(\.state) == [.working, .finishedTurn])
        #expect(sessions.map(\.since) == [now - 40, now - 90])
        #expect(sessions.map(\.project) == ["api", "web"])
        #expect(sessions.map(\.title) == ["Fix the login bug", nil])
    }

    @Test func sessionsIdleForDaysAreNotRebuilt() {
        var core = SessionCore()
        core.reconcile(observation("old", .alive, turnEnded, at: now - 2 * 86_400), observedAt: now)

        #expect(core.snapshot(at: now).sessions.isEmpty)
        #expect(core.trackedSessions.isEmpty)
    }

    @Test func aSessionWithNoReadableTranscriptOrNoProcessIsNotRebuilt() {
        var core = SessionCore()
        core.reconcile(observation("blank", .alive), observedAt: now)
        core.reconcile(observation("dead", .dead, .inProgress, at: now - 5), observedAt: now)

        #expect(core.snapshot(at: now).sessions.isEmpty)
    }

    @Test func aRebuiltSessionCarriesOnWithTheHooksThatFollow() throws {
        let fixture = try Fixture("cli/cli-permission-native-yes")
        let id = fixture.steps[0].event.sessionID
        let call = fixture.steps.first { $0.event.name == "PreToolUse" }!
        var core = SessionCore()
        core.reconcile(observation(id, .alive, .inProgress, at: call.at), observedAt: call.at + 1)
        #expect(core.snapshot(at: call.at + 1).counters == Counters(working: 1))

        var last = call.at
        for step in fixture.steps where step.at > call.at + 1 && step.event.name != "SessionEnd" {
            core.handle(step.event, at: step.at)
            last = step.at
        }
        #expect(core.snapshot(at: last).counters == Counters(finished: 1))
    }
}

@Suite struct HooksDisagreeingWithReconciliation {
    @Test func aMissedPromptIsRecoveredFromTheTranscript() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-normal-turn")
        let stopped = fixture.play(into: &core) { $0.event.name == "Stop" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .alive, .inProgress, at: stopped + 30), observedAt: stopped + 31)

        let session = try #require(core.snapshot(at: stopped + 31).sessions.first)
        #expect(session.state == .working)
        #expect(session.since == stopped + 30)
    }

    @Test func aTranscriptThatIsBehindTheHooksDoesNotOverrideThem() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        let prompts = fixture.steps.filter { $0.event.name == "UserPromptSubmit" }
        fixture.play(into: &core) { $0.at == prompts[1].at }
        let id = fixture.steps[0].event.sessionID

        // The end of the previous turn, read before the new prompt reached the transcript.
        core.reconcile(observation(id, .alive, turnEnded, at: prompts[1].at - 9), observedAt: prompts[1].at + 1)

        #expect(core.snapshot(at: prompts[1].at + 1).counters == Counters(working: 1))
    }

    @Test func anObservationTakenBeforeTheLatestHookIsIgnored() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-resumed-after-kill")
        let resumed = fixture.steps.first { $0.source == "resume" }!.at
        let at = fixture.play(into: &core) { $0.at > resumed && $0.event.name == "UserPromptSubmit" }
        let id = fixture.steps[0].event.sessionID

        // The dead process was seen before the session was resumed; the result arrives late.
        core.reconcile(observation(id, .dead), observedAt: resumed - 1)

        #expect(core.snapshot(at: at).counters == Counters(working: 1))
    }

    @Test func activityThatCannotBeConfirmedIsUnknownAndNeverNeedsTheUser() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-normal-turn")
        let stopped = fixture.play(into: &core) { $0.event.name == "Stop" }
        let id = fixture.steps[0].event.sessionID
        core.handle(HookEvent(name: "StopFailure", sessionID: "failed"), at: stopped)

        // The transcript moved on, but no process is known to be behind it.
        core.reconcile(observation(id, .unknown, .inProgress, at: stopped + 30), observedAt: stopped + 31)

        let snapshot = core.snapshot(at: stopped + 31)
        let session = try #require(snapshot.sessions.first { $0.id == id })
        #expect(session.state == .unknown)
        #expect(!session.needsUser)
        #expect(snapshot.counters == Counters(failed: 1))
        #expect(snapshot.sessions.map(\.id) == ["failed", id])
        #expect(core.snapshot(at: stopped + 30 + 600).sessions.allSatisfy { $0.id != id })
    }

    @Test func hooksAreTrustedWhileNothingContradictsThem() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core)
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .unknown, .inProgress, at: at), observedAt: at + 5)
        core.reconcile(observation(id, .alive), observedAt: at + 6)

        #expect(core.snapshot(at: at + 6).sessions.map(\.state) == [.working])
    }

    @Test func aTurnThatEndedWithSubagentsStillRunningKeepsWorking() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-subagents")
        let stopped = fixture.play(into: &core) { $0.event.name == "Stop" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(
            observation(id, .alive, .ended(pendingBackgroundAgents: 2), at: stopped), observedAt: stopped + 1)

        let session = try #require(core.snapshot(at: stopped + 1).sessions.first)
        #expect(session.state == .working)
        #expect(session.subagents.count == 2)
    }

    @Test func subagentsThatNeverReportedBackDoNotKeepAFinishedSessionWorking() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-subagents")
        let stopped = fixture.play(into: &core) { $0.event.name == "Stop" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .alive, turnEnded, at: stopped + 20), observedAt: stopped + 21)

        let session = try #require(core.snapshot(at: stopped + 21).sessions.first)
        #expect(session.state == .finishedTurn)
        #expect(session.subagents.isEmpty)
    }

    @Test func aTranscriptThatCannotTellWhatRunsInTheBackgroundDoesNotEndATurnWithRunningSubagents() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-subagents")
        let stopped = fixture.play(into: &core) { $0.event.name == "Stop" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(
            observation(id, .alive, .ended(pendingBackgroundAgents: nil), at: stopped), observedAt: stopped + 1)

        let session = try #require(core.snapshot(at: stopped + 1).sessions.first)
        #expect(session.state == .working)
        #expect(session.subagents.count == 2)
    }

    @Test func thatSameTranscriptEndsATurnThatHasNoSubagentsLeft() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let id = fixture.steps[0].event.sessionID

        core.reconcile(
            observation(id, .alive, .ended(pendingBackgroundAgents: nil), at: asked + 2), observedAt: asked + 5)

        #expect(core.snapshot(at: asked + 5).sessions.map(\.state) == [.finishedTurn])
    }

    @Test func aRebuiltSessionWithUnfinishedBackgroundWorkIsUnknown() {
        var core = SessionCore()
        let now = Date(timeIntervalSince1970: 100_000)
        core.reconcile(
            observation("s", .alive, .ended(pendingBackgroundAgents: 1), at: now - 60), observedAt: now)

        #expect(core.snapshot(at: now).sessions.map(\.state) == [.unknown])
        #expect(core.snapshot(at: now).counters == Counters())
    }

    @Test func theSessionTitleComesFromReconciliationWhenThereIsOne() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core)
        let id = fixture.steps[0].event.sessionID

        core.reconcile(observation(id, .alive, title: "Run the slow script"), observedAt: at + 1)

        #expect(core.snapshot(at: at + 1).sessions.first?.title == "Run the slow script")
    }
}

/// Observations and events that arrive in an awkward order.
@Suite struct AwkwardTiming {
    private let start = Date(timeIntervalSince1970: 1_791_380_000)

    @Test func aResumedKilledSessionIsNotRevivedByItsOldTranscript() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-resumed-after-kill")
        let resumed = fixture.play(into: &core) { $0.source == "resume" }
        let id = fixture.steps[0].event.sessionID
        let interrupted = try #require(fixture.steps.last { $0.event.name == "PreToolUse" && $0.at < resumed })

        // The transcript still ends with the tool call the killed process never finished.
        core.reconcile(observation(id, .alive, .inProgress, at: interrupted.at), observedAt: resumed + 5)

        #expect(core.snapshot(at: resumed + 5).sessions.isEmpty)
    }

    @Test func anObservationMadeBeforeTheSessionEndedDoesNotBringItBack() {
        var core = SessionCore()
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: start)
        core.handle(HookEvent(name: "Stop", sessionID: "s"), at: start + 8)
        core.handle(HookEvent(name: "SessionEnd", sessionID: "s"), at: start + 10)

        core.reconcile(observation("s", .alive, turnEnded, at: start + 8), observedAt: start + 9)

        #expect(core.snapshot(at: start + 11).sessions.isEmpty)
    }

    @Test func aSessionResumedAfterItEndedIsObservedAgain() {
        var core = SessionCore()
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: start)
        core.handle(HookEvent(name: "SessionEnd", sessionID: "s"), at: start + 10)

        core.reconcile(observation("s", .alive, .inProgress, at: start + 30), observedAt: start + 31)

        #expect(core.snapshot(at: start + 31).counters == Counters(working: 1))
    }

    @Test func aDeniedAgentCallDoesNotLendItsTaskToTheNextSubagent() throws {
        var core = SessionCore()
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: start)
        core.handle(
            HookEvent(name: "PreToolUse", sessionID: "s", tool: .init(name: "Agent", subject: "Denied task")),
            at: start + 1)
        core.handle(HookEvent(name: "PostToolBatch", sessionID: "s"), at: start + 2)
        core.handle(
            HookEvent(name: "PreToolUse", sessionID: "s", tool: .init(name: "Agent", subject: "Real task")),
            at: start + 3)
        core.handle(
            HookEvent(name: "SubagentStart", sessionID: "s", agentID: "a1", agentType: "general-purpose"),
            at: start + 4)

        let session = try #require(core.snapshot(at: start + 4).sessions.first)
        #expect(session.subagents.map(\.task) == ["Real task"])
    }

    @Test func aBackgroundSubagentWithoutAnIdentifierKeepsTheTurnOpenButIsNotListed() throws {
        var core = SessionCore()
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: start)
        core.handle(
            HookEvent(name: "Stop", sessionID: "s", backgroundTasks: [
                .init(type: "subagent", status: "running"), .init(type: "subagent", status: "running"),
            ]),
            at: start + 5)

        let session = try #require(core.snapshot(at: start + 5).sessions.first)
        #expect(session.state == .working)
        #expect(session.subagents.isEmpty)
    }
}
