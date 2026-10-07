import Foundation
import Testing
import SessionCore

private let t = Date(timeIntervalSince1970: 1_000)
private let terminal = SessionLocation.terminalBundleID
private let claude = SessionLocation.claudeDesktopBundleID
private let browser = "com.apple.Safari"

private func event(_ name: String, _ session: String = "s", tool: HookEvent.Tool? = nil) -> HookEvent {
    HookEvent(name: name, sessionID: session, cwd: "/work/\(session)-project", tool: tool)
}

private func bash(_ command: String) -> HookEvent.Tool {
    HookEvent.Tool(name: "Bash", subject: command, input: ["command": .string(command)])
}

private func core(_ mode: InterruptionMode) -> SessionCore {
    SessionCore(settings: Settings(interruptionMode: mode))
}

/// A session mid-turn that is known to run at `location`.
private func work(_ core: inout SessionCore, _ session: String = "s", in location: SessionLocation = .terminalApp(tty: "/dev/ttys001")) {
    core.handle(event("UserPromptSubmit", session), at: t)
    core.reconcile(Observation(sessionID: session, process: .alive, location: location), observedAt: t)
}

private func ask(_ core: inout SessionCore, _ id: String, session: String = "s", at time: Date = t + 1) {
    core.handle(event("PermissionRequest", session, tool: bash("./hello.sh")), at: time, requestID: id)
}

/// The user looks at a window of the application `bundleID`; in Terminal, at the tab on `tty`.
private func look(_ core: inout SessionCore, at bundleID: String, tty: String? = nil, focus: Bool = false, time: Date = t) {
    core.attend(Attention(frontWindow: FrontWindow(bundleID: bundleID, terminalTTY: tty), focusIsOn: focus), at: time)
}

private func finished(_ session: String = "s", _ kind: TransientLine.Kind = .finished) -> TransientLine {
    TransientLine(sessionID: session, title: nil, project: "\(session)-project", kind: kind)
}

private func raised(_ core: SessionCore, at time: Date = t + 2) -> [String] {
    core.snapshot(at: time).raised.map(\.id)
}

