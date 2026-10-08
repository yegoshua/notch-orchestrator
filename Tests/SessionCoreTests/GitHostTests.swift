import Foundation
import Testing
import SessionCore

/// Stands in for the command line tools: answers a call by the first key its last argument
/// contains, and remembers what was asked. The answers are cut down from what `glab` 1.113 and
/// `gh` 2.96 printed on 2026-10-07.
private final class Recorded {
    var answers: [(key: String, answer: CLIAnswer)]
    var isInstalled = true
    private(set) var calls: [[String]] = []

    init(_ answers: KeyValuePairs<String, CLIAnswer>) {
        self.answers = answers.map { ($0.key, $0.value) }
    }

    func run(_ tool: String, _ arguments: [String]) -> CLIAnswer? {
        calls.append([tool] + arguments)
        guard isInstalled else { return nil }
        return answers.first { arguments.last?.contains($0.key) == true }?.answer
            ?? CLIAnswer(exitStatus: 1, output: "", errorOutput: "unexpected call")
    }
}

private func ok(_ output: String) -> CLIAnswer { CLIAnswer(exitStatus: 0, output: output) }

private func refused(_ output: String, _ error: String) -> CLIAnswer {
    CLIAnswer(exitStatus: 1, output: output, errorOutput: error)
}

private let gitLabPush = Push(
    sessionID: "s", commit: "8fe791d2", branch: "main", remote: GitRemote(host: "gitlab.com", path: "group/apps/frontoffice"))
private let gitHubPush = Push(
    sessionID: "s", commit: "c01727ee", branch: "feature", remote: GitRemote(host: "github.com", path: "me/notch"))

private func gitLabPipelines(_ status: String, ref: String = "main") -> String {
    """
    [{"id":2923343714,"iid":831,"project_id":80556934,"sha":"8fe791d2","ref":"\(ref)","status":"\(status)",\
    "source":"push","created_at":"2026-10-07T17:03:25.492Z","updated_at":"2026-10-07T17:16:07.279Z",\
    "web_url":"https://gitlab.com/group/apps/frontoffice/-/pipelines/2923343714","name":null}]
    """
}

/// Jobs come newest first, which is last stage first.
private func gitLabJobs(_ jobs: [(name: String, stage: String, status: String, allowFailure: Bool)]) -> String {
    let objects = jobs.enumerated().map { index, job in
        """
        {"id":\(900 - index),"name":"\(job.name)","stage":"\(job.stage)","status":"\(job.status)",\
        "allow_failure":\(job.allowFailure),"web_url":"https://gitlab.com/group/apps/frontoffice/-/jobs/\(900 - index)"}
        """
    }
    return "[" + objects.joined(separator: ",") + "]"
}

private let gitLabPipelineURL = "https://gitlab.com/group/apps/frontoffice/-/pipelines/2923343714"

private func checkRuns(_ runs: [(name: String, status: String, conclusion: String?)]) -> String {
    let objects = runs.enumerated().map { index, run in
        """
        {"id":\(index + 1),"name":"\(run.name)","status":"\(run.status)",\
        "conclusion":\(run.conclusion.map { "\"\($0)\"" } ?? "null"),\
        "html_url":"https://github.com/me/notch/actions/runs/5/job/\(index + 1)","app":{"slug":"github-actions"}}
        """
    }
    return "{\"total_count\":\(runs.count),\"check_runs\":[" + objects.joined(separator: ",") + "]}"
}

@Suite struct GitLabPipelines {
    @Test func aRunningPipelineIsInTheStageOfItsRunningJob() {
        let cli = Recorded([
            "/jobs": ok(gitLabJobs([
                ("deploy-stage", "deploy-stage", "created", false), ("unit", "test", "running", false),
                ("lint", "test", "success", false), ("compile", "build", "success", false),
            ])),
            "/pipelines?": ok(gitLabPipelines("running")),
        ])

        let lookup = GitHost.pipeline(of: gitLabPush, run: cli.run)

        #expect(lookup == .found(Pipeline(state: .running(stage: "test"), url: gitLabPipelineURL)))
    }

