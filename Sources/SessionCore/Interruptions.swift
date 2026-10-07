import Foundation

/// How readily the island interrupts the user.
public enum InterruptionMode: String, Equatable, Sendable {
    /// Every request expands with a sound and every finished turn shows its line with a sound,
    /// also when the session is in front.
    case loud
    /// A request expands with a sound only when its session is not in front; a finished turn
    /// shows a silent line.
    case smart
    /// Nothing expands and nothing sounds: the counters are the only sign.
    case quiet
}

/// The window in front of the user, as far as it can be told from outside.
public struct FrontWindow: Equatable, Sendable {
    /// The application the window belongs to.
    public var bundleID: String
    /// The terminal device of the selected tab, when the application is Terminal and it said so.
    public var terminalTTY: String?

    public init(bundleID: String, terminalTTY: String? = nil) {
        self.bundleID = bundleID
        self.terminalTTY = terminalTTY
    }
}

/// What the user is looking at and whether they asked the system for quiet.
public struct Attention: Equatable, Sendable {
    /// Nil when nothing is known about it.
    public var frontWindow: FrontWindow?
    /// A macOS Focus is on.
    public var focusIsOn: Bool

    public init(frontWindow: FrontWindow? = nil, focusIsOn: Bool = false) {
        self.frontWindow = frontWindow
        self.focusIsOn = focusIsOn
    }
}

/// The one line that tells of a turn that ended, or of a pipeline that did.
public struct TransientLine: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case finished
        case failed
        /// The pipeline of what the session pushed passed.
        case ciPassed
        /// It failed.
        case ciFailed
    }

    public var sessionID: String
    public var title: String?
    public var project: String?
    public var kind: Kind

    public init(sessionID: String, title: String?, project: String?, kind: Kind) {
        self.sessionID = sessionID
        self.title = title
        self.project = project
        self.kind = kind
    }
}

/// Something the island does by itself to get the user's attention. Whatever else happens only
/// changes the snapshot: a counter, a colour.
public enum Interruption: Equatable, Sendable {
    /// The request joined `Snapshot.raised`: the island expands with its card. With a sound when
    /// the request is news to the user.
    case expand(requestID: String, sound: Bool)
    /// A turn or a pipeline ended: the island shows the line for a moment and collapses again.
    case line(TransientLine, sound: Bool)
}

/// The system's record of the Focus assertions in force, `~/Library/DoNotDisturb/DB/Assertions.json`.
/// The format is undocumented; a Focus the user turned on shows as an assertion record.
public enum FocusRecord {
    /// Whether a Focus is on. Nil when the data is not that record.
    public static func isOn(json: Data) -> Bool? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let stores = object["data"] as? [[String: Any]]
        else { return nil }
        return stores.contains { ($0["storeAssertionRecords"] as? [Any])?.isEmpty == false }
    }
}
