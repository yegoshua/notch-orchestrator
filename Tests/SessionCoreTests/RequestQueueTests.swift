import Foundation
import Testing
import SessionCore

private let t = Date(timeIntervalSince1970: 1_000)

private func bash(_ command: String) -> HookEvent.Tool {
    HookEvent.Tool(name: "Bash", subject: command, input: ["command": .string(command)])
}

private func event(_ name: String, _ session: String = "s", tool: HookEvent.Tool? = nil, agentID: String? = nil) -> HookEvent {
    HookEvent(name: name, sessionID: session, cwd: "/work/\(session)-project", tool: tool, agentID: agentID)
}

/// A session mid-turn that asks for permission to run `command`.
private func ask(
    _ core: inout SessionCore, _ id: String, session: String = "s", _ command: String = "./hello.sh", at time: Date = t
) {
    core.handle(event("PermissionRequest", session, tool: bash(command)), at: time, requestID: id)
}

private func json(_ data: Data) throws -> NSDictionary {
    try #require(try JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

private let noDecision = Outcome.noDecision

@Suite struct RecordedPermissionRequests {
    @Test func aRequestIsQueuedWithItsSessionToolAndFullCommand() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-allow")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }

        let snapshot = core.snapshot(at: asked)
        let request = try #require(snapshot.requests.first)
        #expect(snapshot.requests.count == 1)
        #expect(request.id == "r76")
        #expect(request.sessionID == fixture.steps[0].event.sessionID)
        #expect(request.sessionTitle == "Run ./hello.sh with the Bash tool. Do nothing else.")
        #expect(request.project == "sandbox")
        #expect(request.toolName == "Bash")
        #expect(request.detail == "./hello.sh")
        #expect(request.excerpt == nil)
        #expect(request.questions.isEmpty)
        #expect(snapshot.sessions.first?.state == .waitingForPermission)
        #expect(snapshot.sessions.first?.since == asked)
        #expect(snapshot.counters == Counters(waiting: 1))
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func allowingAnswersTheHookAsRecordedAndTheSessionWorksOn() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-allow")
        fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let recorded = try #require(fixture.responses.first)
        let prompted = try #require(fixture.steps.first { $0.event.name == "UserPromptSubmit" }).at

        core.decide(.allow, on: "r76", at: recorded.at)

        let resolutions = core.drainResolutions()
        #expect(resolutions == [Resolution(requestID: "r76", outcome: .allow(updatedInput: nil))])
        #expect(try json(PermissionResponse.body(for: resolutions[0].outcome)) == recorded.body)
        let snapshot = core.snapshot(at: recorded.at)
        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.sessions.first?.state == .working)
        // The turn is the one that was going on before the question, not a new one.
        #expect(snapshot.sessions.first?.since == prompted)
        #expect(core.drainResolutions().isEmpty)

        // The rest of the recording: the tool runs and the turn ends, with nothing more to answer.
        let stopped = fixture.play(into: &core, after: recorded.at) { $0.event.name == "Stop" }
        #expect(core.snapshot(at: stopped).counters == Counters(finished: 1))
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func denyingWithAnExplanationAnswersTheHookAsRecorded() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-deny")
        fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let recorded = try #require(fixture.responses.first)

        core.decide(.deny(explanation: "no"), on: "r89", at: recorded.at)

        let resolutions = core.drainResolutions()
        #expect(resolutions == [Resolution(requestID: "r89", outcome: .deny(message: "no"))])
        #expect(try json(PermissionResponse.body(for: resolutions[0].outcome)) == recorded.body)
        #expect(core.snapshot(at: recorded.at).requests.isEmpty)
        #expect(core.snapshot(at: recorded.at).counters == Counters(working: 1))

        let stopped = fixture.play(into: &core, after: recorded.at) { $0.event.name == "Stop" }
        #expect(core.snapshot(at: stopped).counters == Counters(finished: 1))
    }

    @Test func aRequestAnsweredInTheSessionsOwnDialogGoesWhenItsToolCallReturns() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-yes")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        #expect(core.snapshot(at: asked).requests.map(\.id) == ["r62"])

        // The human pressed Yes in the terminal. Nothing cancels the held hook: only the tool call
        // returning says so.
        let returned = fixture.play(into: &core, after: asked) { $0.event.name == "PostToolUse" }

        let snapshot = core.snapshot(at: returned)
        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.counters == Counters(working: 1))
        // The connection the client left open is released, with no decision.
        #expect(core.drainResolutions() == [Resolution(requestID: "r62", outcome: noDecision)])
        #expect(PermissionResponse.body(for: noDecision).isEmpty)
    }

    @Test func aRequestRefusedInTheSessionsOwnDialogGoesWhenTheClientDropsTheConnection() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let dropped = try #require(fixture.responses.first)
        #expect(dropped.clientDisconnected)

        core.connectionDropped(dropped.requestID, at: dropped.at)

        let snapshot = core.snapshot(at: dropped.at)
        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.counters.waiting == 0)
        #expect(core.drainResolutions() == [Resolution(requestID: "r74", outcome: noDecision)])
    }

    @Test func aRequestWhoseDropWentUnnoticedGoesWithTheSessionsNextPrompt() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-permission-native-no")
        let prompts = fixture.steps.filter { $0.event.name == "UserPromptSubmit" }
        let asked = fixture.play(into: &core, reportingDrops: false) { $0.event.name == "PermissionRequest" }
        #expect(core.snapshot(at: asked).requests.map(\.id) == ["r74"])

        fixture.play(into: &core, after: asked, reportingDrops: false) { $0.at == prompts[1].at }

        let snapshot = core.snapshot(at: prompts[1].at)
        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.sessions.first?.state == .working)
        #expect(snapshot.sessions.first?.since == prompts[1].at)
        #expect(core.drainResolutions() == [Resolution(requestID: "r74", outcome: noDecision)])
    }

    @Test func everyRecordedRequestIsResolvedExactlyOnceByTheEndOfItsSession() throws {
        for name in ["allow", "deny", "native-yes", "native-no"] {
            var core = SessionCore()
            let fixture = try Fixture("cli/cli-permission-\(name)")
            let at = fixture.play(into: &core)

            let resolved = core.drainResolutions().map(\.requestID)
            #expect(resolved == fixture.steps.compactMap(\.requestID), "\(name)")
            #expect(core.snapshot(at: at).requests.isEmpty)
        }
    }

    @Test func aKilledSessionStopsWaitingOnceItsRequestTimesOut() throws {
        var core = SessionCore()
        let fixture = try Fixture("cli/cli-killed")
        let at = fixture.play(into: &core)

        // The recording simply stops: no answer, no Stop, no SessionEnd.
        #expect(core.snapshot(at: at).counters == Counters(waiting: 1))
        #expect(core.snapshot(at: at + 3600).counters == Counters())
    }
}

