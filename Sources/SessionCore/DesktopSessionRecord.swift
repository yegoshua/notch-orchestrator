import Foundation

/// The record the Claude desktop app keeps per Code session, reduced to what tells a desktop
/// session from a CLI one. The format is private to the app: anything unexpected reads as "no record".
public struct DesktopSessionRecord: Equatable, Sendable {
    /// The desktop app's own identifier, `local_…`. Deep links take this one.
    public var sessionID: String
    /// The Claude Code session the desktop session currently runs: what hooks call `session_id`.
    public var cliSessionID: String?
    /// Identifiers it ran under before a clear, a compaction or a resume.
    public var priorCLISessionIDs: [String]
    /// The title shown in the desktop sidebar.
    public var title: String?

    public init(
        sessionID: String, cliSessionID: String? = nil, priorCLISessionIDs: [String] = [],
        title: String? = nil
    ) {
        self.sessionID = sessionID
        self.cliSessionID = cliSessionID
        self.priorCLISessionIDs = priorCLISessionIDs
        self.title = title
    }

    /// Reads the contents of a record file. Nil when it is not a session record.
    public init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any],
              let sessionID = object["sessionId"] as? String, !sessionID.isEmpty
        else { return nil }
        var prior = object["priorCliSessionIds"] as? [String] ?? []
        for key in ["unarchivedCliSessionId", "preClearCliSessionId", "historyOnlyCliSessionId"] {
            if let id = object[key] as? String { prior.append(id) }
        }
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(
            sessionID: sessionID, cliSessionID: object["cliSessionId"] as? String, priorCLISessionIDs: prior,
            title: title?.isEmpty == false ? title : nil)
    }

    /// The desktop session behind a hook session identifier; nil for a CLI session.
    /// `hostSessionID` is the desktop identifier the session's own process reports, when it does.
    /// The identifier a desktop session runs under changes over its life, so the answer is only
    /// good for the records it was taken from.
    public static func owning(
        _ cliSessionID: String, hostSessionID: String? = nil, among records: [DesktopSessionRecord]
    ) -> DesktopSessionRecord? {
        if let hostSessionID, let named = records.first(where: { $0.sessionID == hostSessionID }) { return named }
        return records.first { $0.cliSessionID == cliSessionID }
            ?? records.first { $0.priorCLISessionIDs.contains(cliSessionID) }
            // A session imported from the CLI keeps the CLI identifier in its name.
            ?? records.first { $0.sessionID == "local_\(cliSessionID)" }
    }
}
