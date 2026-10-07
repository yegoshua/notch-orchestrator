import Foundation

/// One multiple-choice question an agent asked through `AskUserQuestion`.
public struct Question: Equatable, Sendable {
    public struct Option: Equatable, Sendable {
        public var label: String
        public var description: String?
    }

    public var text: String
    /// A word or two naming what the question is about.
    public var header: String?
    public var options: [Option]
    /// Whether several options may be chosen.
    public var allowsMultiple: Bool
}

/// A session asking the user for permission to run a tool call, or for an answer, while its hook
/// connection is held open.
public struct PendingRequest: Equatable, Sendable, Identifiable {
    /// Given by whoever holds the connection; resolutions carry it back.
    public var id: String
    public var sessionID: String
    public var sessionTitle: String?
    public var project: String?
    public var toolName: String
    /// What is being asked, in full: the command, the path, or the whole input when a tool has no
    /// single subject.
    public var detail: String
    /// For edits: the first lines of the change, removed lines marked `-` and added ones `+`.
    public var excerpt: String?
    /// Not empty when this is an agent's question rather than a permission request.
    public var questions: [Question]
    public var arrivedAt: Date
}

/// What the user did with a request.
public enum Decision: Equatable, Sendable {
    case allow
    /// The explanation, when there is one, is given to the agent as the reason.
    case deny(explanation: String?)
    /// Leave it to the session's own dialog.
    case handBack
    /// For a question: the labels chosen for each question, in the order the questions were asked.
    case answer([[String]])
}

/// What a held hook connection is to be told.
public enum Outcome: Equatable, Sendable {
    /// `updatedInput` replaces the tool input; that is how the answers to a question travel.
    case allow(updatedInput: JSONValue?)
    case deny(message: String?)
    /// Claude Code carries on with its own dialog, as if the hook had not been there.
    case noDecision
}

/// The end of a request, to be delivered to the connection held under `requestID`. Every request
/// the core was given gets exactly one.
public struct Resolution: Equatable, Sendable {
    public var requestID: String
    public var outcome: Outcome

    public init(requestID: String, outcome: Outcome) {
        self.requestID = requestID
        self.outcome = outcome
    }
}

/// What the permission hook answers Claude Code with.
public enum PermissionResponse {
    /// The response body for `outcome`. Empty for no decision.
    public static func body(for outcome: Outcome) -> Data {
        let decision: String
        switch outcome {
        case .noDecision:
            return Data()
        case .allow(let updatedInput):
            decision = #"{"behavior":"allow""# + (updatedInput.map { #","updatedInput":"# + $0.serialized } ?? "") + "}"
        case .deny(let message):
            decision = #"{"behavior":"deny""# + (message.map { #","message":"# + JSONValue.quoted($0) } ?? "") + "}"
        }
        return Data((#"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":"# + decision + "}}").utf8)
    }
}

/// How a tool call is put before the user.
enum RequestPresentation {
    static let questionTool = "AskUserQuestion"
    private static let excerptLines = 8
    private static let excerptLineLength = 160

    static func detail(of input: JSONValue?) -> String {
        guard let input else { return "" }
        for key in ["command", "file_path", "notebook_path", "url", "pattern", "query", "skill"] {
            if let value = input[key]?.string, !value.isEmpty { return value }
        }
        return input.serialized
    }

    static func excerpt(of input: JSONValue?) -> String? {
        guard let input else { return nil }
        var lines: [String] = []
        func add(_ mark: String, _ text: String?) {
            guard let text, !text.isEmpty else { return }
            for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
                lines.append("\(mark) \(line.prefix(excerptLineLength))")
            }
        }
        if let edits = input["edits"]?.array {
            for edit in edits {
                add("-", edit["old_string"]?.string)
                add("+", edit["new_string"]?.string)
            }
        } else if input["old_string"] != nil || input["new_string"] != nil {
            add("-", input["old_string"]?.string)
            add("+", input["new_string"]?.string)
        } else {
            add("+", (input["content"] ?? input["new_source"])?.string)
        }
        guard !lines.isEmpty else { return nil }
        if lines.count > excerptLines {
            let hidden = lines.count - excerptLines
            lines = lines.prefix(excerptLines) + ["… \(hidden) more line\(hidden == 1 ? "" : "s")"]
        }
        return lines.joined(separator: "\n")
    }

    /// The questions of an `AskUserQuestion` call. Empty when the input is not understood, in which
    /// case the call is shown as an ordinary permission request.
    static func questions(tool: String, input: JSONValue?) -> [Question] {
        guard tool == questionTool, let asked = input?["questions"]?.array, !asked.isEmpty else { return [] }
        var questions: [Question] = []
        for item in asked {
            guard let text = item["question"]?.string, let options = item["options"]?.array else { return [] }
            let parsed = options.compactMap { option in
                option["label"]?.string.map { Question.Option(label: $0, description: option["description"]?.string) }
            }
            guard !parsed.isEmpty, parsed.count == options.count else { return [] }
            questions.append(Question(
                text: text, header: item["header"]?.string, options: parsed,
                allowsMultiple: item["multiSelect"] == .bool(true)))
        }
        return questions
    }

    /// The tool input with the chosen labels added the way Claude Code expects them: one string
    /// per question, several choices joined with ", ". Nil when the choices do not fit the questions.
    static func answered(_ input: JSONValue?, questions: [Question], with choices: [[String]]) -> JSONValue? {
        guard case .object(var members)? = input, !questions.isEmpty, choices.count == questions.count else { return nil }
        var answers: [String: JSONValue] = [:]
        for (question, chosen) in zip(questions, choices) {
            guard !chosen.isEmpty, chosen.count == 1 || question.allowsMultiple else { return nil }
            answers[question.text] = .string(chosen.joined(separator: ", "))
        }
        members["answers"] = .object(answers)
        return .object(members)
    }

    /// Whether a returning tool call is the one a request was about. The request carries no call
    /// identifier, so tool and input have to do; an answered question comes back with its answers
    /// added to the input.
    static func isSameCall(_ tool: String, _ input: JSONValue?, as other: HookEvent.Tool) -> Bool {
        guard tool == other.name else { return false }
        func comparable(_ value: JSONValue?) -> JSONValue? {
            guard tool == questionTool, case .object(var members)? = value else { return value }
            members["answers"] = nil
            return .object(members)
        }
        return comparable(input) == comparable(other.input)
    }
}
