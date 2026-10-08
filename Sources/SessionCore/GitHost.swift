import Foundation

/// What a command line tool printed and how it ended.
public struct CLIAnswer: Equatable, Sendable {
    public var exitStatus: Int32
    public var output: String
    public var errorOutput: String

    public init(exitStatus: Int32, output: String, errorOutput: String = "") {
        self.exitStatus = exitStatus
        self.output = output
        self.errorOutput = errorOutput
    }

    fileprivate var json: Any? {
        try? JSONSerialization.jsonObject(with: Data(output.utf8))
    }
}

/// Asks a git host about a push through the provider's own command line tool, which carries the
/// user's sign-in: no token ever passes through here. Only the reading of the answers is decided
/// here; running the tool is the caller's.
public enum GitHost {
    /// Runs a tool with arguments and waits for it. Nil when the tool is not installed.
    public typealias Run = (_ tool: String, _ arguments: [String]) -> CLIAnswer?

    /// The pipeline of the pushed commit.
    public static func pipeline(of push: Push, run: Run) -> PipelineLookup {
        switch push.remote.provider {
        case .gitLab: gitLabPipeline(of: push, run: run)
        case .gitHub: gitHubChecks(of: push, run: run)
        }
    }

    /// The pull or merge request of the pushed branch. Having none, or not finding out, is no error.
    public static func request(of push: Push, run: Run) -> RequestLink? {
        guard let branch = push.branch else { return nil }
        let remote = push.remote
        switch remote.provider {
        case .gitLab:
            let path = "projects/\(escaped(remote.path))/merge_requests?source_branch=\(escaped(branch))&order_by=updated_at&per_page=1"
            guard let found = (ask(remote, path, run)?.json as? [[String: Any]])?.first,
                  let number = found["iid"] as? Int, let url = found["web_url"] as? String
            else { return nil }
            return RequestLink(number: number, url: url, branch: branch, state: found["state"] as? String)
        case .gitHub:
            let owner = remote.path.split(separator: "/").first.map(String.init) ?? ""
            let path = "repos/\(repository(remote))/pulls?head=\(escaped(owner)):\(escaped(branch))&state=all&per_page=1"
            guard let found = (ask(remote, path, run)?.json as? [[String: Any]])?.first,
                  let number = found["number"] as? Int, let url = found["html_url"] as? String
            else { return nil }
            return RequestLink(number: number, url: url, branch: branch, state: found["state"] as? String)
        }
    }

    /// The answer to an API call, when the call went through.
    private static func ask(_ remote: GitRemote, _ path: String, _ run: Run) -> CLIAnswer? {
        let answer = call(remote, path, run)
        return answer?.exitStatus == 0 ? answer : nil
    }

    /// A read of the host's API. Nil when the tool is not installed.
    private static func call(_ remote: GitRemote, _ path: String, _ run: Run) -> CLIAnswer? {
        run(remote.provider.tool, ["api", "--hostname", remote.host, path])
    }

    private static func escaped(_ text: String) -> String {
        let plain = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return text.addingPercentEncoding(withAllowedCharacters: plain) ?? text
    }

    /// `owner/name` as a path of the GitHub API.
    private static func repository(_ remote: GitRemote) -> String {
        remote.path.split(separator: "/").map { escaped(String($0)) }.joined(separator: "/")
    }

    // MARK: GitLab

    private static func gitLabPipeline(of push: Push, run: Run) -> PipelineLookup {
        let remote = push.remote
        let project = "projects/\(escaped(remote.path))"
        guard let answer = ask(remote, "\(project)/pipelines?sha=\(escaped(push.commit))&per_page=20", run)
        // Whatever kept the host from answering, a missing sign-in included: without one GitLab
        // answers for a private project as if it were not there.
        else { return .noAccess }
        guard let pipelines = answer.json as? [[String: Any]] else { return .unknown }
        // Newest first. A merge request may have a pipeline of its own for the same commit.
        guard let found = pipelines.first(where: { $0["ref"] as? String == push.branch }) ?? pipelines.first
        else { return .noPipeline }
        return gitLabPipeline(found, on: remote, run: run)
    }

