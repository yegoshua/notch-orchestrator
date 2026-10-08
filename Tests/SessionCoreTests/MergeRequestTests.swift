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

private func open(
    _ pipeline: PipelineLookup = .noPipeline, title: String = "Add the funnel events", approved given: Int? = nil,
    of required: Int = 2, mergeable: Bool? = nil
) -> MergeRequestLookup {
    .found(MergeRequestStatus(
        state: .open, title: title, url: requestURL, branch: "feature", pipeline: pipeline,
        approvals: given.map { Approvals(given: $0, required: required) }, isMergeable: mergeable))
}

private func lines(_ core: inout SessionCore) -> [TransientLine] {
    core.drainInterruptions().compactMap { interruption in
        if case .line(let line, _) = interruption { return line }
        return nil
    }
}

private let readyLine = TransientLine(
    sessionID: nil, title: "!12 Add the funnel events", project: "frontoffice", kind: .readyToMerge)

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

@Suite struct ApprovalsOfAMergeRequest {
    @Test func theRowCountsApprovalsGivenAndRequired() {
        var core = followed()

        observe(&core, open(approved: 1, mergeable: false))

        #expect(core.snapshot(at: later).mergeRequests.first?.approvals == Approvals(given: 1, required: 2))
    }

    @Test func theCountGoesDownWhenAnApprovalIsWithdrawn() {
        var core = followed()
        observe(&core, open(approved: 2, mergeable: false))

        observe(&core, open(approved: 1, mergeable: false), at: t + 300)

        #expect(core.snapshot(at: later).mergeRequests.first?.approvals == Approvals(given: 1, required: 2))
    }

    @Test func approvalsTheHostWouldNotTellStayAsLastKnown() {
        var core = followed()
        observe(&core, open(approved: 1, mergeable: false))

        observe(&core, open(mergeable: false), at: t + 300)

        #expect(core.snapshot(at: later).mergeRequests.first?.approvals == Approvals(given: 1, required: 2))
    }

    @Test func theSessionsRowShowsThemWhileTheSessionIsInTheList() {
        var core = followed()

        observe(&core, open(approved: 2, mergeable: true))

        let ci = core.snapshot(at: t + 60).sessions.first?.ci
        #expect(ci?.approvals == Approvals(given: 2, required: 2))
        #expect(ci?.isReadyToMerge == true)
    }
}

@Suite struct ReadyToMerge {
    @Test func aMergeableRequestSomebodyApprovedIsAnnouncedOnce() {
        var core = followed()
        _ = core.drainInterruptions()

        observe(&core, open(approved: 2, mergeable: true))
        #expect(lines(&core) == [readyLine])
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == true)

