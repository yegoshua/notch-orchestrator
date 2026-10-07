import Foundation
import Testing
import SessionCore

private let t = Date(timeIntervalSince1970: 1_000)
private let remote = GitRemote(host: "gitlab.com", path: "group/frontoffice")
private let pipelineURL = "https://gitlab.com/group/frontoffice/-/pipelines/7"
private let jobURL = "https://gitlab.com/group/frontoffice/-/jobs/70"

private func event(_ name: String, _ session: String = "s", tool: HookEvent.Tool? = nil, agentID: String? = nil) -> HookEvent {
    HookEvent(name: name, sessionID: session, cwd: "/work/frontoffice", tool: tool, agentID: agentID)
}

private func bash(_ command: String) -> HookEvent.Tool {
    HookEvent.Tool(name: "Bash", subject: command, input: ["command": .string(command)])
}

/// A session mid-turn runs `command` to its end.
private func run(_ command: String, in core: inout SessionCore, _ session: String = "s", at time: Date = t) {
    core.handle(event("UserPromptSubmit", session), at: time)
    core.handle(event("PreToolUse", session, tool: bash(command)), at: time)
    core.handle(event("PostToolUse", session, tool: bash(command)), at: time)
}

/// The repository was read after the push: `commit` of `branch` went out.
private func pushed(_ core: inout SessionCore, _ commit: String = "abc", branch: String = "feature", at time: Date = t + 1) {
    core.handle(Push(sessionID: "s", commit: commit, branch: branch, remote: remote), readAt: time)
}

private func observe(
    _ core: inout SessionCore, _ lookup: PipelineLookup, commit: String = "abc", request: RequestLink? = nil,
    at time: Date = t + 20
) {
    core.reconcile(PipelineObservation(sessionID: "s", commit: commit, lookup: lookup, request: request), observedAt: time)
}

private func running(_ stage: String? = "test") -> PipelineLookup {
    .found(Pipeline(state: .running(stage: stage), url: pipelineURL))
}

private let passed = PipelineLookup.found(Pipeline(state: .passed, url: pipelineURL))
private let failed = PipelineLookup.found(Pipeline(state: .failed, url: pipelineURL, failedJobURL: jobURL))

private func ci(_ core: SessionCore, at time: Date = t + 30) -> SessionCI? {
    core.snapshot(at: time).sessions.first?.ci
}

/// A session that pushed and whose pipeline was found running.
private func followed(_ mode: InterruptionMode = .smart) -> SessionCore {
    var core = SessionCore(settings: Settings(interruptionMode: mode))
    run("git push", in: &core)
    pushed(&core)
    observe(&core, running())
    return core
}

@Suite struct PushCommands {
    @Test(arguments: [
        "git push", "git push -u origin feature", "git add . && git commit -m 'x' && git push",
        "git -C /work/frontoffice push origin main", "cd app; git push --force-with-lease",
        "GIT_SSH_COMMAND='ssh -i key' git push", "gh pr create --fill", "glab mr create --fill --yes",
        "git commit -m done\ngit push",
    ])
    func aCommandThatPushesIsAPush(command: String) {
        #expect(PushCommand.isPush(command))
    }

    @Test(arguments: [
        "git status", "git stash push", "echo git push", "git push --dry-run", "git push -n origin main",
        "gh pr view 5", "glab mr list", "git log --grep push", "",
    ])
    func aCommandThatOnlyMentionsAPushIsNot(command: String) {
        #expect(!PushCommand.isPush(command))
    }
}

@Suite struct GitRemotes {
    @Test(arguments: [
        "git@gitlab.com:group/apps/frontoffice.git", "https://gitlab.com/group/apps/frontoffice.git",
        "https://user@gitlab.com/group/apps/frontoffice", "ssh://git@gitlab.com:22/group/apps/frontoffice.git",
    ])
    func hostAndProjectAreReadFromARemoteURL(url: String) {
        #expect(GitRemote(url: url) == GitRemote(host: "gitlab.com", path: "group/apps/frontoffice"))
    }

    @Test func whatIsNotARemoteOnAHostIsNotRead() {
        #expect(GitRemote(url: "") == nil)
        #expect(GitRemote(url: "/srv/git/project.git") == nil)
        #expect(GitRemote(url: "../project") == nil)
    }

    @Test func gitHubIsToldFromGitLabByTheHost() {
        #expect(GitRemote(host: "github.com", path: "me/notch").provider == .gitHub)
        #expect(GitRemote(host: "gitlab.com", path: "me/notch").provider == .gitLab)
        // A host of one's own is far more often a GitLab.
        #expect(GitRemote(host: "git.example.com", path: "me/notch").provider == .gitLab)
    }

