import Foundation

/// One Claude Code hook invocation, reduced to the fields the session core reads.
public struct HookEvent: Equatable, Sendable {
    public struct BackgroundTask: Equatable, Sendable {
        public var id: String
        public var type: String
        public var status: String
        public var description: String?
        public var agentType: String?

        public init(
            id: String = "", type: String, status: String, description: String? = nil, agentType: String? = nil
        ) {
            self.id = id
            self.type = type
            self.status = status
            self.description = description
            self.agentType = agentType
        }
    }

    /// A tool call as `PreToolUse` reports it.
    public struct Tool: Equatable, Sendable {
        public var name: String
        /// The one input that says what the call is about: the command, the file, the pattern.
        public var subject: String?
        /// The whole input, as Claude Code sent it.
        public var input: JSONValue?

        public init(name: String, subject: String? = nil, input: JSONValue? = nil) {
            self.name = name
            self.subject = subject
            self.input = input
        }
    }

    public var name: String
    public var sessionID: String
    public var cwd: String?
    public var transcriptPath: String?
    /// `SessionStart` only: startup, resume, clear or compact.
    public var source: String?
    /// `UserPromptSubmit` only.
    public var prompt: String?
    /// Tool events only.
    public var tool: Tool?
    /// Set when the event comes from inside a subagent, and on `SubagentStart` / `SubagentStop`.
    public var agentID: String?
    public var agentType: String?
    /// `Stop` only: work that outlives the turn.
    public var backgroundTasks: [BackgroundTask]

    public init(
        name: String, sessionID: String, cwd: String? = nil, transcriptPath: String? = nil,
        source: String? = nil, prompt: String? = nil, tool: Tool? = nil,
        agentID: String? = nil, agentType: String? = nil, backgroundTasks: [BackgroundTask] = []
    ) {
        self.name = name
        self.sessionID = sessionID
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.source = source
        self.prompt = prompt
        self.tool = tool
        self.agentID = agentID
        self.agentType = agentType
        self.backgroundTasks = backgroundTasks
    }

    /// Decodes the JSON body Claude Code passes to a hook. Returns nil when it is not a hook payload.
    public init?(payload: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let name = object["hook_event_name"] as? String,
              let sessionID = object["session_id"] as? String
        else { return nil }
        let tasks = (object["background_tasks"] as? [[String: Any]] ?? []).map {
            BackgroundTask(
                id: $0["id"] as? String ?? "", type: $0["type"] as? String ?? "",
                status: $0["status"] as? String ?? "", description: $0["description"] as? String,
                agentType: $0["agent_type"] as? String)
        }
        self.init(
            name: name, sessionID: sessionID,
            cwd: object["cwd"] as? String,
            transcriptPath: object["transcript_path"] as? String,
            source: object["source"] as? String,
            prompt: object["prompt"] as? String,
            tool: (object["tool_name"] as? String).map {
                Tool(
                    name: $0, subject: Self.subject(of: object["tool_input"] as? [String: Any] ?? [:]),
                    input: object["tool_input"].flatMap(JSONValue.init))
            },
            agentID: object["agent_id"] as? String,
            agentType: object["agent_type"] as? String,
            backgroundTasks: tasks
        )
    }

    private static func subject(of input: [String: Any]) -> String? {
        if let path = input["file_path"] as? String ?? input["notebook_path"] as? String {
            return (path as NSString).lastPathComponent
        }
        for key in ["command", "description", "pattern", "query", "url", "skill"] {
            if let value = input[key] as? String, !value.isEmpty { return value }
        }
        return nil
    }
}