@Suite struct SmartInterruptions {
    @Test func aRequestFromASessionThatIsNotInFrontExpandsWithASound() {
        var core = core(.smart)
        work(&core)
        look(&core, at: browser)

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
        #expect(raised(core) == ["r1"])
        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func nothingIsKnownAboutTheFrontWindowSoTheRequestExpands() {
        var core = core(.smart)
        work(&core)

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func aRequestFromTheTerminalTabInFrontNeitherExpandsNorSounds() {
        var core = core(.smart)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys001")

        ask(&core, "r1")

        #expect(core.drainInterruptions().isEmpty)
        let snapshot = core.snapshot(at: t + 2)
        #expect(snapshot.raised.isEmpty)
        // It is still there to be answered, and still counted.
        #expect(snapshot.requests.map(\.id) == ["r1"])
        #expect(snapshot.counters == Counters(waiting: 1))
    }

    @Test func anotherTabOfTheSameTerminalIsNotTheSession() {
        var core = core(.smart)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys007")

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func whenTheTabCannotBeToldTheOnlySessionInTerminalCountsAsInFront() {
        var core = core(.smart)
        work(&core)
        look(&core, at: terminal)

        ask(&core, "r1")

        #expect(core.drainInterruptions().isEmpty)
        #expect(raised(core).isEmpty)
    }

    @Test func theOnlySessionOfTheDesktopAppIsInFrontWhenTheAppIs() {
        var core = core(.smart)
        work(&core, in: .desktopApp(sessionID: "local_1"))
        look(&core, at: claude)

        ask(&core, "r1")

        #expect(core.drainInterruptions().isEmpty)
        #expect(raised(core).isEmpty)
    }

    @Test func withSeveralSessionsInAnAppWhoseWindowsCannotBeToldApartTheRequestExpands() {
        var core = core(.smart)
        work(&core, "a", in: .desktopApp(sessionID: "local_1"))
        work(&core, "b", in: .desktopApp(sessionID: "local_2"))
        look(&core, at: claude)

        ask(&core, "r1", session: "a")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func aSessionWhoseLocationIsUnknownIsNeverInFront() {
        var core = core(.smart)
        work(&core, in: .unknown)
        look(&core, at: terminal, tty: "/dev/ttys001")

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func leavingASessionThatStillAsksBringsItsRequestUpWithoutASound() {
        var core = core(.smart)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys001")
        ask(&core, "r1")

        look(&core, at: browser, time: t + 5)

        // The user has seen the session's own dialog: this is no news.
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: false)])
        #expect(raised(core, at: t + 5) == ["r1"])
    }

    @Test func leavingASessionThatWasOnlyAssumedToBeInFrontStillMakesItsSound() {
        var core = core(.smart)
        work(&core, in: .desktopApp(sessionID: "local_1"))
        look(&core, at: claude)
        ask(&core, "r1")
        #expect(core.drainInterruptions().isEmpty)

        look(&core, at: browser, time: t + 5)

        // The user may have been in another window of the app and never seen the dialog.
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func comingToTheAskingSessionTakesItsRequestDownAndASoundIsMadeOnlyOnce() {
        var core = core(.smart)
        work(&core)
        look(&core, at: browser)
        ask(&core, "r1")
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])

        look(&core, at: terminal, tty: "/dev/ttys001", time: t + 5)
        #expect(core.drainInterruptions().isEmpty)
        #expect(raised(core, at: t + 5).isEmpty)
        #expect(core.snapshot(at: t + 5).requests.map(\.id) == ["r1"])

        look(&core, at: browser, time: t + 9)
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: false)])
    }

    @Test func onlyRequestsOfSessionsThatAreNotInFrontAreRaised() {
        var core = core(.smart)
        work(&core, "a", in: .terminalApp(tty: "/dev/ttys001"))
        work(&core, "b", in: .terminalApp(tty: "/dev/ttys002"))
        look(&core, at: terminal, tty: "/dev/ttys001")

        ask(&core, "r1", session: "a", at: t + 1)
        ask(&core, "r2", session: "b", at: t + 2)

        #expect(core.drainInterruptions() == [.expand(requestID: "r2", sound: true)])
        let snapshot = core.snapshot(at: t + 3)
        #expect(snapshot.requests.map(\.id) == ["r1", "r2"])
        #expect(snapshot.raised.map(\.id) == ["r2"])
    }

    @Test func anAnsweredRequestIsNoLongerRaised() {
        var core = core(.smart)
        work(&core)
        ask(&core, "r1")

        core.decide(.allow, on: "r1", at: t + 2)

        #expect(raised(core).isEmpty)
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func aRequestHandedBackToTheSessionIsNoLongerRaised() {
        var core = core(.smart)
        work(&core)
        ask(&core, "r1")

        core.decide(.handBack, on: "r1", at: t + 2)
        look(&core, at: browser, time: t + 3)

        #expect(raised(core, at: t + 3).isEmpty)
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func aFinishedTurnShowsASilentLine() {
        var core = core(.smart)
        work(&core)
        look(&core, at: browser)

        core.handle(event("Stop"), at: t + 4)

        #expect(core.drainInterruptions() == [.line(finished(), sound: false)])
        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func theLineCarriesTheSessionsTitle() {
        var core = core(.smart)
        core.handle(HookEvent(name: "UserPromptSubmit", sessionID: "s", cwd: "/work/frontoffice", prompt: "Validate deposit limits"), at: t)

        core.handle(HookEvent(name: "Stop", sessionID: "s"), at: t + 4)

        #expect(core.drainInterruptions() == [.line(
            TransientLine(sessionID: "s", title: "Validate deposit limits", project: "frontoffice", kind: .finished),
            sound: false)])
    }

    @Test func aFailedTurnShowsASilentLine() {
        var core = core(.smart)
        work(&core)

        core.handle(event("StopFailure"), at: t + 4)

        #expect(core.drainInterruptions() == [.line(finished("s", .failed), sound: false)])
    }

    @Test func aTurnThatFinishesInFrontOfTheUserShowsNoLine() {
        var core = core(.smart)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys001")

        core.handle(event("Stop"), at: t + 4)

        #expect(core.drainInterruptions().isEmpty)
        #expect(core.snapshot(at: t + 4).counters == Counters(finished: 1))
    }

    @Test func aStopThatLeavesBackgroundAgentsRunningIsNotAFinishedTurn() {
        var core = core(.smart)
        work(&core)
        var stop = event("Stop")
        stop.backgroundTasks = [HookEvent.BackgroundTask(id: "a1", type: "subagent", status: "running")]

        core.handle(stop, at: t + 4)

        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func aTurnIsAnnouncedOnceHoweverOftenItsEndIsReported() {
        var core = core(.smart)
        work(&core)
        core.handle(event("Stop"), at: t + 4)
        _ = core.drainInterruptions()

        core.handle(event("Stop"), at: t + 5)
        core.reconcile(
            Observation(sessionID: "s", process: .alive, transcript: TranscriptTail(turn: .ended(pendingBackgroundAgents: 0), at: t + 5)),
            observedAt: t + 6)

        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func ordinaryActivityInterruptsNothing() {
        var core = core(.smart)
        look(&core, at: browser)

        core.handle(event("SessionStart"), at: t)
        core.handle(event("UserPromptSubmit"), at: t + 1)
        core.handle(event("PreToolUse", tool: bash("ls")), at: t + 2)
        core.handle(event("PostToolUse", tool: bash("ls")), at: t + 3)
        core.handle(event("PreCompact"), at: t + 4)
        core.handle(event("PostCompact"), at: t + 5)

        #expect(core.drainInterruptions().isEmpty)
        // All there is to see is the colour of a counter.
        #expect(core.snapshot(at: t + 5).counters == Counters(working: 1))
    }

    @Test func aTurnThatReconciliationFindsClosedShowsALine() {
        var core = core(.smart)
        work(&core)

        core.reconcile(
            Observation(sessionID: "s", process: .alive, transcript: TranscriptTail(turn: .ended(pendingBackgroundAgents: 0), at: t + 30)),
            observedAt: t + 31)

        #expect(core.drainInterruptions() == [.line(finished(), sound: false)])
    }

    @Test func aSessionRebuiltFromItsTranscriptAnnouncesNothing() {
        var core = core(.smart)

        core.reconcile(
            Observation(
                sessionID: "old", process: .alive, transcript: TranscriptTail(turn: .ended(pendingBackgroundAgents: 0), at: t - 60),
                cwd: "/work/old-project"),
            observedAt: t)

        #expect(core.snapshot(at: t).counters == Counters(finished: 1))
        #expect(core.drainInterruptions().isEmpty)
    }
}

@Suite struct InterruptionsUnderFocus {
    @Test(arguments: [InterruptionMode.loud, .smart, .quiet])
    func focusSuppressesSoundAndExpansion(mode: InterruptionMode) {
        var core = core(mode)
        work(&core, "a")
        work(&core, "b")
        look(&core, at: browser, focus: true)

        ask(&core, "r1", session: "a")
        core.handle(event("Stop", "b"), at: t + 2)

        #expect(core.drainInterruptions().isEmpty)
        let snapshot = core.snapshot(at: t + 2)
        #expect(snapshot.raised.isEmpty)
        #expect(snapshot.requests.map(\.id) == ["r1"])
        #expect(snapshot.counters == Counters(waiting: 1, finished: 1))
    }

    @Test func focusSuppressesTheSessionInFrontToo() {
        var core = core(.loud)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys001", focus: true)

        ask(&core, "r1")

        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func whenFocusEndsWhatStillWaitsIsBroughtUp() {
        var core = core(.smart)
        work(&core)
        look(&core, at: browser, focus: true)
        ask(&core, "r1")

        look(&core, at: browser, focus: false, time: t + 60)

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
        #expect(raised(core, at: t + 60) == ["r1"])
    }

    @Test func focusComingOnTakesARaisedRequestDown() {
        var core = core(.smart)
        work(&core)
        look(&core, at: browser)
        ask(&core, "r1")

        look(&core, at: browser, focus: true, time: t + 5)

        #expect(raised(core, at: t + 5).isEmpty)
        #expect(core.snapshot(at: t + 5).requests.map(\.id) == ["r1"])
    }
}

@Suite struct LoudInterruptions {
    @Test func aRequestExpandsWithASoundWhenItsSessionIsNotInFront() {
        var core = core(.loud)
        work(&core)
        look(&core, at: browser)

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }

    @Test func aRequestExpandsWithASoundEvenWhenItsSessionIsInFront() {
        var core = core(.loud)
        work(&core)
        look(&core, at: terminal, tty: "/dev/ttys001")

        ask(&core, "r1")

        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
        #expect(raised(core) == ["r1"])
    }

    @Test func aFinishedTurnShowsItsLineWithASoundWhereverTheSessionIs() {
        var core = core(.loud)
        work(&core, "a", in: .terminalApp(tty: "/dev/ttys001"))
        work(&core, "b", in: .terminalApp(tty: "/dev/ttys002"))
        look(&core, at: terminal, tty: "/dev/ttys001")

        core.handle(event("Stop", "a"), at: t + 4)
        core.handle(event("StopFailure", "b"), at: t + 5)

        #expect(core.drainInterruptions() == [
            .line(finished("a"), sound: true), .line(finished("b", .failed), sound: true),
        ])
    }

    @Test func ordinaryActivityStillInterruptsNothing() {
        var core = core(.loud)
        look(&core, at: browser)

        core.handle(event("UserPromptSubmit"), at: t + 1)
        core.handle(event("PreToolUse", tool: bash("ls")), at: t + 2)
        core.handle(event("PostToolUse", tool: bash("ls")), at: t + 3)

        #expect(core.drainInterruptions().isEmpty)
    }
}