    @Test func eachProviderHasItsSignInCommand() {
        #expect(GitProvider.gitLab.signInCommand(host: "git.example.com") == "glab auth login --hostname git.example.com")
        #expect(GitProvider.gitHub.signInCommand(host: "github.com") == "gh auth login --hostname github.com")
    }
}

@Suite struct FollowingAPush {
    @Test func aSessionThatPushedHasAPipelineToLookUp() {
        var core = SessionCore()

        run("git push -u origin feature", in: &core)

        #expect(ci(core, at: t + 1) == SessionCI(state: .pending))
        // The repository has to be read first: nothing says yet which commit went out.
        #expect(core.followedPushes == [FollowedPush(sessionID: "s", cwd: "/work/frontoffice", push: nil, request: nil)])
    }

    @Test func aRecordedToolCallOfAPushIsRecognised() throws {
        let payload = """
            {"session_id": "s", "cwd": "/work/frontoffice", "hook_event_name": "PostToolUse", "tool_name": "Bash",
             "tool_input": {"command": "git push origin HEAD", "description": "Push the branch"},
             "tool_response": {"stdout": "", "stderr": "To gitlab.com:group/frontoffice.git", "interrupted": false},
             "tool_use_id": "toolu_01", "duration_ms": 2154}
            """
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)

        core.handle(try #require(HookEvent(payload: Data(payload.utf8))), at: t)

        #expect(ci(core, at: t + 1)?.state == .pending)
    }

    @Test func aSessionThatOnlyReadCodeShowsNoCI() {
        var core = SessionCore()

        run("git log --oneline", in: &core)

        #expect(ci(core, at: t + 1) == nil)
        #expect(core.followedPushes.isEmpty)
    }

