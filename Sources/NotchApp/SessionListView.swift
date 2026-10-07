import SessionCore
import SwiftUI

/// The expanded notch: every live session, the ones that need the user first.
struct SessionListView: View {
    @ObservedObject var model: AppModel
    /// Room to leave at the top for the notch itself.
    let topInset: CGFloat

    enum Metrics {
        static let width: CGFloat = 460
        static let rowHeight: CGFloat = 40
        static let subagentHeight: CGFloat = 18
        static let emptyHeight: CGFloat = 36
        static let padding: CGFloat = 8
        static let limitLineHeight: CGFloat = 16
        /// The usage limits under the list: a divider and one line per window.
        static let footerHeight: CGFloat = 9 + 2 * limitLineHeight

        static func height(of sessions: [Session], topInset: CGFloat) -> CGFloat {
            let rows = sessions.reduce(CGFloat(0)) {
                $0 + rowHeight + CGFloat($1.subagents.count) * subagentHeight
            }
            return topInset + padding + (sessions.isEmpty ? emptyHeight : rows) + footerHeight + padding
        }
    }

    var body: some View {
        let sessions = model.snapshot.sessions
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset + Metrics.padding)
            ScrollView(.vertical, showsIndicators: false) {
                // The clock ticks here so that elapsed times move while the list is open.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    VStack(spacing: 0) {
                        if sessions.isEmpty {
                            Text("No live sessions")
                                .font(.system(size: 12))
                                .foregroundStyle(Color(white: 0.55))
                                .frame(maxWidth: .infinity)
                                .frame(height: Metrics.emptyHeight)
                        }
                        ForEach(sessions, id: \.id) { session in
                            SessionRow(session: session, now: timeline.date)
                        }
                    }
                }
            }
            LimitsFooter(limits: model.limits).frame(height: Metrics.footerHeight)
            Color.clear.frame(height: Metrics.padding)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(.black))
    }
}

/// Account-wide usage: both windows with their reset times and the age of the figures.
private struct LimitsFooter: View {
    let limits: LimitsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider().overlay(Color(white: 0.25)).padding(.vertical, 4)
            // The clock ticks here so that "updated … ago" and an expired window do not wait for a payload.
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                VStack(alignment: .leading, spacing: 0) {
                    if limits.fiveHour == .noData && limits.sevenDay == .noData {
                        line("Usage limits: no data yet")
                        line(LimitText.noDataExplanation)
                    } else {
                        line(LimitText.line("5-hour limit", limits.fiveHour, now: timeline.date))
                        line(LimitText.line("Weekly limit", limits.sevenDay, now: timeline.date))
                    }
                }
            }
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(Color(white: 0.6))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SessionListView.Metrics.limitLineHeight)
    }
}

private struct SessionRow: View {
    let session: Session
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 9) {
                StateMark(state: session.state).frame(width: 11, height: 11)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(session.project ?? "Unknown project")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(white: 0.95))
                            .layoutPriority(1)
                        if let title = session.title {
                            Text(title).font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
                        }
                    }
                    Text(status).font(.system(size: 11)).foregroundStyle(StateMark.color(session.state))
                }
                .lineLimit(1)
                .truncationMode(.tail)
                Spacer(minLength: 8)
                Text(Self.elapsed(from: session.since, to: now, ago: session.state != .working))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(white: 0.6))
            }
            .frame(height: SessionListView.Metrics.rowHeight)
            .accessibilityElement(children: .combine)

            ForEach(session.subagents, id: \.id) { subagent in
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right").font(.system(size: 8, weight: .semibold))
                    Text(Self.describe(subagent)).font(.system(size: 11)).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .foregroundStyle(Color(white: 0.6))
                .padding(.leading, 20)
                .frame(height: SessionListView.Metrics.subagentHeight)
            }
        }
    }

    private var status: String {
        let label: String
        switch session.state {
        case .working: label = "Working"
        case .finishedTurn: label = "Finished"
        case .failed: label = "Failed"
        case .unknown: label = "Unknown"
        }
        var parts = [label]
        if let activity = session.activity { parts.append(activity) }
        if session.activity == nil, session.state == .working, !session.subagents.isEmpty {
            parts.append(session.subagents.count == 1 ? "1 subagent" : "\(session.subagents.count) subagents")
        }
        return parts.joined(separator: " · ")
    }

    private static func describe(_ subagent: Subagent) -> String {
        var parts = [subagent.task ?? (subagent.type.isEmpty ? "Subagent" : subagent.type)]
        if let activity = subagent.activity { parts.append(activity) }
        return parts.joined(separator: " · ")
    }

    private static func elapsed(from start: Date, to now: Date, ago: Bool) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let text: String
        switch seconds {
        case ..<60: text = "\(seconds)s"
        case ..<3600: text = ago ? "\(seconds / 60)m" : String(format: "%dm %02ds", seconds / 60, seconds % 60)
        default: text = String(format: "%dh %02dm", seconds / 3600, seconds % 3600 / 60)
        }
        return ago ? "\(text) ago" : text
    }
}

/// The state as a shape, so it reads without relying on colour.
private struct StateMark: View {
    let state: SessionState
    @State private var turning = false

    var body: some View {
        Group {
            switch state {
            case .working:
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(turning ? 360 : 0))
                    .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: turning)
                    .onAppear { turning = true }
            case .finishedTurn:
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
            case .unknown:
                Image(systemName: "questionmark").font(.system(size: 9, weight: .heavy))
            }
        }
        .foregroundStyle(Self.color(state))
    }

    static func color(_ state: SessionState) -> Color {
        switch state {
        case .working: Color(red: 0.45, green: 0.68, blue: 1.0)
        case .finishedTurn: Color(red: 0.45, green: 0.85, blue: 0.55)
        case .failed: Color(red: 1.0, green: 0.62, blue: 0.30)
        case .unknown: Color(white: 0.55)
        }
    }
}