@Suite struct QuietInterruptions {
    @Test(arguments: [browser, terminal])
    func aRequestNeitherExpandsNorSoundsWhereverTheUserLooks(front: String) {
        var core = core(.quiet)
        work(&core)
        look(&core, at: front, tty: front == terminal ? "/dev/ttys001" : nil)

        ask(&core, "r1")

        #expect(core.drainInterruptions().isEmpty)
        let snapshot = core.snapshot(at: t + 2)
        #expect(snapshot.raised.isEmpty)
        // The counter is the only sign, and the request can still be answered.
        #expect(snapshot.requests.map(\.id) == ["r1"])
        #expect(snapshot.counters == Counters(waiting: 1))
    }

    @Test func aFinishedOrFailedTurnShowsNoLine() {
        var core = core(.quiet)
        work(&core, "a")
        work(&core, "b")
        look(&core, at: browser)

        core.handle(event("Stop", "a"), at: t + 4)
        core.handle(event("StopFailure", "b"), at: t + 5)

        #expect(core.drainInterruptions().isEmpty)
        #expect(core.snapshot(at: t + 5).counters == Counters(finished: 1, failed: 1))
    }

    @Test func switchingToSmartBringsUpWhatStillWaits() {
        var core = core(.quiet)
        work(&core)
        look(&core, at: browser)
        ask(&core, "r1")

        core.settings.interruptionMode = .smart

        #expect(raised(core, at: t + 3) == ["r1"])
        core.advance(to: t + 3)
        #expect(core.drainInterruptions() == [.expand(requestID: "r1", sound: true)])
    }
}

