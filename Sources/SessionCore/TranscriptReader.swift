import Foundation

/// Reads the end of a Claude Code transcript (JSON lines). The format is undocumented, so anything
/// unrecognised is skipped and the answer is nil rather than a guess.
public enum TranscriptReader {
    /// What the last entries of `text` say about the session's turn. `text` may start mid-line.
    public static func tail(of text: String) -> TranscriptTail? {
        for line in text.split(whereSeparator: \.isNewline).reversed() {
            guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  entry["isSidechain"] as? Bool != true,
                  let at = (entry["timestamp"] as? String).flatMap(date)
            else { continue }
            let message = entry["message"] as? [String: Any] ?? [:]

            switch entry["type"] as? String {
            case "system":
                switch entry["subtype"] as? String {
                case "turn_duration":
                    // Written by the CLI only; it leaves the count out when nothing is pending.
                    let pending = entry["pendingBackgroundAgentCount"] as? Int ?? 0
                    return TranscriptTail(turn: .ended(pendingBackgroundAgents: pending), at: at)
                case "compact_boundary":
                    // What came before was rewritten into a summary; what comes after is not a turn yet.
                    return nil
                default:
                    continue
                }
            case "assistant":
                let stopped = message["stop_reason"] as? String
                let turn: TranscriptTail.Turn =
                    stopped == nil || stopped == "tool_use" ? .inProgress : .ended(pendingBackgroundAgents: nil)
                return TranscriptTail(turn: turn, at: at)
            case "user":
                if entry["isMeta"] as? Bool == true || entry["isCompactSummary"] as? Bool == true { continue }
                if let blocks = message["content"] as? [[String: Any]] {
                    if blocks.contains(where: { $0["type"] as? String == "tool_result" }) {
                        return TranscriptTail(turn: .inProgress, at: at)
                    }
                    let interrupted = blocks.contains {
                        ($0["text"] as? String)?.hasPrefix("[Request interrupted by user") == true
                    }
                    if interrupted { return TranscriptTail(turn: .ended(pendingBackgroundAgents: nil), at: at) }
                    continue
                }
                // Only a submitted prompt starts a turn; slash commands and their output do not.
                if entry["promptSource"] != nil || entry["permissionMode"] != nil {
                    return TranscriptTail(turn: .inProgress, at: at)
                }
                continue
            default:
                continue
            }
        }
        return nil
    }

    /// The most recent title Claude Code gave the session, if `text` holds one.
    public static func title(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline).reversed() where line.contains("\"ai-title\"") {
            if let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
               entry["type"] as? String == "ai-title", let title = entry["aiTitle"] as? String, !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private static func date(_ text: String) -> Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: text)
    }
}