@Suite struct RequestQueue {
    @Test func requestsFromSeveralSessionsAreQueuedInArrivalOrder() {
        var core = SessionCore()
        for session in ["a", "b"] { core.handle(event("UserPromptSubmit", session), at: t) }
        ask(&core, "1", session: "b", "make b", at: t + 1)
        ask(&core, "2", session: "a", "make a", at: t + 2)
        // Two calls of one batch, both waiting, arriving at the same instant.
        ask(&core, "3", session: "b", "make b2", at: t + 2)

        let snapshot = core.snapshot(at: t + 3)
        #expect(snapshot.requests.map(\.id) == ["1", "2", "3"])
        #expect(snapshot.requests.map(\.sessionID) == ["b", "a", "b"])
        #expect(snapshot.requests.map(\.project) == ["b-project", "a-project", "b-project"])
        #expect(snapshot.requests.map(\.detail) == ["make b", "make a", "make b2"])
        #expect(snapshot.counters == Counters(waiting: 2))
        // Waiting sessions come first, the one waiting longest on top.
        #expect(snapshot.sessions.map(\.id) == ["b", "a"])
        #expect(snapshot.sessions.map(\.needsUser) == [true, true])
    }

    @Test func answeringTheHeadBringsUpTheNextAndNoneIsLost() {
        var core = SessionCore()
        ask(&core, "1", session: "a", at: t)
        ask(&core, "2", session: "b", at: t + 1)
        ask(&core, "3", session: "a", "rm -rf build", at: t + 2)

        core.decide(.allow, on: "1", at: t + 3)
        #expect(core.snapshot(at: t + 3).requests.map(\.id) == ["2", "3"])
        // Session a still has a request open.
        #expect(core.snapshot(at: t + 3).counters == Counters(waiting: 2))

        core.decide(.deny(explanation: nil), on: "2", at: t + 4)
        core.decide(.allow, on: "3", at: t + 5)

        #expect(core.snapshot(at: t + 5).requests.isEmpty)
        #expect(core.snapshot(at: t + 5).counters == Counters(working: 2))
        #expect(core.drainResolutions() == [
            Resolution(requestID: "1", outcome: .allow(updatedInput: nil)),
            Resolution(requestID: "2", outcome: .deny(message: nil)),
            Resolution(requestID: "3", outcome: .allow(updatedInput: nil)),
        ])
    }

    @Test func aDecisionOnARequestThatIsGoneDoesNothing() {
        var core = SessionCore()
        ask(&core, "1")
        core.decide(.allow, on: "1", at: t + 1)
        _ = core.drainResolutions()

        core.decide(.deny(explanation: "late"), on: "1", at: t + 2)
        core.decide(.allow, on: "never-seen", at: t + 2)
        core.connectionDropped("1", at: t + 2)

        #expect(core.drainResolutions().isEmpty)
        #expect(core.snapshot(at: t + 2).counters == Counters(working: 1))
    }

    @Test func aBlankExplanationIsAPlainDeny() {
        var core = SessionCore()
        ask(&core, "1")

        core.decide(.deny(explanation: "  \n"), on: "1", at: t + 1)

        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: .deny(message: nil))])
    }

    @Test func aRequestThatCannotBeShownIsHandedStraightBack() {
        var core = SessionCore()

        // No tool in the payload: there is nothing to ask the user about.
        core.handle(event("PermissionRequest"), at: t, requestID: "1")

        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
        #expect(core.snapshot(at: t).requests.isEmpty)
        #expect(core.snapshot(at: t).counters.waiting == 0)
    }
}

