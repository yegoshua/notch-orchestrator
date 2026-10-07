import Foundation
import Testing
import SessionCore

@Suite struct CountersFromRecordedCLISessions {
    @Test func aSessionIsWorkingOnceAPromptIsSubmitted() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "UserPromptSubmit" }

        #expect(core.snapshot(at: at).counters == Counters(working: 1, finished: 0))
    }

    @Test func aSessionIsFinishedWhenItsTurnStops() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "Stop" }

        #expect(core.snapshot(at: at).counters == Counters(working: 0, finished: 1))
    }

    @Test func aStartedSessionWithNoTurnShowsNothing() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "SessionStart" }

        #expect(core.snapshot(at: at).counters == Counters())
    }

    @Test func anEndedSessionShowsNothing() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-normal-turn").play(into: &core)

        #expect(core.snapshot(at: at).counters == Counters())
    }

    @Test func aFinishedSessionLeavesTheCountersAfterTheLivenessThreshold() throws {
        var core = SessionCore()
        let stopped = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "Stop" }

        #expect(core.snapshot(at: stopped.addingTimeInterval(599)).counters.finished == 1)
        #expect(core.snapshot(at: stopped.addingTimeInterval(600)).counters.finished == 0)
    }

    @Test func theLivenessThresholdIsConfigurable() throws {
        var core = SessionCore(settings: Settings(livenessThreshold: 60))
        let stopped = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "Stop" }

        #expect(core.snapshot(at: stopped.addingTimeInterval(59)).counters.finished == 1)
        #expect(core.snapshot(at: stopped.addingTimeInterval(60)).counters.finished == 0)

        core.settings.livenessThreshold = 3600
        #expect(core.snapshot(at: stopped.addingTimeInterval(60)).counters.finished == 1)
    }

    @Test func aWorkingSessionNeverExpires() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-normal-turn").play(into: &core) { $0.event.name == "UserPromptSubmit" }

        #expect(core.snapshot(at: at.addingTimeInterval(86_400)).counters.working == 1)
    }

    @Test func aSessionKeepsWorkingWhileItsSubagentsRunInTheBackground() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-subagents")

        // The first Stop arrives with both subagents still running.
        let firstStop = fixture.play(into: &core) { $0.event.name == "Stop" }
        #expect(core.snapshot(at: firstStop).counters == Counters(working: 1, finished: 0))

        var core2 = SessionCore()
        let lastStop = fixture.play(into: &core2) { $0.event.name == "Stop" && $0.event.backgroundTasks.isEmpty }
        #expect(core2.snapshot(at: lastStop).counters == Counters(working: 0, finished: 1))
    }

    @Test func aBackgroundCommandDoesNotKeepAFinishedSessionWorking() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: t)
        core.handle(
            HookEvent(name: "Stop", sessionID: "s", backgroundTasks: [.init(type: "shell", status: "running")]),
            at: t + 5
        )

        #expect(core.snapshot(at: t + 5).counters == Counters(working: 0, finished: 1))
    }

    @Test func compactingAFinishedSessionDoesNotRestartItsLivenessClock() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-compaction")
        let stops = fixture.steps.filter { $0.event.name == "Stop" }
        let stopBeforeCompaction = stops[1].at

        let compacted = fixture.play(into: &core) { $0.event.name == "PostCompact" }

        #expect(compacted > stopBeforeCompaction)
        #expect(core.snapshot(at: compacted).counters == Counters(working: 0, finished: 1))
        #expect(core.snapshot(at: stopBeforeCompaction.addingTimeInterval(600)).counters == Counters())
    }

    @Test func compactingMidTurnKeepsTheSessionWorking() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: t)
        core.handle(HookEvent(name: "SessionStart", sessionID: "s", source: "compact"), at: t + 5)

        #expect(core.snapshot(at: t + 5).counters == Counters(working: 1, finished: 0))
    }

    @Test func resumingASessionShowsNothingUntilItsNextTurn() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-resumed")

        let resumed = fixture.play(into: &core) { $0.event.source == "resume" }
        #expect(core.snapshot(at: resumed).counters == Counters())

        var core2 = SessionCore()
        fixture.play(into: &core2) { $0.event.source == "resume" }
        let prompted = fixture.steps.last { $0.event.name == "UserPromptSubmit" }!
        core2.handle(prompted.event, at: prompted.at)
        #expect(core2.snapshot(at: prompted.at).counters == Counters(working: 1, finished: 0))
    }

    @Test func clearingReplacesTheSessionWithoutLeavingTheOldOneBehind() throws {
        var core = SessionCore()
        let at = try Fixture("cli/cli-clear").play(into: &core) { $0.event.source == "clear" }
        #expect(core.snapshot(at: at).counters == Counters())

        var core2 = SessionCore()
        let fixture = try Fixture("cli/cli-clear")
        let lastStop = fixture.steps.last { $0.event.name == "Stop" }!.at
        fixture.play(into: &core2) { $0.at == lastStop }
        #expect(core2.snapshot(at: lastStop).counters == Counters(working: 0, finished: 1))
    }

    @Test func countersAddUpAcrossSessions() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        for id in ["a", "b", "c"] {
            core.handle(HookEvent(name: "UserPromptSubmit", sessionID: id), at: t)
        }
        core.handle(HookEvent(name: "Stop", sessionID: "b"), at: t + 1)

        let snapshot = core.snapshot(at: t + 2)
        #expect(snapshot.counters == Counters(working: 2, finished: 1))
        #expect(snapshot.sessions.map(\.id) == ["a", "c", "b"])
    }

    @Test func aFailedTurnCountsAsFinished() {
        var core = SessionCore()
        let t = Date(timeIntervalSince1970: 1_000)
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s"), at: t)
        core.handle(HookEvent(name: "StopFailure", sessionID: "s"), at: t + 1)

        #expect(core.snapshot(at: t + 1).counters == Counters(working: 0, finished: 1))
    }
}