    @Test func theProjectOfTheRemoteIsAskedOnItsHostForTheCommit() {
        let cli = Recorded(["/jobs": ok("[]"), "/pipelines?": ok(gitLabPipelines("running"))])

        _ = GitHost.pipeline(of: gitLabPush, run: cli.run)

        #expect(cli.calls.first == [
            "glab", "api", "--hostname", "gitlab.com", "projects/group%2Fapps%2Ffrontoffice/pipelines?sha=8fe791d2&per_page=20",
        ])
        #expect(cli.calls.last?.last == "projects/group%2Fapps%2Ffrontoffice/pipelines/2923343714/jobs?per_page=100")
    }

    @Test func aPipelineWaitingToStartIsRunningInItsFirstStage() {
        let cli = Recorded([
            "/jobs": ok(gitLabJobs([("unit", "test", "created", false), ("compile", "build", "pending", false)])),
            "/pipelines?": ok(gitLabPipelines("pending")),
        ])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run)
            == .found(Pipeline(state: .running(stage: "build"), url: gitLabPipelineURL)))
    }

    @Test func aRunningPipelineWhoseJobsCannotBeReadHasNoStage() {
        let cli = Recorded(["/jobs": refused("", "glab: 500"), "/pipelines?": ok(gitLabPipelines("running"))])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run)
            == .found(Pipeline(state: .running(stage: nil), url: gitLabPipelineURL)))
    }

    @Test func aPipelineThatSucceededPassed() {
        let cli = Recorded(["/pipelines?": ok(gitLabPipelines("success"))])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .passed, url: gitLabPipelineURL)))
    }

    @Test func aFailedPipelineNamesTheJobThatFailedIt() {
        let cli = Recorded([
            "/jobs": ok(gitLabJobs([
                ("deploy", "deploy", "skipped", false), ("unit", "test", "failed", false),
                ("sonar", "build", "failed", true), ("compile", "build", "success", false),
            ])),
            "/pipelines?": ok(gitLabPipelines("failed")),
        ])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(
            state: .failed, url: gitLabPipelineURL,
            failedJobURL: "https://gitlab.com/group/apps/frontoffice/-/jobs/899")))
    }

    @Test func aPipelineHeldAtAManualStepAfterEverythingElseSucceededPassed() {
        // As recorded: the production deploy waits for a click, the rollbacks are optional.
        let cli = Recorded([
            "/jobs": ok(gitLabJobs([
                ("rollback-prod", "deploy-prod", "created", true), ("deploy-prod", "deploy-prod", "manual", false),
                ("rollback-stage", "deploy-stage", "manual", true), ("deploy-stage", "deploy-stage", "success", false),
                ("pack:docker-image", "pack", "success", false), ("sonar", "build", "success", true),
            ])),
            "/pipelines?": ok(gitLabPipelines("manual")),
        ])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .passed, url: gitLabPipelineURL)))
    }

    @Test func aPipelineHeldAtAManualStepBeforeAnythingRanIsUnknown() {
        let cli = Recorded([
            "/jobs": ok(gitLabJobs([("unit", "test", "created", false), ("approve", "gate", "manual", false)])),
            "/pipelines?": ok(gitLabPipelines("manual")),
        ])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .unknown, url: gitLabPipelineURL)))
    }

    @Test(arguments: ["canceled", "skipped", "something-new"])
    func aPipelineThatEndedSomeOtherWayIsUnknownNeverPassed(status: String) {
        let cli = Recorded(["/jobs": ok("[]"), "/pipelines?": ok(gitLabPipelines(status))])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .unknown, url: gitLabPipelineURL)))
    }

    @Test func aCommitWithoutPipelinesHasNone() {
        let cli = Recorded(["/pipelines?": ok("[]")])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .noPipeline)
    }

    @Test func amongThePipelinesOfTheCommitTheOneOfThePushedBranchIsTaken() {
        let pipelines = """
            [{"id":3,"sha":"8fe791d2","ref":"refs/merge-requests/12/head","status":"failed","web_url":"https://gitlab.com/p/3"},
             {"id":2,"sha":"8fe791d2","ref":"main","status":"success","web_url":"https://gitlab.com/p/2"},
             {"id":1,"sha":"8fe791d2","ref":"v1.0","status":"running","web_url":"https://gitlab.com/p/1"}]
            """
        let cli = Recorded(["/jobs": ok("[]"), "/pipelines?": ok(pipelines)])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .passed, url: "https://gitlab.com/p/2")))
    }

    @Test func withoutAPipelineOfTheBranchTheNewestOfTheCommitIsTaken() {
        let pipelines = """
            [{"id":3,"sha":"8fe791d2","ref":"refs/merge-requests/12/head","status":"success","web_url":"https://gitlab.com/p/3"},
             {"id":1,"sha":"8fe791d2","ref":"v1.0","status":"failed","web_url":"https://gitlab.com/p/1"}]
            """
        let cli = Recorded(["/pipelines?": ok(pipelines)])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .found(Pipeline(state: .passed, url: "https://gitlab.com/p/3")))
    }

    @Test func aProjectTheSignInDoesNotReachIsNoAccess() {
        // Without a sign-in GitLab answers for a private project as if it were not there.
        let cli = Recorded(["/pipelines?": refused(#"{"message":"404 Project Not Found"}"#, "glab: 404 Project Not Found (HTTP 404)")])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .noAccess)
    }

    @Test func aHostThatDoesNotAnswerIsNoAccess() {
        let error = #"ERROR  Get "https://git.example.com/api/v4/projects/a%2Fb/pipelines?sha=abc": dial tcp 10.0.0.1:443: i/o timeout."#
        let cli = Recorded(["/pipelines?": refused("", error)])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .noAccess)
    }

    @Test func aMissingToolIsNoAccess() {
        let cli = Recorded([:])
        cli.isInstalled = false

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .noAccess)
        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .noAccess)
    }

    @Test(arguments: ["<html>Sign in</html>", "", #"{"message":"ok"}"#, #"[{"id":"seven"}]"#])
    func anAnswerThatCannotBeReadIsUnknown(output: String) {
        let cli = Recorded(["/pipelines?": ok(output)])

        #expect(GitHost.pipeline(of: gitLabPush, run: cli.run) == .unknown)
    }
}

@Suite struct GitHubChecks {
    private let checksURL = "https://github.com/me/notch/commit/c01727ee/checks"

    @Test func checksStillRunningAreARunningPipelineInTheCheckThatRuns() {
        let cli = Recorded(["check-runs": ok(checkRuns([
            ("lint", "completed", "success"), ("test", "in_progress", nil), ("deploy", "queued", nil),
        ]))])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .found(Pipeline(state: .running(stage: "test"), url: checksURL)))
        #expect(cli.calls == [["gh", "api", "--hostname", "github.com", "repos/me/notch/commits/c01727ee/check-runs?per_page=100"]])
    }

    @Test func checksThatAllSucceededPassed() {
        let cli = Recorded(["check-runs": ok(checkRuns([
            ("lint", "completed", "success"), ("docs", "completed", "skipped"), ("test", "completed", "success"),
        ]))])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .found(Pipeline(state: .passed, url: checksURL)))
    }

    @Test func aFailedCheckFailsThePipelineAtOnceAndIsLinked() {
        let cli = Recorded(["check-runs": ok(checkRuns([
            ("lint", "completed", "success"), ("test", "completed", "failure"), ("deploy", "in_progress", nil),
        ]))])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .found(Pipeline(
            state: .failed, url: checksURL, failedJobURL: "https://github.com/me/notch/actions/runs/5/job/2")))
    }

    @Test func checksThatWereCancelledAreUnknownNeverPassed() {
        let cli = Recorded(["check-runs": ok(checkRuns([("lint", "completed", "success"), ("test", "completed", "cancelled")]))])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .found(Pipeline(state: .unknown, url: checksURL)))
    }

    @Test func aCommitWithoutChecksHasNoPipeline() {
        let cli = Recorded(["check-runs": ok(#"{"total_count":0,"check_runs":[]}"#)])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .noPipeline)
    }

    @Test func aCommitTheHostHasNotSeenYetHasNoPipeline() {
        let body = #"{"message":"No commit found for SHA: c01727ee","documentation_url":"https://docs.github.com/rest/checks/runs#list-check-runs-for-a-git-reference","status":"422"}"#
        let cli = Recorded(["check-runs": refused(body, "gh: No commit found for SHA: c01727ee (HTTP 422)")])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .noPipeline)
    }

    @Test func aRepositoryTheSignInDoesNotReachIsNoAccess() {
        let body = #"{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}"#
        let cli = Recorded(["check-runs": refused(body, "gh: Not Found (HTTP 404)")])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .noAccess)
    }

    @Test func notBeingSignedInIsNoAccess() {
        let error = "To get started with GitHub CLI, please run:  gh auth login\nAlternatively, populate the GH_TOKEN environment variable with a GitHub API authentication token."
        let cli = Recorded(["check-runs": CLIAnswer(exitStatus: 4, output: "", errorOutput: error)])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .noAccess)
    }

    @Test(arguments: ["not json", #"{"total_count":2}"#, #"["check_runs"]"#])
    func anAnswerThatCannotBeReadIsUnknown(output: String) {
        let cli = Recorded(["check-runs": ok(output)])

        #expect(GitHost.pipeline(of: gitHubPush, run: cli.run) == .unknown)
    }
}

@Suite struct RequestsOfABranch {
    @Test func theMergeRequestOfTheBranchIsFoundOnGitLab() {
        let requests = """
            [{"id":4410,"iid":12,"title":"Lock the bank","state":"opened","source_branch":"main",\
            "web_url":"https://gitlab.com/group/apps/frontoffice/-/merge_requests/12"}]
            """
        let cli = Recorded(["merge_requests": ok(requests)])

        let request = GitHost.request(of: gitLabPush, run: cli.run)

        #expect(request == RequestLink(
            number: 12, url: "https://gitlab.com/group/apps/frontoffice/-/merge_requests/12", branch: "main", state: "opened"))
        #expect(cli.calls == [[
            "glab", "api", "--hostname", "gitlab.com",
            "projects/group%2Fapps%2Ffrontoffice/merge_requests?source_branch=main&order_by=updated_at&per_page=1",
        ]])
    }

    @Test func thePullRequestOfTheBranchIsFoundOnGitHub() {
        let requests = #"[{"number":96,"state":"open","html_url":"https://github.com/me/notch/pull/96","head":{"ref":"feature"}}]"#
        let cli = Recorded(["pulls": ok(requests)])

        let request = GitHost.request(of: gitHubPush, run: cli.run)

        #expect(request == RequestLink(number: 96, url: "https://github.com/me/notch/pull/96", branch: "feature", state: "open"))
        #expect(cli.calls == [["gh", "api", "--hostname", "github.com", "repos/me/notch/pulls?head=me:feature&state=all&per_page=1"]])
    }

    @Test func aBranchWithoutARequestHasNone() {
        #expect(GitHost.request(of: gitLabPush, run: Recorded(["merge_requests": ok("[]")]).run) == nil)
        #expect(GitHost.request(of: gitHubPush, run: Recorded(["pulls": ok("[]")]).run) == nil)
    }

    @Test func aRequestThatCannotBeLookedUpIsNoError() {
        let cli = Recorded(["merge_requests": refused(#"{"message":"401 Unauthorized"}"#, "glab: 401 Unauthorized (HTTP 401)")])

        #expect(GitHost.request(of: gitLabPush, run: cli.run) == nil)
    }

    @Test func aPushWithoutABranchHasNoRequest() {
        var push = gitLabPush
        push.branch = nil
        let cli = Recorded([:])

        #expect(GitHost.request(of: push, run: cli.run) == nil)
        #expect(cli.calls.isEmpty)
    }

    @Test func aBranchNameIsEscapedForTheQuery() {
        var push = gitLabPush
        push.branch = "fix/HUB-1 & more"
        let cli = Recorded(["merge_requests": ok("[]")])

        _ = GitHost.request(of: push, run: cli.run)

        #expect(cli.calls.first?.last
            == "projects/group%2Fapps%2Ffrontoffice/merge_requests?source_branch=fix%2FHUB-1%20%26%20more&order_by=updated_at&per_page=1")
    }
}

private let followedRequest = FollowedMergeRequest.ID(remote: GitRemote(host: "gitlab.com", path: "group/apps/frontoffice"), number: 12)

/// A merge request as GitLab answers for one, cut down to what is read and a little around it.
private func gitLabMergeRequest(
    _ state: String = "opened", headPipeline: String? = "running", mergeStatus: String = "not_approved"
) -> String {
    let pipeline = headPipeline.map {
        """
        {"id":2923343714,"iid":831,"project_id":80556934,"sha":"8fe791d2","ref":"refs/merge-requests/12/head",\
        "status":"\($0)","source":"merge_request_event",\
        "web_url":"https://gitlab.com/group/apps/frontoffice/-/pipelines/2923343714"}
        """
    } ?? "null"
    return """
    {"id":4301,"iid":12,"project_id":80556934,"title":"Add the funnel events","state":"\(state)",\
    "target_branch":"main","source_branch":"feature","draft":false,"detailed_merge_status":"\(mergeStatus)",\
    "sha":"8fe791d2","merge_commit_sha":null,"squash_commit_sha":null,\
    "web_url":"https://gitlab.com/group/apps/frontoffice/-/merge_requests/12","head_pipeline":\(pipeline)}
    """
}

/// The approvals of a merge request as GitLab answers for them, cut down.
private func gitLabApprovals(by names: [String], required: Int) -> String {
    let approvers = names.map { "{\"user\":{\"id\":1,\"username\":\"\($0)\",\"name\":\"\($0)\"}}" }.joined(separator: ",")
    return """
    {"id":4301,"iid":12,"state":"opened","approved":\(names.count >= required),"approvals_required":\(required),\
    "approvals_left":\(max(0, required - names.count)),"approved_by":[\(approvers)]}
    """
}

@Suite struct GitLabApprovals {
    private func status(_ answers: KeyValuePairs<String, CLIAnswer>) -> MergeRequestStatus? {
        guard case .found(let status) = GitHost.mergeRequest(followedRequest, run: Recorded(answers).run) else { return nil }
        return status
    }

    @Test func approvalsGivenAndRequiredAreRead() {
        let read = status([
            "/approvals": ok(gitLabApprovals(by: ["olha"], required: 2)),
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil)),
        ])

        #expect(read?.approvals == Approvals(given: 1, required: 2))
        #expect(read?.isMergeable == false)
    }

    @Test func aProjectThatAsksForNoneRequiresNone() {
        let read = status([
            "/approvals": ok("{\"approved\":true,\"approved_by\":[]}"),
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil, mergeStatus: "mergeable")),
        ])

        #expect(read?.approvals == Approvals(given: 0, required: 0))
        #expect(read?.isMergeable == true)
    }

    @Test func onlyTheHostsOwnVerdictMakesItMergeable() {
        let read = status([
            "/approvals": ok(gitLabApprovals(by: ["olha", "taras"], required: 2)),
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil, mergeStatus: "mergeable")),
        ])

        #expect(read?.isMergeable == true)
    }

    @Test(arguments: [
        "not_approved", "ci_must_pass", "ci_still_running", "discussions_not_resolved", "conflict", "draft_status",
        "need_rebase", "requested_changes", "something_new",
    ])
    func whateverElseTheHostSaysIsNotMergeable(mergeStatus: String) {
        let read = status([
            "/approvals": ok(gitLabApprovals(by: ["olha", "taras"], required: 2)),
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil, mergeStatus: mergeStatus)),
        ])

        #expect(read?.isMergeable == false)
    }

    @Test(arguments: ["checking", "unchecked", "preparing", "approvals_syncing"])
    func aHostThatIsStillWorkingItOutHasNotSaid(mergeStatus: String) {
        let read = status([
            "/approvals": ok(gitLabApprovals(by: ["olha", "taras"], required: 2)),
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil, mergeStatus: mergeStatus)),
        ])

        #expect(read?.isMergeable == nil)
    }

    @Test func aMergeRequestThatDoesNotSayIsNeitherMergeableNorNot() {
        let read = status([
            "/approvals": ok(gitLabApprovals(by: ["olha"], required: 1)),
            "merge_requests/12": ok("{\"state\":\"opened\",\"web_url\":\"https://gitlab.com/group/apps/frontoffice/-/merge_requests/12\"}"),
        ])

        #expect(read?.isMergeable == nil)
    }

    @Test(arguments: [refused("", "glab: 403 Forbidden (HTTP 403)"), ok("[]"), ok("{\"approvals_required\":2}")])
    func approvalsThatCannotBeReadAreNotKnown(answer: CLIAnswer) {
        let read = status([
            "/approvals": answer,
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil, mergeStatus: "mergeable")),
        ])

        #expect(read?.approvals == nil)
        #expect(read?.isMergeable == true)
    }
}

