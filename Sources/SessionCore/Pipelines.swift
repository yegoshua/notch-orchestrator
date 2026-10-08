import Foundation

/// The software a git host runs, as far as the app can follow pipelines on it.
public enum GitProvider: Equatable, Sendable {
    case gitHub
    case gitLab

    /// Nothing on a host of one's own says which software it runs; it is far more often a GitLab.
    public init(host: String) {
        self = host.contains("github") ? .gitHub : .gitLab
    }

    /// The command line tool that speaks to the provider with the user's own sign-in.
    public var tool: String {
        switch self {
        case .gitHub: "gh"
        case .gitLab: "glab"
        }
    }

    /// What signs the user in to `host`, to be run by them in a terminal.
    public func signInCommand(host: String) -> String {
        "\(tool) auth login --hostname \(host)"
    }
}

/// Where a repository is pushed to.
public struct GitRemote: Hashable, Codable, Sendable {
    public var host: String
    /// The project on the host, `group/project`.
    public var path: String

    public init(host: String, path: String) {
        self.host = host
        self.path = path
    }

    /// Reads a remote URL in either form git takes: `git@host:group/project.git` or one with a
    /// scheme. Nil for a remote that is not on a host.
    public init?(url: String) {
        let url = url.trimmingCharacters(in: .whitespacesAndNewlines)
        var host: Substring
        var path: Substring
        if let scheme = url.range(of: "://") {
            let rest = url[scheme.upperBound...]
            guard let slash = rest.firstIndex(of: "/") else { return nil }
            host = rest[..<slash]
            path = rest[slash...]
        } else {
            guard let colon = url.firstIndex(of: ":"), !url[..<colon].contains("/") else { return nil }
            host = url[..<colon]
            path = url[url.index(after: colon)...]
        }
        if let user = host.lastIndex(of: "@") { host = host[host.index(after: user)...] }
        if let port = host.firstIndex(of: ":") { host = host[..<port] }
        while path.hasPrefix("/") { path = path.dropFirst() }
        while path.hasSuffix("/") { path = path.dropLast() }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        guard !host.isEmpty, !path.isEmpty else { return nil }
        self.init(host: host.lowercased(), path: String(path))
    }

    public var provider: GitProvider { GitProvider(host: host) }
}

/// Telling from a shell command whether it sends commits to a remote.
public enum PushCommand {
    /// Whether `command` pushes: `git push`, or creating a pull or merge request through the
    /// GitHub or GitLab CLI, anywhere in a chain of commands.
    public static func isPush(_ command: String) -> Bool {
        simpleCommands(in: command).contains { command in
            var words = command[...]
            // Variables set for the one command.
            while let first = words.first, first.contains("="), !first.hasPrefix("-") { words = words.dropFirst() }
            guard let tool = words.popFirst() else { return false }
            switch (tool as NSString).lastPathComponent {
            case "git":
                // Options of git itself come before the subcommand; two of them take a value.
                while let option = words.first, option.hasPrefix("-") {
                    words = words.dropFirst(option == "-C" || option == "-c" ? 2 : 1)
                }
                return words.first == "push" && !words.contains("--dry-run") && !words.contains("-n")
            case "gh":
                return words.starts(with: ["pr", "create"])
            case "glab":
                return words.starts(with: ["mr", "create"])
            default:
                return false
            }
        }
    }

    /// The commands of a chain, each as its words. Quotes keep their contents together, so a
    /// commit message that mentions a push is not one.
    private static func simpleCommands(in command: String) -> [[String]] {
        var commands: [[String]] = [[]]
        var word = ""
        var isWord = false
        var quote: Character?
        func endWord() {
            if isWord { commands[commands.count - 1].append(word) }
            word = ""
            isWord = false
        }
        for character in command {
            if let open = quote {
                if character == open { quote = nil } else { word.append(character) }
            } else if character == "'" || character == "\"" {
                quote = character
                isWord = true
            } else if character.isWhitespace && !character.isNewline {
                endWord()
            } else if ";&|()".contains(character) || character.isNewline {
                endWord()
                commands.append([])
            } else {
                word.append(character)
                isWord = true
            }
        }
        endWord()
        return commands
    }
}

/// "This session pushed commit X of branch Y": what the repository showed once the hook reported
/// the push.
public struct Push: Equatable, Sendable {
    public var sessionID: String
    public var commit: String
    /// Nil when no branch was checked out.
    public var branch: String?
    public var remote: GitRemote

    public init(sessionID: String, commit: String, branch: String?, remote: GitRemote) {
        self.sessionID = sessionID
        self.commit = commit
        self.branch = branch
        self.remote = remote
    }
}

/// The pipeline of one commit as its git host tells it.
public struct Pipeline: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// With the stage it is in, where the host says.
        case running(stage: String?)
        case passed
        case failed
        /// It is there, but how it went cannot be told: cancelled, skipped, or in a state the app does not know.
        case unknown
    }

    public var state: State
    public var url: String?
    public var failedJobURL: String?

    public init(state: State, url: String? = nil, failedJobURL: String? = nil) {
        self.state = state
        self.url = url
        self.failedJobURL = failedJobURL
    }
}