        observe(&core, open(approved: 2, mergeable: true), at: t + 300)
        #expect(lines(&core).isEmpty)
    }

    @Test func withoutAnApprovalAMergeableRequestIsNotReady() {
        var core = followed()
        _ = core.drainInterruptions()

        // A project that asks for no approvals: mergeable as soon as its CI passed.
        observe(&core, open(approved: 0, of: 0, mergeable: true))

        #expect(lines(&core).isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)
    }

    @Test func onceSomebodyApprovedItIs() {
        var core = followed()
        observe(&core, open(approved: 0, of: 0, mergeable: true))
        _ = core.drainInterruptions()

        observe(&core, open(approved: 1, of: 0, mergeable: true), at: t + 300)

        #expect(lines(&core) == [readyLine])
    }

    @Test func approvedButNotMergeableIsNotReady() {
        var core = followed()
        _ = core.drainInterruptions()

        // Its CI fails, a thread is open, it has conflicts: the host says no.
        observe(&core, open(approved: 2, mergeable: false))

        #expect(lines(&core).isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)
    }

    @Test func aRequestThatStoppedBeingReadyAndIsReadyAgainIsAnnouncedAgain() {
        var core = followed()
        observe(&core, open(approved: 2, mergeable: true))
        _ = core.drainInterruptions()

        observe(&core, open(approved: 2, mergeable: false), at: t + 300)
        #expect(lines(&core).isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)

        observe(&core, open(approved: 2, mergeable: true), at: t + 600)
        #expect(lines(&core) == [readyLine])
    }

    @Test func aMergeabilityThatCannotBeReadIsNeverReady() {
        var core = followed()
        _ = core.drainInterruptions()

        observe(&core, open(approved: 2, mergeable: nil))

        #expect(lines(&core).isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)
    }

    @Test func aRequestThatWasReadyIsNotShownReadyOnAnAnswerThatCannotBeRead() {
        for answer in [MergeRequestLookup.unknown, .noAccess, open(approved: 2, mergeable: nil)] {
            var core = followed()
            observe(&core, open(approved: 2, mergeable: true))

            observe(&core, answer, at: t + 300)

            #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)
        }
    }

    @Test func approvalsTheHostWouldNotTellMakeNothingReady() {
        var core = followed()
        observe(&core, open(approved: 1, of: 0, mergeable: false))
        _ = core.drainInterruptions()

        // The one approval may have been withdrawn since: the count shown is the last known.
        observe(&core, open(mergeable: true), at: t + 300)

        #expect(lines(&core).isEmpty)
        #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == false)
    }

    @Test func oneAnswerThatCannotBeReadDoesNotMakeItNewsAgain() {
        var core = followed()
        observe(&core, open(approved: 2, mergeable: true))
        _ = core.drainInterruptions()

        observe(&core, .unknown, at: t + 300)
        observe(&core, open(approved: 2, mergeable: nil), at: t + 600)
        observe(&core, open(approved: 2, mergeable: true), at: t + 900)

        #expect(lines(&core).isEmpty)
    }

    @Test func afterARestartItIsNotAnnouncedAgain() throws {
        var before = followed()
        observe(&before, open(approved: 2, mergeable: true))
        let stored = try JSONEncoder().encode(before.followedMergeRequests)

        var after = SessionCore()
        after.restore(try JSONDecoder().decode([FollowedMergeRequest].self, from: stored))
        observe(&after, open(approved: 2, mergeable: true), at: later)

        #expect(lines(&after).isEmpty)
        #expect(after.snapshot(at: later).mergeRequests.first?.isReadyToMerge == true)
    }

    @Test func aFileFromBeforeReadinessWasFollowedIsStillRead() throws {
        let stored = Data("""
        [{"remote":{"host":"gitlab.com","path":"group/frontoffice"},"number":12,"url":"\(requestURL)"}]
        """.utf8)

        let read = try JSONDecoder().decode([FollowedMergeRequest].self, from: stored)

        #expect(read.map(\.number) == [12])
        #expect(read.first?.wasAnnouncedReady == false)
    }

    @Test func theLineIsSilentInSmartModeAndSoundsInLoud() {
        for (mode, sound) in [(InterruptionMode.smart, false), (.loud, true)] {
            var core = SessionCore(settings: Settings(interruptionMode: mode))
            push(&core)
            _ = core.drainInterruptions()

            observe(&core, open(approved: 2, mergeable: true))

            #expect(core.drainInterruptions() == [.line(readyLine, sound: sound)])
        }
    }

    @Test func inQuietModeAndUnderFocusThereIsNoLineAndNoneLater() {
        var quiet = SessionCore(settings: Settings(interruptionMode: .quiet))
        push(&quiet)
        var focused = SessionCore(settings: Settings(interruptionMode: .loud))
        push(&focused)
        focused.attend(Attention(focusIsOn: true), at: t + 25)
        for var core in [quiet, focused] {
            _ = core.drainInterruptions()

            observe(&core, open(approved: 2, mergeable: true))
            observe(&core, open(approved: 2, mergeable: true), at: t + 300)

            #expect(lines(&core).isEmpty)
            #expect(core.snapshot(at: later).mergeRequests.first?.isReadyToMerge == true)
        }
    }
}