@Suite struct GitLabMergeRequests {
    @Test func anOpenMergeRequestIsReadWithThePipelineOfItsHead() {
        let cli = Recorded([
            "/approvals": ok(gitLabApprovals(by: [], required: 2)),
            "merge_requests/12": ok(gitLabMergeRequest()),
            "/jobs": ok(gitLabJobs([("deploy", "deploy", "created", false), ("unit", "test", "running", false)])),
        ])

        #expect(GitHost.mergeRequest(followedRequest, run: cli.run) == .found(MergeRequestStatus(
            state: .open, title: "Add the funnel events", url: "https://gitlab.com/group/apps/frontoffice/-/merge_requests/12",
            branch: "feature", pipeline: .found(Pipeline(state: .running(stage: "test"), url: gitLabPipelineURL)),
            approvals: Approvals(given: 0, required: 2), isMergeable: false)))
    }

    @Test func itIsAskedForByItsNumberInTheProjectOnItsHost() {
        let cli = Recorded(["merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil))])

        _ = GitHost.mergeRequest(followedRequest, run: cli.run)

        #expect(cli.calls.first == ["glab", "api", "--hostname", "gitlab.com", "projects/group%2Fapps%2Ffrontoffice/merge_requests/12"])
    }

    @Test func thePipelineOfTheHeadIsTheOneTheMergeRequestNames() {
        let cli = Recorded([
            "merge_requests/12": ok(gitLabMergeRequest(headPipeline: "failed")),
            "/jobs": ok(gitLabJobs([("unit", "test", "failed", false)])),
        ])

        _ = GitHost.mergeRequest(followedRequest, run: cli.run)

        // Not looked for by commit: a pipeline of the merged result runs on another one.
        #expect(cli.calls.map(\.last) == [
            "projects/group%2Fapps%2Ffrontoffice/merge_requests/12",
            "projects/group%2Fapps%2Ffrontoffice/pipelines/2923343714/jobs?per_page=100",
            "projects/group%2Fapps%2Ffrontoffice/merge_requests/12/approvals",
        ])
    }

    @Test func oneWithoutAPipelineHasNone() {
        let cli = Recorded(["merge_requests/12": ok(gitLabMergeRequest(headPipeline: nil))])

        guard case .found(let status) = GitHost.mergeRequest(followedRequest, run: cli.run) else {
            Issue.record("not found")
            return
        }
        #expect(status.pipeline == .noPipeline)
    }

    @Test func oneThatIsBeingMergedIsStillOpen() {
        let cli = Recorded(["merge_requests/12": ok(gitLabMergeRequest("locked", headPipeline: nil))])

        guard case .found(let status) = GitHost.mergeRequest(followedRequest, run: cli.run) else {
            Issue.record("not found")
            return
        }
        #expect(status.state == .open)
    }

    @Test(arguments: [("merged", MergeRequestStatus.State.merged), ("closed", .closed)])
    func oneThatEndedIsReadWithoutItsPipeline(state: String, expected: MergeRequestStatus.State) {
        let cli = Recorded(["merge_requests/12": ok(gitLabMergeRequest(state, headPipeline: "success"))])

        #expect(GitHost.mergeRequest(followedRequest, run: cli.run) == .found(MergeRequestStatus(
            state: expected, title: "Add the funnel events",
            url: "https://gitlab.com/group/apps/frontoffice/-/merge_requests/12", branch: "feature")))
        #expect(cli.calls.count == 1)
    }

    @Test func aProjectTheSignInDoesNotReachIsNoAccess() {
        let cli = Recorded(["merge_requests/12": refused("{\"message\":\"404 Project Not Found\"}", "glab: 404 Project Not Found (HTTP 404)")])

        #expect(GitHost.mergeRequest(followedRequest, run: cli.run) == .noAccess)
    }

    @Test func aMissingToolIsNoAccess() {
        let cli = Recorded([:])
        cli.isInstalled = false

        #expect(GitHost.mergeRequest(followedRequest, run: cli.run) == .noAccess)
    }

    @Test(arguments: ["", "[]", "{\"iid\":12}", "{\"state\":\"draft\",\"web_url\":\"https://gitlab.com/x\"}"])
    func anAnswerThatCannotBeReadIsUnknown(output: String) {
        let cli = Recorded(["merge_requests/12": ok(output)])

        #expect(GitHost.mergeRequest(followedRequest, run: cli.run) == .unknown)
    }

    @Test func aPullRequestOnGitHubIsNotAskedAbout() {
        let cli = Recorded([:])

        #expect(GitHost.mergeRequest(FollowedMergeRequest.ID(remote: gitHubPush.remote, number: 5), run: cli.run) == .unknown)
        #expect(cli.calls.isEmpty)
    }
}

@Suite struct HostAccessChecks {
    @Test func aToolThatIsSignedInHasAccess() {
        let cli = Recorded(["gitlab.example.com": ok("")])

        #expect(GitHost.access(to: "gitlab.example.com", run: cli.run) == .signedIn)
        #expect(cli.calls == [["glab", "auth", "status", "--hostname", "gitlab.example.com"]])
    }

    @Test func aToolThatRefusesIsSignedOut() {
        let cli = Recorded(["gitlab.com": refused("", "No token found")])

        #expect(GitHost.access(to: "gitlab.com", run: cli.run) == .signedOut)
    }

    @Test func aMissingToolIsToldApart() {
        let cli = Recorded([:])
        cli.isInstalled = false

        #expect(GitHost.access(to: "gitlab.com", run: cli.run) == .noTool)
    }
}
