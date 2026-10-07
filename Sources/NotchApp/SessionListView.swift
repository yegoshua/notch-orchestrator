import SessionCore
import SwiftUI

/// The open island as a list: every live session, the ones that need the user first, and the
/// usage limits underneath. A row says where a click on it leads before it is clicked.
struct SessionListView: View {
    @ObservedObject var model: AppModel
    /// The height of the band above the list, which counts against the height the island may take.
    let bandHeight: CGFloat
    let jump: (Session) -> Void

    /// The order the sessions were in when the list opened. Rows do not move under the pointer;
    /// a changed order shows the next time the list opens.
    @State private var order: [String] = []
    @State private var hovered: String?
    /// Sessions whose subagents the user folded away.
    @State private var folded: Set<String> = []

    private enum Metrics {
        static let groupHeight: CGFloat = 28
        static let regionPadding: CGFloat = 6
        static let emptyHeight: CGFloat = 96
        static let usageHeight: CGFloat = 70
        /// From this many sessions on, the list is grouped by state.
        static let groupingThreshold = 8
    }

    private enum Item: Identifiable {
        case group(String, Int)
        case row(Session)
        case subagent(Subagent, sessionID: String, isLast: Bool)

        var id: String {
            switch self {
            case .group(let label, _): "group:\(label)"
            case .row(let session): "row:\(session.id)"
            case .subagent(let subagent, let sessionID, _): "sub:\(sessionID):\(subagent.id)"
            }
        }

        var height: CGFloat {
            switch self {
            case .group: Metrics.groupHeight
            case .row: Island.rowHeight
            case .subagent: Island.subagentHeight
            }
        }
    }

    private var sessions: [Session] {
        let live = model.snapshot.sessions
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        // Sessions that appeared since the list opened go to the end, in the order the core gives.
        return live.enumerated().sorted {
            (position[$0.element.id] ?? order.count + $0.offset) < (position[$1.element.id] ?? order.count + $1.offset)
        }.map(\.element)
    }

    private var items: [Item] {
        func rows(_ sessions: [Session]) -> [Item] {
            sessions.flatMap { session -> [Item] in
                let subagents = folded.contains(session.id) ? [] : session.subagents
                return [.row(session)] + subagents.enumerated().map {
                    .subagent($1, sessionID: session.id, isLast: $0 == subagents.count - 1)
                }
            }
        }
        let sessions = sessions
        guard sessions.count >= Metrics.groupingThreshold else { return rows(sessions) }
        let groups: [(String, (SessionState) -> Bool)] = [
            ("Needs you", { $0.isWaiting }), ("Failed", { $0 == .failed }), ("Working", { $0 == .working }),
            ("Finished", { $0 == .finishedTurn }), ("Unknown", { $0 == .unknown }),
        ]
        return groups.flatMap { label, belongs -> [Item] in
            let members = sessions.filter { belongs($0.state) }
            return members.isEmpty ? [] : [.group(label, members.count)] + rows(members)
        }
    }

    var body: some View {
        let items = items
        let wanted = items.reduce(2 * Metrics.regionPadding) { $0 + $1.height }
        let region = min(wanted, Island.maxHeight - bandHeight - Metrics.usageHeight)
        VStack(spacing: 0) {
            if items.isEmpty {
                empty
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    // The clock ticks here so that elapsed times move while the list is open.
                    TimelineView(.periodic(from: .now, by: 1)) { timeline in
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                view(for: item, now: timeline.date).frame(height: item.height)
                            }
                        }
                        .padding(.vertical, Metrics.regionPadding)
                    }
                }
                .frame(height: region)
                // What continues below the edge fades out instead of being cut.
                .mask(LinearGradient(
                    stops: [.init(color: .black, location: 0),
                            .init(color: .black, location: wanted > region ? 1 - 34 / region : 1),
                            .init(color: wanted > region ? .clear : .black, location: 1)],
                    startPoint: .top, endPoint: .bottom))
            }
            UsageFooter(limits: model.limits).frame(height: Metrics.usageHeight)
        }
        .onAppear { order = model.snapshot.sessions.map(\.id) }
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No live sessions").font(Island.cardTitle).foregroundStyle(Island.text)
            (Text("Run ") + Text("claude").font(Island.code).foregroundColor(Island.text)
                + Text(" in any terminal or open the desktop app. Sessions appear here."))
                .font(Island.detail)
                .foregroundStyle(Island.text2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.emptyHeight)
    }

    @ViewBuilder
    private func view(for item: Item, now: Date) -> some View {
        switch item {
        case .group(let label, let count):
            HStack(spacing: 6) {
                Text(label).font(Island.label).foregroundStyle(Island.text3)
                Text("\(count)").font(Island.meta).foregroundStyle(Island.text4)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 6)
            .frame(maxHeight: .infinity, alignment: .bottom)
        case .row(let session):
            SessionRow(
                session: session, request: model.snapshot.requests.first { $0.sessionID == session.id },
                now: now, isHovered: hovered == session.id, isFolded: folded.contains(session.id),
                toggleSubagents: {
                    withAnimation(Island.content) { folded.formSymmetricDifference([session.id]) }
                })
                .background(HoverArea { inside in
                    if inside { hovered = session.id } else if hovered == session.id { hovered = nil }
                })
                .onTapGesture { jump(session) }
        case .subagent(let subagent, _, let isLast):
            SubagentRow(subagent: subagent, isLast: isLast)
        }
    }
}