    @Test func aPushThatHasNotReturnedIsNotFollowedYet() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)

        core.handle(event("PreToolUse", tool: bash("git push")), at: t)

        #expect(ci(core, at: t + 1) == nil)
    }

    @Test func aPushMadeByASubagentIsItsSessions() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)

        core.handle(event("PostToolUse", tool: bash("git push"), agentID: "a1"), at: t)

        #expect(ci(core, at: t + 1)?.state == .pending)
    }

    @Test func onceTheRepositoryWasReadThePipelineOfThatCommitIsLookedUp() {
        var core = SessionCore()
        run("git push", in: &core)

        pushed(&core, "abc", branch: "feature")

        let push = Push(sessionID: "s", commit: "abc", branch: "feature", remote: remote)
        #expect(core.followedPushes == [FollowedPush(sessionID: "s", cwd: "/work/frontoffice", push: push, request: nil)])
    }

    @Test func aPushNobodyHookedIsNotFollowed() {
        var core = SessionCore()
        core.handle(event("UserPromptSubmit"), at: t)

        pushed(&core)
        observe(&core, running())

        #expect(ci(core) == nil)
    }

    @Test func aRunningPipelineShowsItsStage() {
        let core = followed()

        #expect(ci(core) == SessionCI(state: .running(stage: "test"), url: pipelineURL))
    }

    @Test func theStageMovesOnWithThePipeline() {
        var core = followed()

        observe(&core, running("deploy"), at: t + 40)

        #expect(ci(core, at: t + 41)?.state == .running(stage: "deploy"))
    }

    @Test func aPipelineThatPassedShowsAsPassedAndIsNoLongerLookedUp() {
        var core = followed()

        observe(&core, passed, at: t + 40)

        #expect(ci(core, at: t + 41) == SessionCI(state: .passed, url: pipelineURL))
        #expect(core.followedPushes.isEmpty)
    }

    @Test func aFailedPipelineLinksToTheJobThatFailed() {
        var core = followed()

        observe(&core, failed, at: t + 40)

        #expect(ci(core, at: t + 41) == SessionCI(state: .failed, url: jobURL))
    }

    @Test func aFailedPipelineDoesNotMakeTheSessionNeedTheUser() {
        var core = followed()
        core.handle(event("Stop"), at: t + 30)

        observe(&core, failed, at: t + 40)

        let snapshot = core.snapshot(at: t + 41)
        #expect(snapshot.sessions.first?.needsUser == false)
        #expect(snapshot.counters == Counters(finished: 1))
    }

    @Test func aPipelineOfAnotherCommitIsNotMistakenForIt() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core, "abc")

        observe(&core, passed, commit: "older")

        #expect(ci(core)?.state == .pending)
    }

    @Test func aPipelineThatCannotBeConfirmedIsUnknownNeverPassed() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core)

        observe(&core, .unknown)

        #expect(ci(core)?.state == .unknown)
        #expect(core.followedPushes.isEmpty)
    }

    @Test func aPipelineThatEndedInAWayNobodyCanTellIsUnknown() {
        var core = followed()

        observe(&core, .found(Pipeline(state: .unknown, url: pipelineURL)), at: t + 40)

        #expect(ci(core, at: t + 41) == SessionCI(state: .unknown, url: pipelineURL))
        #expect(core.followedPushes.isEmpty)
    }

    @Test func oneAnswerThatCannotBeReadDoesNotEndARunningPipeline() {
        var core = followed()

        observe(&core, .unknown, at: t + 40)
        #expect(ci(core, at: t + 41)?.state == .running(stage: "test"))

        observe(&core, passed, at: t + 60)
        #expect(ci(core, at: t + 61)?.state == .passed)
    }

    @Test func aLookAtTheRepositoryFromBeforeThePushSaysNothingAboutIt() {
        var core = followed()
        run("git push", in: &core, at: t + 50)

        // Read for the first push, delivered late.
        pushed(&core, "abc", at: t + 45)

        #expect(core.followedPushes.map(\.push) == [nil])
    }

    @Test func aRunningPipelineNobodyConfirmsAnyMoreBecomesUnknown() {
        var core = followed()

        // Lookups keep failing or stopped altogether.
        observe(&core, .noAccess, at: t + 40)

        #expect(ci(core, at: t + 60)?.state == .running(stage: "test"))
        #expect(ci(core, at: t + 20 + 300)?.state == .unknown)
    }

    @Test func aHostThatCannotBeReachedIsNamed() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core)

        observe(&core, .noAccess)

        #expect(ci(core) == SessionCI(state: .noAccess(host: "gitlab.com")))
    }

    @Test func aHostThatCouldNotBeReachedIsAskedAgainAndWorksOnceSignedIn() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core)
        observe(&core, .noAccess)

        // Still to be asked, though not as often as a pipeline that runs.
        #expect(core.followedPushes.map(\.lacksAccess) == [true])
        observe(&core, running("build"), at: t + 80)

        #expect(ci(core, at: t + 81)?.state == .running(stage: "build"))
        #expect(core.followedPushes.map(\.lacksAccess) == [false])
    }

    @Test func aHostThatCannotBeReachedDoesNotKeepTheSessionInTheList() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core)
        core.handle(event("Stop"), at: t + 2)

        observe(&core, .noAccess)

        // Ten minutes from the moment it was found out.
        #expect(core.snapshot(at: t + 20 + 599).sessions.map(\.id) == ["s"])
        #expect(core.snapshot(at: t + 20 + 600).sessions.isEmpty)
    }

    @Test func aCommitWithoutAPipelineShowsNothingAfterAShortWait() {
        var core = SessionCore()
        run("git push", in: &core)
        pushed(&core)

        observe(&core, .noPipeline)

        #expect(ci(core, at: t + 60)?.state == .pending)
        #expect(ci(core, at: t + 120) == nil)
        core.advance(to: t + 120)
        #expect(core.followedPushes.isEmpty)
    }

    @Test func aPushWhoseRepositoryCannotBeReadShowsNothingAfterAShortWait() {
        var core = SessionCore()

        run("git push", in: &core)

        #expect(ci(core, at: t + 120) == nil)
    }

    @Test func aSecondPushReplacesThePipelineBeingFollowed() {
        var core = followed()

        run("git push", in: &core, at: t + 50)
        pushed(&core, "def", at: t + 51)

        #expect(ci(core, at: t + 52) == SessionCI(state: .pending))
        observe(&core, passed, commit: "abc", at: t + 60)
        #expect(ci(core, at: t + 61)?.state == .pending)
        observe(&core, running("build"), commit: "def", at: t + 60)
        #expect(ci(core, at: t + 61)?.state == .running(stage: "build"))
    }

    @Test func openingARequestForTheCommitAlreadyPushedKeepsItsPipeline() {
        var core = followed()
        observe(&core, passed, at: t + 40)
        _ = core.drainInterruptions()

        run("gh pr create --fill", in: &core, at: t + 50)
        // The repository is read again, in case something new went out.
        #expect(core.followedPushes.map(\.push) == [nil])
        pushed(&core, "abc", at: t + 51)

        #expect(ci(core, at: t + 52)?.state == .passed)
        #expect(core.followedPushes.isEmpty)
        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func theRequestOfTheBranchIsLinked() {
        var core = SessionCore()
        run("glab mr create --fill", in: &core)
        pushed(&core)
        let request = RequestLink(number: 12, url: "https://gitlab.com/group/frontoffice/-/merge_requests/12", branch: "feature")

        observe(&core, .noPipeline, request: request)

        #expect(ci(core) == SessionCI(state: .pending, request: request))
        #expect(core.followedPushes.first?.request == request)
    }

    @Test func theRequestTheDesktopAppTiedToTheSessionIsLinked() {
        var core = followed()
        let other = RequestLink(number: 95, url: "https://github.com/me/shop/pull/95", branch: "other", state: "MERGED")
        let mine = RequestLink(number: 96, url: "https://github.com/me/shop/pull/96", branch: "feature", state: "OPEN")

        core.reconcile(Observation(sessionID: "s", process: .alive, requests: [other, mine]), observedAt: t + 25)

        #expect(ci(core)?.request == mine)
    }
}