@Suite struct RecordedInterruptions {
    @Test func aRecordedPermissionRequestInterruptsOnceAndItsTurnEndsWithALine() throws {
        var core = core(.smart)
        let fixture = try Fixture("cli/cli-permission-allow")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        #expect(core.drainInterruptions() == [.expand(requestID: "r76", sound: true)])

        core.decide(.allow, on: "r76", at: asked)
        fixture.play(into: &core, after: asked) { $0.event.name == "Stop" }

        let rest = core.drainInterruptions()
        #expect(rest.count == 1)
        guard case .line(let line, sound: false)? = rest.first else {
            Issue.record("expected a silent line, got \(rest)")
            return
        }
        #expect(line.kind == .finished)
        #expect(line.project == "sandbox")
    }

    @Test func aRecordedTurnWithoutRequestsInterruptsOnlyWithItsLine() throws {
        var core = core(.smart)
        let fixture = try Fixture("cli/cli-normal-turn")
        fixture.play(into: &core)

        let all = core.drainInterruptions()
        #expect(all.allSatisfy { if case .line(_, sound: false) = $0 { true } else { false } })
        #expect(all.count == fixture.steps.filter { $0.event.name == "Stop" }.count)
    }
}

/// Reading whether a macOS Focus is on from the system's own record of it.
@Suite struct FocusRecords {
    @Test func aFocusTheUserTurnedOnIsOn() {
        let json = """
            {"data": [{"storeAssertionRecords": [{"assertionDetails": {
                "assertionDetailsIdentifier": "com.apple.focus.activity-manager",
                "assertionDetailsModeIdentifier": "com.apple.donotdisturb.mode.default",
                "assertionDetailsReason": "user-action"}, "assertionUUID": "A1"}],
              "storeInvalidationRecords": []}], "header": {"version": 1}}
            """
        #expect(FocusRecord.isOn(json: Data(json.utf8)) == true)
    }

    @Test func withNoAssertionNoFocusIsOn() {
        #expect(FocusRecord.isOn(json: Data(#"{"data": [{"storeInvalidationRecords": [{"x": 1}]}], "header": {}}"#.utf8)) == false)
        #expect(FocusRecord.isOn(json: Data(#"{"data": [{"storeAssertionRecords": []}]}"#.utf8)) == false)
        #expect(FocusRecord.isOn(json: Data(#"{"data": []}"#.utf8)) == false)
    }

    @Test func whatIsNotTheRecordSaysNothing() {
        #expect(FocusRecord.isOn(json: Data("not json".utf8)) == nil)
        #expect(FocusRecord.isOn(json: Data(#"{"header": {}}"#.utf8)) == nil)
        #expect(FocusRecord.isOn(json: Data()) == nil)
    }
}
