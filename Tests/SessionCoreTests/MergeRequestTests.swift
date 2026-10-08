import Foundation
import Testing
import SessionCore

private let t = Date(timeIntervalSince1970: 1_000)
private let remote = GitRemote(host: "gitlab.com", path: "group/frontoffice")
private let requestURL = "https://gitlab.com/group/frontoffice/-/merge_requests/12"
private let pipelineURL = "https://gitlab.com/group/frontoffice/-/pipelines/7"
private let jobURL = "https://gitlab.com/group/frontoffice/-/jobs/70"
private let id = FollowedMergeRequest.ID(remote: remote, number: 12)
/// Long after the session that pushed has left the list.
private let later = t + 3_600

private func event(_ name: String, _ session: String, tool: HookEvent.Tool? = nil) -> HookEvent {
    HookEvent(name: name, sessionID: session, cwd: "/work/frontoffice", tool: tool)
}

/// A session pushes `commit` to `branch`, its turn ends, and the host is asked about the push.
private func push(
    _ core: inout SessionCore, _ session: String = "s", commit: String = "abc", branch: String = "feature",
    to remote: GitRemote = remote, request: RequestLink? = RequestLink(number: 12, url: requestURL, branch: "feature", state: "opened"),
    at time: Date = t
) {
    let bash = HookEvent.Tool(name: "Bash", subject: "git push", input: ["command": .string("git push")])
    core.handle(event("UserPromptSubmit", session), at: time)
    core.handle(event("PreToolUse", session, tool: bash), at: time)
    core.handle(event("PostToolUse", session, tool: bash), at: time)
    core.handle(event("Stop", session), at: time)
    core.handle(Push(sessionID: session, commit: commit, branch: branch, remote: remote), readAt: time + 1)
    core.reconcile(
        PipelineObservation(
            sessionID: session, commit: commit, lookup: .found(Pipeline(state: .passed, url: pipelineURL)), request: request),
        observedAt: time + 20)
}

private func open(_ pipeline: PipelineLookup = .noPipeline, title: String = "Add the funnel events") -> MergeRequestLookup {
    .found(MergeRequestStatus(state: .open, title: title, url: requestURL, branch: "feature", pipeline: pipeline))
}

private func observe(_ core: inout SessionCore, _ lookup: MergeRequestLookup, at time: Date = t + 30) {
    core.reconcile(MergeRequestObservation(id: id, lookup: lookup), observedAt: time)
}

/// A session pushed to merge request 12 and the host was asked about it once.
private func followed() -> SessionCore {
    var core = SessionCore()
    push(&core)
    observe(&core, open())
    return core
}

@Suite struct FollowingAMergeRequest {
    @Test func theMergeRequestASessionPushedToIsInTheSectionOnceTheSessionLeftTheList() {
        let core = followed()

        #expect(core.snapshot(at: later).sessions.isEmpty)
        #expect(core.snapshot(at: later).mergeRequests == [
            FollowedMergeRequest(remote: remote, number: 12, url: requestURL, title: "Add the funnel events", branch: "feature"),
        ])
    }

    @Test func whileItsSessionIsInTheListItIsInThatRowOnly() {
        let core = followed()

        let snapshot = core.snapshot(at: t + 60)
        #expect(snapshot.sessions.first?.ci?.request?.number == 12)
        #expect(snapshot.mergeRequests.isEmpty)
        #expect(core.followedMergeRequests.map(\.number) == [12])
    }

    @Test func aPushWithoutARequestFollowsNone() {
        var core = SessionCore()

        push(&core, request: nil)

        #expect(core.followedMergeRequests.isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.isEmpty)
    }

    @Test func twoSessionsOnOneBranchYieldOne() {
        var core = SessionCore()

        push(&core, "s")
        push(&core, "other", commit: "def")

        #expect(core.snapshot(at: later).mergeRequests.map(\.number) == [12])
    }

    @Test func theSameNumberInAnotherRepositoryIsAnotherMergeRequest() {
        var core = SessionCore()
        let backoffice = GitRemote(host: "gitlab.com", path: "group/backoffice")

        push(&core, "s")
        push(&core, "other", to: backoffice, request: RequestLink(number: 12, url: "https://gitlab.com/group/backoffice/-/merge_requests/12"))

        #expect(core.snapshot(at: later).mergeRequests.map(\.project) == ["backoffice", "frontoffice"])
    }

    @Test(arguments: ["merged", "closed"])
    func aRequestThatIsNoLongerOpenIsNotTakenUp(state: String) {
        var core = SessionCore()

        push(&core, request: RequestLink(number: 12, url: requestURL, state: state))

        #expect(core.followedMergeRequests.isEmpty)
    }

    @Test func aPullRequestOnGitHubIsNotFollowedYet() {
        var core = SessionCore()
        let gitHub = GitRemote(host: "github.com", path: "me/notch")

        push(&core, to: gitHub, request: RequestLink(number: 5, url: "https://github.com/me/notch/pull/5", state: "open"))

        #expect(core.followedMergeRequests.isEmpty)
        #expect(core.snapshot(at: t + 60).sessions.first?.ci?.request?.number == 5)
    }
}

@Suite struct TheStateOfAMergeRequest {
    @Test func itShowsThePipelineOfItsHeadCommit() {
        var core = followed()

        observe(&core, open(.found(Pipeline(state: .running(stage: "test"), url: pipelineURL))))

        let shown = core.snapshot(at: later).mergeRequests.first
        #expect(shown?.ci == .running(stage: "test"))
        #expect(shown?.pipelineURL == pipelineURL)
    }