private struct SessionRow: View {
    let session: Session
    /// What the session waits for, when the app holds the request.
    let request: PendingRequest?
    let now: Date
    let isHovered: Bool
    let isFolded: Bool
    let toggleSubagents: () -> Void

    private var target: JumpTarget? { session.location.jumpTarget }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        HStack(spacing: 9) {
            StateMark(state: session.state).frame(width: 14)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(session.title ?? session.project ?? "Untitled session")
                        .font(Island.listTitle)
                        .foregroundStyle(Island.text)
                        .layoutPriority(1)
                    (Text(meta).foregroundColor(Island.text3)
                        + Text(context.map { " · " + $0 } ?? "").foregroundColor(contextColor))
                        .font(Island.small)
                }
                .frame(height: 17)
                HStack(spacing: 6) {
                    Text(activity)
                        .font(Island.detail)
                        .foregroundStyle(session.state.isWaiting ? Island.text : Island.text2)
                    if !session.subagents.isEmpty {
                        Text("· \(session.subagents.count) subagent\(session.subagents.count == 1 ? "" : "s") \(isFolded ? "▸" : "▾")")
                            .font(Island.detail)
                            .foregroundStyle(Island.text3)
                            .layoutPriority(1)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: toggleSubagents)
                            .accessibilityAddTraits(.isButton)
                            .accessibilityLabel(isFolded ? "Show subagents" : "Hide subagents")
                    }
                }
                .frame(height: 16)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 8)
            trailing.fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
        .background {
            if isHovered {
                shape.fill(LinearGradient(colors: Island.rowHover, startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
            }
        }
        .contentShape(shape)
        .padding(.horizontal, 8)
        .animation(Island.quick, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(target == nil ? [] : .isButton)
        .accessibilityHint(target.map { "\($0.label). \($0.explanation)" } ?? "")
    }

    /// At rest: how long, and whether it needs the user. Under the pointer: where a click leads.
    @ViewBuilder
    private var trailing: some View {
        if isHovered {
            HStack(spacing: 7) {
                if let target { Text(target.reach).font(Island.small).foregroundStyle(Island.text3) }
                Text(target?.label ?? "No jump target")
                    .font(Island.detail)
                    .foregroundStyle(target == nil ? Island.text3 : Island.text)
            }
        } else {
            HStack(spacing: 8) {
                if session.state.isWaiting {
                    Text("Needs you").font(Island.label).foregroundStyle(Island.waiting)
                } else if session.state == .failed {
                    Text("Failed").font(Island.small).foregroundStyle(Island.failedText)
                }
                Text(Self.elapsed(from: session.since, to: now, ago: session.state != .working && !session.state.isWaiting))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Island.text3)
            }
        }
    }

    private var meta: String {
        [session.title == nil ? nil : session.project, session.location.originLabel]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// How full the context is: a share of the window where it is known, else the tokens in it.
    private var context: String? {
        if let used = session.context?.usedPercentage { return "\(LimitText.percent(used))% context" }
        guard let tokens = session.context?.tokens else { return nil }
        return tokens < 1000 ? "\(tokens) tokens" : "\(Int((Double(tokens) / 1000).rounded()))k tokens"
    }

    /// Stands out as the context fills up. Where only tokens are known the window is not, so
    /// the steps are those of the smallest window a session can have, 200k.
    private var contextColor: Color {
        let used = session.context?.usedPercentage ?? session.context?.tokens.map { Double($0) / 2000 } ?? 0
        switch used {
        case ..<60: return Island.text3
        case ..<85: return Island.waiting
        default: return Island.failedText
        }
    }

    private var activity: String {
        switch session.state {
        case .working:
            return session.activity ?? "Working"
        case .waitingForPermission:
            guard let request else { return "Waiting for permission in the session" }
            let subject = request.detail.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
            if subject.isEmpty { return "Wants to use \(request.toolName)" }
            return request.toolName == "Bash" ? "Wants to run \(subject)" : "Wants to use \(request.toolName): \(subject)"
        case .waitingForAnswer:
            return request?.questions.first.map { "Asks: \($0.text)" } ?? "Waiting for an answer in the session"
        case .finishedTurn:
            return "Finished"
        case .failed:
            return "The turn ended with an error"
        case .unknown:
            return "State could not be confirmed"
        }
    }

    private static func elapsed(from start: Date, to now: Date, ago: Bool) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        let text: String
        switch seconds {
        case ..<60: text = "\(seconds)s"
        case ..<3600: text = "\(seconds / 60)m"
        default: text = String(format: "%dh %02dm", seconds / 3600, seconds % 3600 / 60)
        }
        return ago ? "\(text) ago" : text
    }
}

