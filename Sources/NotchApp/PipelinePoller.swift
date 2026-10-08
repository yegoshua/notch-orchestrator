import Foundation
import SessionCore

/// Looks at the repositories and git hosts of the pushes the session core follows. The session
/// core decides what to make of the answers.
///
/// Not safe for concurrent use: one `look` at a time.
final class PipelinePoller: @unchecked Sendable {
    /// Pushes whose request was looked up already. Once per push is enough: a request that is
    /// opened later comes with a push hook of its own.
    private var requested: Set<String> = []

    /// Reads the repository of every push that has not been read yet and asks the host about
    /// each push's pipeline. Blocks while the tools run, so not for the main thread.
    func look(at followed: [FollowedPush]) -> (pushes: [Push], observations: [PipelineObservation]) {
        var pushes: [Push] = []
        var observations: [PipelineObservation] = []
        for item in followed {
            var push = item.push
            if push == nil, let cwd = item.cwd, let read = Self.push(of: item.sessionID, in: cwd) {
                pushes.append(read)
                push = read
            }
            guard let push else { continue }
            let key = "\(push.sessionID) \(push.commit)"
            if item.push == nil { requested.remove(key) }
            let lookup = GitHost.pipeline(of: push, run: CommandLineTool.run)
            var request: RequestLink?
            if item.request == nil, lookup != .noAccess, requested.insert(key).inserted {
                request = GitHost.request(of: push, run: CommandLineTool.run)
            }
            observations.append(PipelineObservation(
                sessionID: push.sessionID, commit: push.commit, lookup: lookup, request: request))
        }
        let sessions = Set(followed.map(\.sessionID))
        requested = requested.filter { key in sessions.contains { key.hasPrefix($0 + " ") } }
        return (pushes, observations)
    }

    /// Asks the host about each of the merge requests. Blocks while the tools run.
    func look(at mergeRequests: [FollowedMergeRequest.ID]) -> [MergeRequestObservation] {
        mergeRequests.map { MergeRequestObservation(id: $0, lookup: GitHost.mergeRequest($0, run: CommandLineTool.run)) }
    }

    /// What is checked out in the repository at `cwd` and where its branch is pushed to. Nil when
    /// that is no repository, or one without a remote on a host.
    private static func push(of sessionID: String, in cwd: String) -> Push? {
        func git(_ arguments: String...) -> String? {
            guard let answer = CommandLineTool.run("git", ["-C", cwd] + arguments), answer.exitStatus == 0 else { return nil }
            let line = answer.output.trimmingCharacters(in: .whitespacesAndNewlines)
            return line.isEmpty ? nil : line
        }
        guard let commit = git("rev-parse", "HEAD") else { return nil }
        let branch = git("symbolic-ref", "--quiet", "--short", "HEAD")
        let name = branch.flatMap { git("config", "branch.\($0).pushRemote") ?? git("config", "branch.\($0).remote") } ?? "origin"
        guard let remote = git("remote", "get-url", "--push", name).flatMap(GitRemote.init(url:)) else { return nil }
        return Push(sessionID: sessionID, commit: commit, branch: branch, remote: remote)
    }
}

/// Runs git and the git hosts' command line tools the way a terminal would find them. An app
/// started from the Finder has a bare `PATH`, so the usual places are searched as well.
enum CommandLineTool {
    private static let timeout: TimeInterval = 20

    private static let searchPath: [String] = {
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let usual = ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "/usr/bin", "/bin"]
        return inherited + usual.filter { !inherited.contains($0) }
    }()

    /// Nil when the tool is not installed or could not be started.
    static func run(_ tool: String, _ arguments: [String]) -> CLIAnswer? {
        guard let executable = searchPath.map({ "\($0)/\(tool)" }).first(where: FileManager.default.isExecutableFile(atPath:))
        else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        // The tools call git and each other.
        environment["PATH"] = searchPath.joined(separator: ":")
        // Nobody is there to answer a question.
        environment["GIT_TERMINAL_PROMPT"] = "0"
        environment["GH_PROMPT_DISABLED"] = "1"
        environment["NO_COLOR"] = "1"
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        // Into files rather than pipes: a helper the tool leaves behind would keep a pipe open
        // and the read of it waiting, long after the tool itself was stopped.
        let files = FileManager.default
        let output = files.temporaryDirectory.appendingPathComponent("notch-\(UUID().uuidString).out")
        let errorOutput = output.appendingPathExtension("err")
        defer {
            try? files.removeItem(at: output)
            try? files.removeItem(at: errorOutput)
        }
        guard files.createFile(atPath: output.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              files.createFile(atPath: errorOutput.path, contents: nil, attributes: [.posixPermissions: 0o600]),
              let printed = try? FileHandle(forWritingTo: output), let errors = try? FileHandle(forWritingTo: errorOutput)
        else { return nil }
        defer {
            try? printed.close()
            try? errors.close()
        }
        process.standardOutput = printed
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return nil
        }
        // A host that does not answer must not hold up the others for long.
        let deadline = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: deadline)
        process.waitUntilExit()
        deadline.cancel()
        func text(_ file: URL) -> String { (try? Data(contentsOf: file)).map { String(decoding: $0, as: UTF8.self) } ?? "" }
        return CLIAnswer(exitStatus: process.terminationStatus, output: text(output), errorOutput: text(errorOutput))
    }
}
