import Foundation
import Testing
import SessionCore

private let t = Date(timeIntervalSince1970: 1_000)
private let remote = GitRemote(host: "gitlab.com", path: "group/frontoffice")
private let requestURL = "https://gitlab.com/group/frontoffice/-/merge_requests/12"
private let pipelineURL = "https://gitlab.com/group/frontoffice/-/pipelines/9"
private let jobURL = "https://gitlab.com/group/frontoffice/-/jobs/90"
private let id = FollowedMergeRequest.ID(remote: remote, number: 12)
/// When the host says it was merged, and when the core first hears of it.
private let mergedAt = t + 100
private let heard = t + 120

private let running = PipelineLookup.found(Pipeline(state: .running(stage: "deploy-stage"), url: pipelineURL))
private let passed = PipelineLookup.found(Pipeline(state: .passed, url: pipelineURL))
private let failed = PipelineLookup.found(Pipeline(state: .failed, url: pipelineURL, failedJobURL: jobURL))
private let held = PipelineLookup.found(Pipeline(state: .held, url: pipelineURL))

private func event(_ name: String, tool: HookEvent.Tool? = nil) -> HookEvent {
    HookEvent(name: name, sessionID: "s", cwd: "/work/frontoffice", tool: tool)
}

/// A session pushed to merge request 12, which the host has told of once, open.
private func followed(_ settings: Settings = Settings()) -> SessionCore {
    var core = SessionCore(settings: settings)
    let bash = HookEvent.Tool(name: "Bash", subject: "git push", input: ["command": .string("git push")])
    core.handle(event("UserPromptSubmit"), at: t)
    core.handle(event("PreToolUse", tool: bash), at: t)
    core.handle(event("PostToolUse", tool: bash), at: t)
    core.handle(event("Stop"), at: t)
    core.handle(Push(sessionID: "s", commit: "abc", branch: "feature", remote: remote), readAt: t + 1)
    core.reconcile(
        PipelineObservation(
            sessionID: "s", commit: "abc", lookup: .found(Pipeline(state: .passed, url: pipelineURL)),
            request: RequestLink(number: 12, url: requestURL, branch: "feature", state: "opened")),
        observedAt: t + 20)
    core.reconcile(
        MergeRequestObservation(id: id, lookup: .found(MergeRequestStatus(
            state: .open, title: "Add the funnel events", url: requestURL, branch: "feature",
            approvals: Approvals(given: 2, required: 2), isMergeable: true))),
        observedAt: t + 30)
    _ = core.drainInterruptions()
    return core
}

private func merged(_ pipeline: PipelineLookup = .noPipeline, _ deployments: [Deployment]? = []) -> MergeRequestLookup {
    .found(MergeRequestStatus(
        state: .merged, title: "Add the funnel events", url: requestURL, branch: "feature", pipeline: pipeline,
        mergedAt: mergedAt, deployments: deployments))
}

private func observe(_ core: inout SessionCore, _ lookup: MergeRequestLookup, at time: Date = heard) {
    core.reconcile(MergeRequestObservation(id: id, lookup: lookup), observedAt: time)
}

private func shown(_ core: SessionCore, at time: Date = heard + 1) -> FollowedMergeRequest? {
    core.snapshot(at: time).mergeRequests.first
}

private func lines(_ core: inout SessionCore) -> [TransientLine.Kind] {
    core.drainInterruptions().compactMap { interruption in
        if case .line(let line, _) = interruption { return line.kind }
        return nil
    }
}

private func deployed(_ environment: String, _ state: Deployment.State) -> Deployment {
    Deployment(environment: environment, state: state)
}

@Suite struct AMergedRequest {
    @Test func itStaysAndShowsThePipelineOfTheCommitItWasMergedAs() {
        var core = followed()

        observe(&core, merged(running))

        let request = shown(core)
        #expect(request?.mergedAt == mergedAt)
        #expect(request?.ci == .running(stage: "deploy-stage"))
        #expect(request?.pipelineURL == pipelineURL)
    }

    @Test func itIsInTheSectionEvenWhileItsSessionIsInTheList() {
        // The row of the session shows what the session pushed, not what the merge set off.
        var core = followed()

        observe(&core, merged(running))

        let snapshot = core.snapshot(at: heard + 1)
        #expect(snapshot.sessions.map(\.id) == ["s"])
        #expect(snapshot.mergeRequests.map(\.number) == [12])
    }