@Suite struct RequestsSettledElsewhere {
    @Test func theSessionsNextToolCallDoesNotClearARequest() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        core.handle(event("PreToolUse", tool: bash("make a")), at: t + 1)
        ask(&core, "1", "make a", at: t + 1)

        // A second call of the same batch starts, and one that needed no permission returns.
        core.handle(event("PreToolUse", tool: bash("ls")), at: t + 2)
        core.handle(event("PostToolUse", tool: bash("ls")), at: t + 3)

        let snapshot = core.snapshot(at: t + 3)
        #expect(snapshot.requests.map(\.id) == ["1"])
        #expect(snapshot.sessions.first?.state == .waitingForPermission)
        #expect(snapshot.sessions.first?.since == t + 1)
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func aReturningToolCallClearsOnlyTheRequestForThatCall() {
        var core = SessionCore()
        ask(&core, "1", "make a", at: t)
        ask(&core, "2", "make b", at: t)

        core.handle(event("PostToolUse", tool: bash("make b")), at: t + 5)

        #expect(core.snapshot(at: t + 5).requests.map(\.id) == ["1"])
        #expect(core.snapshot(at: t + 5).counters == Counters(waiting: 1))
        #expect(core.drainResolutions() == [Resolution(requestID: "2", outcome: noDecision)])
    }

    @Test(arguments: ["PostToolBatch", "Stop", "StopFailure", "UserPromptSubmit"])
    func theEndOfTheBatchOrTheTurnClearsWhatIsLeft(name: String) {
        var core = SessionCore()
        ask(&core, "1", "make a", at: t)
        ask(&core, "2", "make b", at: t)
        ask(&core, "other", session: "x", at: t)

        core.handle(event(name), at: t + 5)

        let snapshot = core.snapshot(at: t + 5)
        #expect(snapshot.requests.map(\.id) == ["other"])
        #expect(snapshot.sessions.first { $0.id == "s" }?.state.needsUser == (name == "StopFailure"))
        #expect(snapshot.counters.waiting == 1)
        #expect(core.drainResolutions().map(\.requestID) == ["1", "2"])
    }

    @Test func aSessionEndingClearsItsRequests() {
        var core = SessionCore()
        ask(&core, "1", session: "a")
        ask(&core, "2", session: "b")

        core.handle(event("SessionEnd", "a"), at: t + 5)

        #expect(core.snapshot(at: t + 5).requests.map(\.id) == ["2"])
        #expect(core.snapshot(at: t + 5).sessions.map(\.id) == ["b"])
        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
    }

    @Test func aSessionWhoseProcessDiedLosesItsRequests() {
        var core = SessionCore()
        ask(&core, "1")

        core.reconcile(Observation(sessionID: "s", process: .dead), observedAt: t + 5)

        #expect(core.snapshot(at: t + 5).requests.isEmpty)
        #expect(core.snapshot(at: t + 5).sessions.isEmpty)
        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
    }