    @Test func aFailedPipelineLinksToTheJobThatFailed() {
        var core = followed()

        observe(&core, open(.found(Pipeline(state: .failed, url: pipelineURL, failedJobURL: jobURL))))

        let shown = core.snapshot(at: later).mergeRequests.first
        #expect(shown?.ci == .failed)
        #expect(shown?.pipelineURL == jobURL)
    }

    @Test func withoutAPipelineItShowsNoCI() {
        var core = followed()
        observe(&core, open(.found(Pipeline(state: .passed, url: pipelineURL))))

        observe(&core, open(.noPipeline))

        let shown = core.snapshot(at: later).mergeRequests.first
        #expect(shown?.ci == nil)
        #expect(shown?.pipelineURL == nil)
    }

    @Test func aHostThatCannotBeAskedShowsAsNoAccessAndKeepsWhatWasKnown() {
        var core = followed()

        observe(&core, .noAccess)

        let shown = core.snapshot(at: later).mergeRequests.first
        #expect(shown?.ci == .noAccess(host: "gitlab.com"))
        #expect(shown?.title == "Add the funnel events")
    }

    @Test func anAnswerThatCannotBeReadIsUnknownNeverPassed() {
        var core = followed()
        observe(&core, open(.found(Pipeline(state: .passed, url: pipelineURL))))

        observe(&core, .unknown)

        #expect(core.snapshot(at: later).mergeRequests.first?.ci == .unknown)
    }

    @Test func itsTitleFollowsTheHost() {
        var core = followed()

        observe(&core, open(title: "Add the funnel events, with tests"))

        #expect(core.snapshot(at: later).mergeRequests.first?.title == "Add the funnel events, with tests")
    }
}

@Suite struct TheEndOfAMergeRequest {
    @Test(arguments: [MergeRequestStatus.State.merged, .closed])
    func oneThatWasMergedOrClosedLeaves(state: MergeRequestStatus.State) {
        var core = followed()

        observe(&core, .found(MergeRequestStatus(state: state, url: requestURL)))

        #expect(core.followedMergeRequests.isEmpty)
    }

    @Test func anOpenOneStaysHoweverLong() {
        var core = followed()

        observe(&core, open(), at: t + 30 * 86_400)

        #expect(core.snapshot(at: t + 30 * 86_400).mergeRequests.map(\.number) == [12])
    }

    @Test func theUserCanStopFollowingOne() {
        var core = followed()

        core.stopFollowing(id)

        #expect(core.snapshot(at: later).mergeRequests.isEmpty)
        // What the host says about it afterwards does not bring it back.
        observe(&core, open(), at: later)
        #expect(core.followedMergeRequests.isEmpty)
    }

    @Test func aSessionThatPushesToItAgainBringsItBack() {
        var core = followed()
        core.stopFollowing(id)

        push(&core, commit: "def", at: later)

        #expect(core.followedMergeRequests.map(\.number) == [12])
    }
}

@Suite struct AskingAboutMergeRequests {
    @Test func oneThatWasNeverAskedAboutIsAskedAtOnce() {
        var core = SessionCore()

        push(&core)

        #expect(core.mergeRequestsToAsk(at: t + 21) == [id])
    }

    @Test func oneThatOnlyWaitsIsAskedEveryFewMinutes() {
        let core = followed()

        #expect(core.mergeRequestsToAsk(at: t + 50).isEmpty)
        #expect(core.mergeRequestsToAsk(at: t + 30 + 239).isEmpty)
        #expect(core.mergeRequestsToAsk(at: t + 30 + 240) == [id])
    }

    @Test func oneWhosePipelineRunsIsAskedEveryTime() {
        var core = followed()

        observe(&core, open(.found(Pipeline(state: .running(stage: "build"), url: pipelineURL))), at: t + 40)

        #expect(core.mergeRequestsToAsk(at: t + 41) == [id])
    }

    @Test func oneWhoseHostCannotBeAskedIsNotAskedInAHurry() {
        var core = followed()

        observe(&core, .noAccess, at: t + 40)

        #expect(core.mergeRequestsToAsk(at: t + 60).isEmpty)
        #expect(core.mergeRequestsToAsk(at: t + 40 + 240) == [id])
    }

    @Test func aPushToItIsAReasonToAskAgain() {
        var core = followed()

        push(&core, commit: "def", at: t + 100)

        #expect(core.mergeRequestsToAsk(at: t + 121) == [id])
    }
}

@Suite struct MergeRequestsAcrossARestart {
    @Test func whatWasFollowedIsFollowedAgain() throws {
        let before = followed()
        let stored = try JSONEncoder().encode(before.followedMergeRequests)

        var after = SessionCore()
        after.restore(try JSONDecoder().decode([FollowedMergeRequest].self, from: stored))

        #expect(after.snapshot(at: later).mergeRequests == before.snapshot(at: later).mergeRequests)
    }

    @Test func howItStoodIsNotKeptButAskedAtOnce() throws {
        var before = followed()
        observe(&before, open(.found(Pipeline(state: .running(stage: "test"), url: pipelineURL))))
        let stored = try JSONEncoder().encode(before.followedMergeRequests)

        var after = SessionCore()
        after.restore(try JSONDecoder().decode([FollowedMergeRequest].self, from: stored))

        let shown = after.snapshot(at: later).mergeRequests.first
        #expect(shown?.title == "Add the funnel events")
        #expect(shown?.ci == nil)
        #expect(after.mergeRequestsToAsk(at: later) == [id])
    }

    @Test func oneThatIsFollowedAlreadyIsNotReplaced() {
        var core = followed()

        core.restore([FollowedMergeRequest(remote: remote, number: 12, url: requestURL, title: "An older title")])

        #expect(core.snapshot(at: later).mergeRequests.first?.title == "Add the funnel events")
    }
}