@Suite struct LivenessWhileAPipelineRuns {
    @Test func aSessionStaysInTheListWhileItsPipelineRunsThoughItsTurnEndedLongAgo() {
        var core = followed()
        core.handle(event("Stop"), at: t + 30)
        for minute in 1...30 { observe(&core, running("deploy"), at: t + TimeInterval(minute * 60)) }

        let snapshot = core.snapshot(at: t + 1800)

        #expect(snapshot.sessions.map(\.id) == ["s"])
        #expect(snapshot.sessions.first?.state == .finishedTurn)
    }

    @Test func aSessionWaitingForItsPipelineToAppearStaysToo() {
        var core = SessionCore(settings: Settings(livenessThreshold: 60))
        run("git push", in: &core)
        pushed(&core)
        core.handle(event("Stop"), at: t + 2)

        #expect(core.snapshot(at: t + 90).sessions.map(\.id) == ["s"])
        #expect(core.snapshot(at: t + 130).sessions.isEmpty)
    }

    @Test func onceThePipelineEndedTheSessionLeavesOnTheUsualSchedule() {
        var core = followed()
        core.handle(event("Stop"), at: t + 30)
        for minute in 1..<20 { observe(&core, running("deploy"), at: t + TimeInterval(minute * 60)) }

        observe(&core, passed, at: t + 1200)

        // Ten minutes from the end of the pipeline, not from the end of the turn.
        #expect(core.snapshot(at: t + 1200 + 599).sessions.map(\.id) == ["s"])
        #expect(core.snapshot(at: t + 1200 + 600).sessions.isEmpty)
    }

    @Test func aSessionThatEndedTakesItsPipelineWithIt() {
        var core = followed()

        core.handle(event("SessionEnd"), at: t + 30)

        #expect(core.snapshot(at: t + 31).sessions.isEmpty)
        #expect(core.followedPushes.isEmpty)
    }
}

@Suite struct PipelineLines {
    private func line(_ kind: TransientLine.Kind) -> TransientLine {
        TransientLine(sessionID: "s", title: nil, project: "frontoffice", kind: kind)
    }

    @Test func aPipelineThatPassedShowsASilentLineInSmartMode() {
        var core = followed(.smart)
        _ = core.drainInterruptions()

        observe(&core, passed, at: t + 40)

        #expect(core.drainInterruptions() == [.line(line(.ciPassed), sound: false)])
    }

    @Test func aPipelineThatFailedShowsASilentLineInSmartMode() {
        var core = followed(.smart)
        _ = core.drainInterruptions()

        observe(&core, failed, at: t + 40)

        #expect(core.drainInterruptions() == [.line(line(.ciFailed), sound: false)])
    }

    @Test func inLoudModeTheLineComesWithASound() {
        var core = followed(.loud)
        _ = core.drainInterruptions()

        observe(&core, failed, at: t + 40)

        #expect(core.drainInterruptions() == [.line(line(.ciFailed), sound: true)])
    }

    @Test func inQuietModeThereIsNoLine() {
        var core = followed(.quiet)

        observe(&core, passed, at: t + 40)

        #expect(core.drainInterruptions().isEmpty)
        #expect(ci(core, at: t + 41)?.state == .passed)
    }

    @Test func underAFocusThereIsNoLine() {
        var core = followed(.loud)
        core.attend(Attention(focusIsOn: true), at: t + 30)
        _ = core.drainInterruptions()

        observe(&core, failed, at: t + 40)

        #expect(core.drainInterruptions().isEmpty)
    }

    @Test func theLineComesAlsoWhenTheSessionIsInFront() {
        // The window of the session does not say how its pipeline went.
        var core = followed(.smart)
        core.reconcile(Observation(sessionID: "s", process: .alive, location: .terminalApp(tty: "/dev/ttys001")), observedAt: t + 25)
        core.attend(
            Attention(frontWindow: FrontWindow(bundleID: SessionLocation.terminalBundleID, terminalTTY: "/dev/ttys001")),
            at: t + 30)
        _ = core.drainInterruptions()

        observe(&core, passed, at: t + 40)

        #expect(core.drainInterruptions() == [.line(line(.ciPassed), sound: false)])
    }

    @Test func onlyPassingAndFailingShowALine() {
        var core = followed(.loud)
        _ = core.drainInterruptions()

        observe(&core, running("deploy"), at: t + 40)
        observe(&core, .unknown, at: t + 60)

        #expect(core.drainInterruptions().isEmpty)
    }
}