    @Test func aSessionStartedAgainLosesTheRequestsOfItsDeadTurn() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 1)

        core.handle(HookEvent(name: "SessionStart", sessionID: "s", source: "resume"), at: t + 60)

        #expect(core.snapshot(at: t + 60).requests.isEmpty)
        #expect(core.snapshot(at: t + 60).sessions.isEmpty)
        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
    }

    @Test func aSubagentFinishingItsBatchDoesNotClearTheSessionsOwnRequest() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 1)

        core.handle(event("PostToolBatch", agentID: "agent-1"), at: t + 2)
        core.handle(event("SubagentStop", agentID: "agent-1"), at: t + 3)

        #expect(core.snapshot(at: t + 3).requests.map(\.id) == ["1"])
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func aSubagentsRequestOutlivesItsParentsStopAndGoesWithItsOwnBatch() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        core.handle(
            HookEvent(name: "PermissionRequest", sessionID: "s", tool: bash("./hello.sh"), agentID: "agent-1"),
            at: t + 1, requestID: "1")

        // The parent's turn stops while its background subagent is still asking.
        core.handle(
            HookEvent(name: "Stop", sessionID: "s", backgroundTasks: [
                .init(id: "agent-1", type: "subagent", status: "running"),
            ]),
            at: t + 2)
        #expect(core.snapshot(at: t + 2).requests.map(\.id) == ["1"])
        #expect(core.snapshot(at: t + 2).counters == Counters(waiting: 1))

        core.handle(event("PostToolBatch", agentID: "agent-1"), at: t + 3)
        #expect(core.snapshot(at: t + 3).requests.isEmpty)
        #expect(core.snapshot(at: t + 3).counters.waiting == 0)
    }
}

@Suite struct IgnoredRequests {
    @Test func anIgnoredRequestIsGivenBackWithNoDecisionAndItsSessionBecomesUnknown() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 10)
        let timeout = core.settings.requestTimeout
        // Well below the ten minutes Claude Code gives the hook.
        #expect(timeout <= 300)

        core.advance(to: t + 10 + timeout - 1)
        #expect(core.drainResolutions().isEmpty)
        #expect(core.snapshot(at: t + 10 + timeout - 1).counters == Counters(waiting: 1))

        core.advance(to: t + 10 + timeout)

        // Never answered on the user's behalf: Claude Code's own dialog decides.
        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
        let snapshot = core.snapshot(at: t + 10 + timeout)
        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.sessions.first?.state == .unknown)
        #expect(snapshot.sessions.first?.needsUser == false)
        #expect(snapshot.counters == Counters())
    }

    @Test func aSnapshotNeverShowsARequestPastItsTimeout() {
        var core = SessionCore()
        ask(&core, "1")

        // Nothing told the core that time has passed; the snapshot still must not show it as waiting.
        let snapshot = core.snapshot(at: t + core.settings.requestTimeout)

        #expect(snapshot.requests.isEmpty)
        #expect(snapshot.counters.waiting == 0)
    }

    @Test func theTimeoutIsConfigurable() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        ask(&core, "1")

        core.advance(to: t + 29)
        #expect(core.drainResolutions().isEmpty)
        core.advance(to: t + 30)
        #expect(core.drainResolutions().map(\.requestID) == ["1"])
    }

    @Test func onlyTheRequestsThatRanOutAreGivenBack() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        ask(&core, "1", "make a", at: t)
        ask(&core, "2", "make b", at: t + 20)

        core.advance(to: t + 30)

        #expect(core.drainResolutions().map(\.requestID) == ["1"])
        #expect(core.snapshot(at: t + 30).requests.map(\.id) == ["2"])
        #expect(core.snapshot(at: t + 30).counters == Counters(waiting: 1))
    }

    @Test func aSessionThatGaveUpWaitingWorksAgainOnceItsToolCallReturns() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        ask(&core, "1")
        core.advance(to: t + 30)

        // The human answered in the session's own dialog after all.
        core.handle(event("PostToolUse", tool: bash("./hello.sh")), at: t + 40)

        #expect(core.snapshot(at: t + 40).counters == Counters(working: 1))
        #expect(core.drainResolutions().map(\.requestID) == ["1"])
    }
}