private struct SubagentRow: View {
    let subagent: Subagent
    let isLast: Bool

    var body: some View {
        HStack(spacing: 8) {
            StateMark(state: .working, size: 7)
            if !subagent.type.isEmpty {
                Text(subagent.type).font(Island.smallCode).foregroundStyle(Island.text2)
                    .layoutPriority(1)
            }
            Text(description).font(Island.detail).foregroundStyle(Island.text2)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        // The branch that ties the subagent to its session.
        .background(alignment: .topLeading) {
            let line = Island.branch
            ZStack(alignment: .topLeading) {
                line.frame(width: 1, height: isLast ? Island.subagentHeight / 2 : Island.subagentHeight)
                line.frame(width: 12, height: 1).offset(y: Island.subagentHeight / 2)
            }
            .offset(x: 13.5)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
    }

    private var description: String {
        [subagent.task, subagent.activity].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Account-wide usage: both windows with their reset times and the age of the figures.
private struct UsageFooter: View {
    let limits: LimitsSnapshot

    var body: some View {
        // The clock ticks here so that "updated … ago" and an expired window do not wait for a payload.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 22) {
                    meter("5-hour", limits.fiveHour, now: timeline.date)
                    meter("Weekly", limits.sevenDay, now: timeline.date)
                }
                Spacer().frame(height: 10)
                Text(limits.fiveHour == .noData && limits.sevenDay == .noData
                    ? LimitText.noDataExplanation : LimitText.freshness(limits))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Island.text3)
                    .lineLimit(1)
                    .frame(height: 14)
            }
            .padding(.horizontal, 18)
            .padding(.top, 10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .overlay(alignment: .top) { Island.divider.frame(height: 1) }
    }

    private func meter(_ name: String, _ window: LimitWindow, now: Date) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                Text(name).foregroundStyle(Island.text2)
                Text(LimitText.figure(window))
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .foregroundStyle(LimitText.color(window))
                Spacer(minLength: 4)
                Text(resets(window, now: now)).foregroundStyle(Island.text3)
            }
            .font(Island.small)
            .lineLimit(1)
            .frame(height: 15)
            GeometryReader { proxy in
                Capsule().fill(Island.barTrack)
                if case .known(let reading) = window {
                    Capsule().fill(LimitText.barColor(reading.usedPercentage))
                        .opacity(reading.isStale ? 0.5 : 1)
                        .frame(width: max(4, proxy.size.width * min(1, reading.usedPercentage / 100)))
                        .animation(Island.ring, value: reading.usedPercentage)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LimitText.line("\(name) limit", window, now: now))
    }

    private func resets(_ window: LimitWindow, now: Date) -> String {
        switch window {
        case .known: LimitText.resets(window, now: now) ?? ""
        case .reset: "window reset"
        case .noData: "no data yet"
        }
    }
}