    /// Reads a pipeline as GitLab lists it, asking for its jobs where the state takes them.
    private static func gitLabPipeline(_ found: [String: Any], on remote: GitRemote, run: Run) -> PipelineLookup {
        let project = "projects/\(escaped(remote.path))"
        guard let id = found["id"] as? Int, let status = found["status"] as? String else { return .unknown }
        var pipeline = Pipeline(state: .unknown, url: found["web_url"] as? String)
        func jobs() -> [[String: Any]] {
            // Newest first, which is the last stage first.
            ((ask(remote, "\(project)/pipelines/\(id)/jobs?per_page=100", run)?.json as? [[String: Any]]) ?? []).reversed()
        }
        func isRequired(_ job: [String: Any]) -> Bool { job["allow_failure"] as? Bool != true }
        func has(_ status: String) -> ([String: Any]) -> Bool { { $0["status"] as? String == status } }
        switch status {
        case "success":
            pipeline.state = .passed
        case "failed":
            let failed = jobs().filter(has("failed"))
            pipeline.state = .failed
            pipeline.failedJobURL = (failed.first(where: isRequired) ?? failed.first)?["web_url"] as? String
        case "created", "waiting_for_resource", "preparing", "pending", "running", "scheduled":
            let jobs = jobs()
            let current = jobs.first(where: has("running")) ?? jobs.first(where: has("pending")) ?? jobs.first(where: has("created"))
            pipeline.state = .running(stage: current?["stage"] as? String)
        case "manual":
            // Held at a step somebody has to start by hand, typically the production deploy.
            // That counts as passed only when what ran before it is seen to have succeeded.
            let jobs = jobs()
            let before = jobs.prefix { !has("manual")($0) }
            let succeeded = before.contains(where: has("success")) && !jobs.filter(isRequired).contains(where: has("failed"))
            pipeline.state = succeeded ? .passed : .unknown
        default:
            break
        }
        return .found(pipeline)
    }

    /// How a followed merge request stands, with the pipeline of its head commit while it is open.
    public static func mergeRequest(_ id: FollowedMergeRequest.ID, run: Run) -> MergeRequestLookup {
        let remote = id.remote
        // Pull requests are not followed beyond their session yet.
        guard remote.provider == .gitLab else { return .unknown }
        guard let answer = ask(remote, "projects/\(escaped(remote.path))/merge_requests/\(id.number)", run)
        else { return .noAccess }
        guard let found = answer.json as? [String: Any], let url = found["web_url"] as? String else { return .unknown }
        let state: MergeRequestStatus.State
        switch found["state"] as? String {
        // Locked is what it is for the moment it takes to merge.
        case "opened", "locked": state = .open
        case "merged": state = .merged
        case "closed": state = .closed
        default: return .unknown
        }
        var status = MergeRequestStatus(
            state: state, title: found["title"] as? String, url: url, branch: found["source_branch"] as? String)
        guard state == .open else { return .found(status) }
        if let head = found["head_pipeline"] as? [String: Any] {
            status.pipeline = gitLabPipeline(head, on: remote, run: run)
        }
        // The project's rules are the host's to apply: only its verdict is read.
        // While it is still working that out, it has not said.
        let undecided: Set = ["checking", "unchecked", "preparing", "approvals_syncing"]
        status.isMergeable = (found["detailed_merge_status"] as? String)
            .flatMap { undecided.contains($0) ? nil : $0 == "mergeable" }
        if let approvals = ask(remote, "projects/\(escaped(remote.path))/merge_requests/\(id.number)/approvals", run)?.json as? [String: Any],
           let given = approvals["approved_by"] as? [Any] {
            status.approvals = Approvals(given: given.count, required: approvals["approvals_required"] as? Int ?? 0)
        }
        return .found(status)
    }

    // MARK: GitHub

    private static let failures: Set = ["failure", "timed_out", "startup_failure", "action_required"]
    private static let successes: Set = ["success", "neutral", "skipped"]

    private static func gitHubChecks(of push: Push, run: Run) -> PipelineLookup {
        let remote = push.remote
        guard let answer = call(remote, "repos/\(repository(remote))/commits/\(escaped(push.commit))/check-runs?per_page=100", run)
        else { return .noAccess }
        guard answer.exitStatus == 0 else {
            // The push may not have arrived yet; anything else kept the host from answering.
            let status = (answer.json as? [String: Any])?["status"] as? String
            return status == "422" ? .noPipeline : .noAccess
        }
        guard let runs = (answer.json as? [String: Any])?["check_runs"] as? [[String: Any]] else { return .unknown }
        if runs.isEmpty { return .noPipeline }
        var pipeline = Pipeline(state: .unknown, url: "https://\(remote.host)/\(remote.path)/commit/\(push.commit)/checks")
        func conclusion(_ run: [String: Any]) -> String { run["conclusion"] as? String ?? "" }
        let unfinished = runs.filter { $0["status"] as? String != "completed" }
        if let failed = runs.first(where: { failures.contains(conclusion($0)) }) {
            // One failed check fails the commit, whatever the others still do.
            pipeline.state = .failed
            pipeline.failedJobURL = failed["html_url"] as? String
        } else if !unfinished.isEmpty {
            let current = unfinished.first { $0["status"] as? String == "in_progress" } ?? unfinished.first
            pipeline.state = .running(stage: current?["name"] as? String)
        } else if runs.allSatisfy({ successes.contains(conclusion($0)) }), runs.contains(where: { conclusion($0) == "success" }) {
            pipeline.state = .passed
        }
        return .found(pipeline)
    }
}