@Suite struct HandingARequestBack {
    @Test func theCardGoesAtOnceWithNoDecisionAndTheSessionKeepsWaiting() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 1)

        core.decide(.handBack, on: "1", at: t + 2)

        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
        let snapshot = core.snapshot(at: t + 2)
        #expect(snapshot.requests.isEmpty)
        // Its own dialog is known to be open.
        #expect(snapshot.sessions.first?.state == .waitingForPermission)
        #expect(snapshot.sessions.first?.since == t + 1)
        #expect(snapshot.counters == Counters(waiting: 1))
    }

    @Test func theSessionWorksAgainOnceTheHandedBackCallReturns() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 1)
        core.decide(.handBack, on: "1", at: t + 2)
        _ = core.drainResolutions()

        core.handle(event("PostToolUse", tool: bash("./hello.sh")), at: t + 9)

        let snapshot = core.snapshot(at: t + 9)
        #expect(snapshot.sessions.first?.state == .working)
        #expect(snapshot.sessions.first?.since == t)
        // The connection was already released when the request was handed back.
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func aHandedBackRequestNobodyAnswersLeavesTheSessionUnknownAfterTheTimeout() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        ask(&core, "1", at: t)
        core.decide(.handBack, on: "1", at: t + 20)
        _ = core.drainResolutions()

        // The clock runs from the hand back: that is when the dialog was last known to be open.
        #expect(core.snapshot(at: t + 49).counters == Counters(waiting: 1))
        core.advance(to: t + 50)

        #expect(core.snapshot(at: t + 50).sessions.first?.state == .unknown)
        #expect(core.snapshot(at: t + 50).counters == Counters())
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func handingBackTwiceOrDecidingAfterwardsDoesNothing() {
        var core = SessionCore()
        ask(&core, "1")
        core.decide(.handBack, on: "1", at: t + 1)
        _ = core.drainResolutions()

        core.decide(.handBack, on: "1", at: t + 2)
        core.decide(.allow, on: "1", at: t + 2)

        #expect(core.drainResolutions().isEmpty)
        #expect(core.snapshot(at: t + 2).counters == Counters(waiting: 1))
    }
}

private let twoQuestions: JSONValue = [
    "questions": [
        [
            "question": "Which color?", "header": "Color", "multiSelect": false,
            "options": [
                ["label": "Red", "description": "The color red"],
                ["label": "Green", "description": "The color green"],
                ["label": "Blue", "description": "The color blue"],
            ],
        ],
        [
            "question": "Which sizes?", "header": "Sizes", "multiSelect": true,
            "options": [
                ["label": "Small", "description": "S"], ["label": "Medium", "description": "M"],
                ["label": "Large", "description": "L"],
            ],
        ],
    ],
]

private func askQuestions(_ core: inout SessionCore, _ id: String, at time: Date = t) {
    core.handle(
        event("PermissionRequest", tool: HookEvent.Tool(name: "AskUserQuestion", input: twoQuestions)),
        at: time, requestID: id)
}

@Suite struct AgentQuestions {
    @Test func aQuestionIsQueuedWithItsOptions() throws {
        var core = SessionCore()
        askQuestions(&core, "q")

        let snapshot = core.snapshot(at: t)
        let request = try #require(snapshot.requests.first)
        #expect(request.toolName == "AskUserQuestion")
        #expect(request.questions.map(\.text) == ["Which color?", "Which sizes?"])
        #expect(request.questions.map(\.header) == ["Color", "Sizes"])
        #expect(request.questions.map(\.allowsMultiple) == [false, true])
        #expect(request.questions[0].options.map(\.label) == ["Red", "Green", "Blue"])
        #expect(request.questions[1].options.map(\.description) == ["S", "M", "L"])
        #expect(snapshot.sessions.first?.state == .waitingForAnswer)
        #expect(snapshot.sessions.first?.needsUser == true)
        #expect(snapshot.counters == Counters(waiting: 1))
    }