    @Test func whatWasKnownOfItsReviewIsNoLongerShown() {
        var core = followed()

        observe(&core, merged(running))

        #expect(shown(core)?.approvals == nil)
        #expect(shown(core)?.isReadyToMerge == false)
        #expect(core.snapshot(at: heard + 1).sessions.first?.ci?.isReadyToMerge == false)
    }

    @Test func untilItsPipelineAppearsItIsPending() {
        var core = followed()

        observe(&core, merged(.noPipeline))

        #expect(shown(core)?.ci == .pending)
    }

    @Test func aFailedPipelineLinksToTheJobThatFailed() {
        var core = followed()

        observe(&core, merged(failed))

        #expect(shown(core)?.ci == .failed)
        #expect(shown(core)?.pipelineURL == jobURL)
    }

    @Test func itShowsTheEnvironmentsTheCommitGoesTo() {
        var core = followed()

        observe(&core, merged(running, [deployed("staging", .succeeded), deployed("production", .running)]))

        #expect(shown(core)?.deployments == [deployed("staging", .succeeded), deployed("production", .running)])
    }

    @Test func withoutDeploymentsItShowsThePipelineAlone() {
        var core = followed()

        observe(&core, merged(passed))

        #expect(shown(core)?.ci == .passed)
        #expect(shown(core)?.deployments == [])
    }

    @Test func aPipelineHeldAtAManualStepShowsAsHeldAndThenAsWhatFollows() {
        var core = followed()

        observe(&core, merged(held, [deployed("production", .waiting)]))
        #expect(shown(core)?.ci == .held)

        observe(&core, merged(running, [deployed("production", .running)]), at: heard + 300)
        #expect(shown(core, at: heard + 301)?.ci == .running(stage: "deploy-stage"))
        #expect(shown(core, at: heard + 301)?.deployments == [deployed("production", .running)])
    }

    @Test func aHostThatCannotBeAskedShowsAsNoAccess() {
        var core = followed()
        observe(&core, merged(running))

        observe(&core, .noAccess, at: heard + 20)

        #expect(shown(core, at: heard + 21)?.ci == .noAccess(host: "gitlab.com"))
        #expect(shown(core, at: heard + 21)?.mergedAt == mergedAt)
    }
}

@Suite struct LinesAfterTheMerge {
    private func line(_ kind: TransientLine.Kind) -> TransientLine {
        TransientLine(sessionID: nil, title: "!12 Add the funnel events", project: "frontoffice", kind: kind)
    }

    @Test func aPipelineThatFailedIsAnnouncedOnce() {
        var core = followed()

        observe(&core, merged(failed))
        #expect(core.drainInterruptions() == [.line(line(.failedAfterMerge(environment: nil)), sound: false)])

        observe(&core, merged(failed), at: heard + 300)
        #expect(lines(&core).isEmpty)
    }

    @Test func oneThatWasRunAgainAndFailedAgainIsAnnouncedAgain() {
        var core = followed()
        observe(&core, merged(failed))
        _ = core.drainInterruptions()

        observe(&core, merged(running), at: heard + 300)
        observe(&core, merged(failed), at: heard + 600)

        #expect(lines(&core) == [.failedAfterMerge(environment: nil)])
    }

    @Test func aDeploymentThatFailedIsAnnouncedByItsEnvironment() {
        var core = followed()

        observe(&core, merged(running, [deployed("staging", .succeeded), deployed("production", .failed)]))

        #expect(lines(&core) == [.failedAfterMerge(environment: "production")])
    }

    @Test func thePipelineThatFailedWithItIsNotASecondLine() {
        var core = followed()

        observe(&core, merged(failed, [deployed("production", .failed)]))
        observe(&core, merged(failed, [deployed("production", .failed)]), at: heard + 300)

        #expect(lines(&core) == [.failedAfterMerge(environment: "production")])
    }

    @Test func eachEnvironmentThatFailedHasItsLine() {
        var core = followed()
        observe(&core, merged(running, [deployed("staging", .failed), deployed("production", .waiting)]))

        observe(&core, merged(running, [deployed("staging", .failed), deployed("production", .failed)]), at: heard + 20)

        #expect(lines(&core) == [.failedAfterMerge(environment: "staging"), .failedAfterMerge(environment: "production")])
    }