/// The answer to "what is the pipeline for this commit".
public enum PipelineLookup: Equatable, Sendable {
    case found(Pipeline)
    /// The host knows of none, at least not yet.
    case noPipeline
    /// The host could not be asked: no sign-in, no tool, no way to it.
    case noAccess
    /// The host answered something that could not be read.
    case unknown
}

/// A pull or merge request.
public struct RequestLink: Equatable, Sendable {
    public var number: Int
    public var url: String
    /// The branch it asks to merge.
    public var branch: String?
    /// In the provider's own word: open, merged, closed.
    public var state: String?

    public init(number: Int, url: String, branch: String? = nil, state: String? = nil) {
        self.number = number
        self.url = url
        self.branch = branch
        self.state = state
    }
}

/// What a look at the git host found out about the push a session is followed for.
public struct PipelineObservation: Equatable, Sendable {
    public var sessionID: String
    /// The commit that was asked about. A session may have pushed another one since.
    public var commit: String
    public var lookup: PipelineLookup
    /// The request of the pushed branch, when it was looked up and there is one.
    public var request: RequestLink?

    public init(sessionID: String, commit: String, lookup: PipelineLookup, request: RequestLink? = nil) {
        self.sessionID = sessionID
        self.commit = commit
        self.lookup = lookup
        self.request = request
    }
}

/// How the pipeline of a session's push stands.
public enum CIState: Equatable, Sendable {
    /// The session pushed; its pipeline has not been found yet.
    case pending
    case running(stage: String?)
    case passed
    case failed
    /// Could not be confirmed. Never shown as passed.
    case unknown
    case noAccess(host: String)

    /// Whether the pipeline has yet to end, which keeps its session in the list.
    public var isFollowed: Bool {
        switch self {
        case .pending, .running: true
        case .passed, .failed, .unknown, .noAccess: false
        }
    }
}

/// The CI of what a session pushed last.
public struct SessionCI: Equatable, Sendable {
    public var state: CIState
    /// The pipeline, or the job that failed when that is known.
    public var url: String?
    public var request: RequestLink?

    public init(state: CIState, url: String? = nil, request: RequestLink? = nil) {
        self.state = state
        self.url = url
        self.request = request
    }
}

/// A push somebody has to look at for the core: its repository, or the pipeline of its commit.
public struct FollowedPush: Equatable, Sendable {
    public var sessionID: String
    public var cwd: String?
    /// Nil while the repository has not been read since the session pushed.
    public var push: Push?
    /// The request of the branch, once known.
    public var request: RequestLink?
    /// The host could not be asked last time. It may be by now, but there is no hurry to try.
    public var lacksAccess: Bool

    public init(sessionID: String, cwd: String?, push: Push?, request: RequestLink?, lacksAccess: Bool = false) {
        self.sessionID = sessionID
        self.cwd = cwd
        self.push = push
        self.request = request
        self.lacksAccess = lacksAccess
    }
}

/// A pull or merge request the core goes on following after the session that pushed to it has
/// left the list. What is stored of it is what tells it apart; how it stands is asked afresh.
public struct FollowedMergeRequest: Equatable, Sendable, Codable, Identifiable {
    public struct ID: Hashable, Sendable {
        public var remote: GitRemote
        public var number: Int

        public init(remote: GitRemote, number: Int) {
            self.remote = remote
            self.number = number
        }
    }

    public var remote: GitRemote
    public var number: Int
    public var url: String
    /// Nil until the host was asked.
    public var title: String?
    /// The branch it asks to merge.
    public var branch: String?
    /// The pipeline of its head commit. Nil when it has none, or none is known yet.
    public var ci: CIState?
    /// That pipeline, or the job that failed when that is known.
    public var pipelineURL: String?

    public var id: ID { ID(remote: remote, number: number) }
    /// The repository by its name alone.
    public var project: String { (remote.path as NSString).lastPathComponent }

    public init(
        remote: GitRemote, number: Int, url: String, title: String? = nil, branch: String? = nil,
        ci: CIState? = nil, pipelineURL: String? = nil
    ) {
        self.remote = remote
        self.number = number
        self.url = url
        self.title = title
        self.branch = branch
        self.ci = ci
        self.pipelineURL = pipelineURL
    }

    private enum CodingKeys: String, CodingKey {
        case remote, number, url, title, branch
    }
}

/// A merge request as its git host tells it.
public struct MergeRequestStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case open
        case merged
        case closed
    }

    public var state: State
    public var title: String?
    public var url: String
    public var branch: String?
    /// The pipeline of its head commit.
    public var pipeline: PipelineLookup

    public init(state: State, title: String? = nil, url: String, branch: String? = nil, pipeline: PipelineLookup = .noPipeline) {
        self.state = state
        self.title = title
        self.url = url
        self.branch = branch
        self.pipeline = pipeline
    }
}

/// The answer to "how does this merge request stand".
public enum MergeRequestLookup: Equatable, Sendable {
    case found(MergeRequestStatus)
    /// The host could not be asked: no sign-in, no tool, no way to it.
    case noAccess
    /// The host answered something that could not be read.
    case unknown
}

/// What a look at the git host found out about a followed merge request.
public struct MergeRequestObservation: Equatable, Sendable {
    public var id: FollowedMergeRequest.ID
    public var lookup: MergeRequestLookup

    public init(id: FollowedMergeRequest.ID, lookup: MergeRequestLookup) {
        self.id = id
        self.lookup = lookup
    }
}