    @Test func answersGoBackAsTheOriginalInputPlusTheChosenLabels() throws {
        var core = SessionCore()
        askQuestions(&core, "q")

        core.decide(.answer([["Blue"], ["Small", "Large"]]), on: "q", at: t + 1)

        let resolution = try #require(core.drainResolutions().first)
        let body = try json(PermissionResponse.body(for: resolution.outcome))
        // The shape recorded in the prototype (check C18, mock-sdkhost-A5): several choices of one
        // question are joined with ", ".
        let expected = try json(Data(#"""
        {"hookSpecificOutput": {"hookEventName": "PermissionRequest", "decision": {"behavior": "allow", "updatedInput": {
          "questions": [
            {"question": "Which color?", "header": "Color", "options": [{"label": "Red", "description": "The color red"}, {"label": "Green", "description": "The color green"}, {"label": "Blue", "description": "The color blue"}], "multiSelect": false},
            {"question": "Which sizes?", "header": "Sizes", "options": [{"label": "Small", "description": "S"}, {"label": "Medium", "description": "M"}, {"label": "Large", "description": "L"}], "multiSelect": true}],
          "answers": {"Which color?": "Blue", "Which sizes?": "Small, Large"}}}}}
        """#.utf8))
        #expect(body == expected)
        #expect(core.snapshot(at: t + 1).requests.isEmpty)
        #expect(core.snapshot(at: t + 1).counters == Counters(working: 1))
    }

    @Test func anAnswerGivenThroughTheHookMatchesTheRecording() throws {
        var core = SessionCore()
        let fixture = try Fixture("sim/tui-question-answered-by-hook")
        let asked = fixture.play(into: &core) { $0.event.name == "PermissionRequest" }
        let recorded = try #require(fixture.responses.first)
        let request = try #require(core.snapshot(at: asked).requests.first)
        #expect(request.questions.first?.options.map(\.label) == ["Red", "Green", "Blue"])

        core.decide(.answer([["Blue"]]), on: request.id, at: recorded.at)

        let resolution = try #require(core.drainResolutions().first)
        #expect(try json(PermissionResponse.body(for: resolution.outcome)) == recorded.body)

        // The tool call then returns with the answers added to its input; nothing is left to clear.
        let stopped = fixture.play(into: &core, after: recorded.at) { $0.event.name == "Stop" }
        #expect(core.snapshot(at: stopped).counters == Counters(finished: 1))
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func aQuestionAnsweredInTheSessionGoesWhenItsToolCallReturnsWithTheAnswers() {
        var core = SessionCore()
        askQuestions(&core, "q")
        guard case .object(var answered) = twoQuestions else { return }
        answered["answers"] = ["Which color?": "Red", "Which sizes?": "Medium"]

        core.handle(
            event("PostToolUse", tool: HookEvent.Tool(name: "AskUserQuestion", input: .object(answered))), at: t + 5)

        #expect(core.snapshot(at: t + 5).requests.isEmpty)
        #expect(core.drainResolutions() == [Resolution(requestID: "q", outcome: noDecision)])
    }

    @Test func anAnswerThatDoesNotFitTheQuestionsIsNotSent() {
        var core = SessionCore()
        askQuestions(&core, "q")
        ask(&core, "p", at: t)

        core.decide(.answer([["Blue"]]), on: "q", at: t + 1)
        core.decide(.answer([["Blue"], []]), on: "q", at: t + 1)
        core.decide(.answer([["Blue", "Red"], ["Small"]]), on: "q", at: t + 1)
        core.decide(.allow, on: "q", at: t + 1)
        core.decide(.answer([["Blue"]]), on: "p", at: t + 1)

        #expect(core.drainResolutions().isEmpty)
        #expect(core.snapshot(at: t + 1).requests.map(\.id) == ["q", "p"])
    }
}

@Suite struct WhatARequestShows {
    private func request(_ tool: String, _ input: JSONValue) throws -> PendingRequest {
        var core = SessionCore()
        core.handle(event("PermissionRequest", tool: HookEvent.Tool(name: tool, input: input)), at: t, requestID: "1")
        return try #require(core.snapshot(at: t).requests.first)
    }

    @Test func aLongCommandIsShownInFull() throws {
        let command = "for f in $(ls);\ndo\n  echo " + String(repeating: "x", count: 400) + "\ndone"

        #expect(try request("Bash", ["command": .string(command), "description": "loop"]).detail == command)
    }

    @Test func anEditShowsTheFullPathAndAShortExcerptOfTheChange() throws {
        let edit = try request("Edit", [
            "file_path": "/work/app/Sources/Deep/Module/File.swift",
            "old_string": "let a = 1\nlet b = 2", "new_string": "let a = 10\nlet b = 2\nlet c = 3",
        ])

        #expect(edit.detail == "/work/app/Sources/Deep/Module/File.swift")
        #expect(edit.excerpt == "- let a = 1\n- let b = 2\n+ let a = 10\n+ let b = 2\n+ let c = 3")
    }

    @Test func aNewFileShowsItsFirstLinesAndHowMuchMoreThereIs() throws {
        let content = (1...40).map { "line \($0)" }.joined(separator: "\n")
        let write = try request("Write", ["file_path": "/work/app/notes.txt", "content": .string(content)])

        let lines = try #require(write.excerpt).split(separator: "\n")
        #expect(lines.first == "+ line 1")
        #expect(lines.count <= 9)
        #expect(lines.last == "… 32 more lines")
    }

    @Test func aToolWithNoObviousSubjectShowsItsWholeInput() throws {
        let other = try request("mcp__db__run", ["statement": "DROP TABLE users", "confirm": true])

        #expect(other.detail == #"{"confirm":true,"statement":"DROP TABLE users"}"#)
        #expect(other.excerpt == nil)
    }

    @Test func aHookPayloadKeepsTheWholeToolInput() throws {
        let payload = #"{"hook_event_name": "PermissionRequest", "session_id": "s", "tool_name": "Bash", "tool_input": {"command": "ls -la", "timeout": 5000, "run_in_background": false}}"#
        let event = try #require(HookEvent(payload: Data(payload.utf8)))

        #expect(event.tool?.input == ["command": "ls -la", "timeout": .number("5000"), "run_in_background": false])
    }
}

@Suite struct PermissionResponses {
    @Test func theBodiesAreTheOnesClaudeCodeAccepted() {
        func text(_ outcome: Outcome) -> String { String(decoding: PermissionResponse.body(for: outcome), as: UTF8.self) }

        #expect(text(.allow(updatedInput: nil))
            == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#)
        #expect(text(.deny(message: nil))
            == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny"}}}"#)
        #expect(text(.deny(message: "use \"data/colors.txt\"\ninstead"))
            == #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"use \"data/colors.txt\"\ninstead"}}}"#)
        #expect(text(.noDecision) == "")
    }
}

@Suite struct ReconcilingWaitingSessions {
    private func inProgress(at time: Date, process: Observation.Process = .alive) -> Observation {
        Observation(sessionID: "s", process: process, transcript: TranscriptTail(turn: .inProgress, at: time))
    }

    @Test func aTranscriptMidToolCallDoesNotTurnAWaitingSessionBackToWorking() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 5)

        // The transcript ends in the tool call that is waiting, or in the result of a parallel one.
        core.reconcile(inProgress(at: t + 4), observedAt: t + 10)
        core.reconcile(inProgress(at: t + 8), observedAt: t + 10)
        core.reconcile(inProgress(at: t + 8, process: .unknown), observedAt: t + 10)

        let snapshot = core.snapshot(at: t + 10)
        #expect(snapshot.sessions.first?.state == .waitingForPermission)
        #expect(snapshot.requests.map(\.id) == ["1"])
        #expect(core.drainResolutions().isEmpty)
    }

    @Test func aSessionMadeUnknownByTheRequestTimeoutIsNotTakenToBeWorking() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 5)
        core.advance(to: t + 35)

        // Still the same tool call at the end of the transcript: nothing has moved.
        core.reconcile(inProgress(at: t + 4), observedAt: t + 40)

        #expect(core.snapshot(at: t + 40).sessions.first?.state == .unknown)
        #expect(core.snapshot(at: t + 40).counters == Counters())
    }

    @Test func aTranscriptThatMovedOnAfterTheTimeoutShowsTheSessionWorkingAgain() {
        var core = SessionCore(settings: Settings(requestTimeout: 30))
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 5)
        core.advance(to: t + 35)

        core.reconcile(inProgress(at: t + 38), observedAt: t + 40)

        #expect(core.snapshot(at: t + 40).counters == Counters(working: 1))
    }

    @Test func aTurnTheTranscriptClosedTakesItsRequestsWithIt() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)
        ask(&core, "1", at: t + 5)

        // Refused in the session's own dialog and interrupted: no hook says so.
        core.reconcile(
            Observation(
                sessionID: "s", process: .alive,
                transcript: TranscriptTail(turn: .ended(pendingBackgroundAgents: 0), at: t + 7)),
            observedAt: t + 10)

        #expect(core.snapshot(at: t + 10).counters == Counters(finished: 1))
        #expect(core.snapshot(at: t + 10).requests.isEmpty)
        #expect(core.drainResolutions() == [Resolution(requestID: "1", outcome: noDecision)])
    }
}