    @Test func anEnvironmentDeployedToAgainThatFailsAgainIsAnnouncedAgain() {
        var core = followed()
        observe(&core, merged(running, [deployed("production", .failed)]))
        observe(&core, merged(running, [deployed("production", .running)]), at: heard + 20)
        _ = core.drainInterruptions()

        observe(&core, merged(running, [deployed("production", .failed)]), at: heard + 40)

        #expect(lines(&core) == [.failedAfterMerge(environment: "production")])
    }

    @Test func aPipelineHeldAtAManualStepIsAnnouncedOncePerTimeItIsHeld() {
        var core = followed()

        observe(&core, merged(held))
        observe(&core, merged(held), at: heard + 300)
        #expect(lines(&core) == [.heldAtManualStep])

        // Started, and held again at the next step.
        observe(&core, merged(running), at: heard + 600)
        observe(&core, merged(held), at: heard + 900)
        #expect(lines(&core) == [.heldAtManualStep])
    }

    @Test func successIsQuiet() {
        var core = followed()

        observe(&core, merged(running, [deployed("staging", .running)]))
        observe(&core, merged(passed, [deployed("staging", .succeeded)]), at: heard + 20)

        #expect(lines(&core).isEmpty)
    }

    @Test func theMergeItselfIsNoNews() {
        var core = followed()

        observe(&core, merged(.noPipeline))

        #expect(lines(&core).isEmpty)
    }

    @Test func oneAnswerThatCannotBeReadDoesNotMakeItNewsAgain() {
        var core = followed()
        observe(&core, merged(failed))
        _ = core.drainInterruptions()

        observe(&core, .unknown, at: heard + 20)
        observe(&core, .noAccess, at: heard + 40)
        observe(&core, merged(failed), at: heard + 60)

        #expect(lines(&core).isEmpty)
    }

    @Test func deploymentsTheHostWouldNotTellStayAsLastKnownAndAreNotNewsAgain() {
        var core = followed()
        observe(&core, merged(running, [deployed("production", .failed)]))
        _ = core.drainInterruptions()

        observe(&core, merged(running, nil), at: heard + 20)
        #expect(shown(core, at: heard + 21)?.deployments == [deployed("production", .failed)])

        observe(&core, merged(running, [deployed("production", .failed)]), at: heard + 40)
        #expect(lines(&core).isEmpty)
    }

    @Test(arguments: [(InterruptionMode.smart, false), (.loud, true)])
    func theLinesAreSilentInSmartModeAndSoundInLoud(mode: InterruptionMode, sound: Bool) {
        var core = followed(Settings(interruptionMode: mode))

        observe(&core, merged(held, [deployed("staging", .failed)]))

        #expect(core.drainInterruptions() == [
            .line(line(.failedAfterMerge(environment: "staging")), sound: sound),
            .line(line(.heldAtManualStep), sound: sound),
        ])
    }

    @Test func inQuietModeAndUnderFocusThereIsNoLineAndNoneLater() {
        var focused = followed(Settings(interruptionMode: .loud))
        focused.attend(Attention(focusIsOn: true), at: t + 40)
        for var core in [followed(Settings(interruptionMode: .quiet)), focused] {
            observe(&core, merged(failed, [deployed("staging", .failed)]))
            observe(&core, merged(failed, [deployed("staging", .failed)]), at: heard + 300)

            #expect(lines(&core).isEmpty)
        }
    }

    @Test func afterARestartNothingIsAnnouncedAgain() throws {
        var before = followed()
        observe(&before, merged(held, [deployed("staging", .failed)]))
        observe(&before, merged(failed, [deployed("staging", .failed)]), at: heard + 20)
        let stored = try JSONEncoder().encode(before.followedMergeRequests)

        var after = SessionCore()
        after.restore(try JSONDecoder().decode([FollowedMergeRequest].self, from: stored))
        observe(&after, merged(failed, [deployed("staging", .failed)]), at: heard + 40)

        #expect(lines(&after).isEmpty)
        #expect(shown(after, at: heard + 41)?.mergedAt == mergedAt)
    }
}

@Suite struct TheEndOfAMergedRequest {
    @Test func itLeavesAWhileAfterItsPipelineAndDeploymentsEnded() {
        var core = followed()
        observe(&core, merged(running, [deployed("staging", .running)]))

        observe(&core, merged(passed, [deployed("staging", .succeeded)]), at: heard + 60)

        // Like a session whose turn ended: there to be seen for a while, then gone.
        #expect(shown(core, at: heard + 60 + 599)?.ci == .passed)
        #expect(shown(core, at: heard + 60 + 600) == nil)
    }

    @Test(arguments: [Deployment.State.running, .waiting])
    func itStaysWhileADeploymentHasNotEnded(state: Deployment.State) {
        var core = followed()

        observe(&core, merged(passed, [deployed("staging", .succeeded), deployed("production", state)]))

        #expect(shown(core, at: heard + 3_600)?.number == 12)
    }

    @Test func itStaysWhileItsPipelineIsHeld() {
        var core = followed()

        observe(&core, merged(held))

        #expect(shown(core, at: heard + 3_600)?.ci == .held)
    }

    @Test func oneThatWentOnAfterItSeemedOverStays() {
        var core = followed()
        observe(&core, merged(passed))

        observe(&core, merged(running), at: heard + 300)

        #expect(shown(core, at: heard + 3_600)?.number == 12)
    }

    @Test func aDayAfterTheMergeItLeavesWhateverItsState() {
        var core = followed()

        observe(&core, merged(held, [deployed("production", .waiting)]))

        #expect(shown(core, at: mergedAt + 86_399)?.number == 12)
        #expect(shown(core, at: mergedAt + 86_400) == nil)
    }

    @Test func oneThatLeftIsNotAskedAboutAndNotKept() {
        var core = followed()
        observe(&core, merged(held))

        observe(&core, merged(held), at: mergedAt + 86_400)

        #expect(core.followedMergeRequests.isEmpty)
        #expect(core.mergeRequestsToAsk(at: mergedAt + 90_000).isEmpty)
    }

    @Test func aMergeCommitWithoutAPipelineIsDroppedAfterTheUsualWait() {
        var core = followed()

        observe(&core, merged(.noPipeline))
        observe(&core, merged(.noPipeline), at: heard + 119)
        #expect(core.followedMergeRequests.map(\.number) == [12])

        observe(&core, merged(.noPipeline), at: heard + 120)
        #expect(core.followedMergeRequests.isEmpty)
    }

    @Test func deploymentsWithoutAPipelineAreShownAloneAndEndIt() {
        var core = followed()
        observe(&core, merged(.noPipeline, [deployed("production", .running)]))
        #expect(shown(core)?.ci == .pending)

        observe(&core, merged(.noPipeline, [deployed("production", .running)]), at: heard + 120)
        #expect(shown(core, at: heard + 121)?.ci == nil)
        #expect(shown(core, at: heard + 3_600)?.number == 12)

        observe(&core, merged(.noPipeline, [deployed("production", .succeeded)]), at: heard + 4_000)
        #expect(shown(core, at: heard + 4_000 + 600) == nil)
    }

    @Test func theDayCountsFromTheMergeAcrossARestart() throws {
        var before = followed()
        observe(&before, merged(held))
        let stored = try JSONEncoder().encode(before.followedMergeRequests)

        var after = SessionCore()
        after.restore(try JSONDecoder().decode([FollowedMergeRequest].self, from: stored))

        #expect(shown(after, at: mergedAt + 86_399)?.number == 12)
        #expect(shown(after, at: mergedAt + 86_400) == nil)
    }
}

@Suite struct AskingAboutAMergedRequest {
    @Test(arguments: [running, .noPipeline])
    func oneWhosePipelineRunsOrIsAwaitedIsAskedEveryTime(pipeline: PipelineLookup) {
        var core = followed()

        observe(&core, merged(pipeline))

        #expect(core.mergeRequestsToAsk(at: heard + 1) == [id])
    }

    @Test func oneWithADeploymentRunningIsAskedEveryTime() {
        var core = followed()

        observe(&core, merged(passed, [deployed("production", .running)]))

        #expect(core.mergeRequestsToAsk(at: heard + 1) == [id])
    }

    @Test func oneThatWaitsForAManualStepIsAskedEveryFewMinutes() {
        var core = followed()

        observe(&core, merged(held, [deployed("production", .waiting)]))

        #expect(core.mergeRequestsToAsk(at: heard + 239).isEmpty)
        #expect(core.mergeRequestsToAsk(at: heard + 240) == [id])
    }
}
