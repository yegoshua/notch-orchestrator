import SessionCore
import SwiftUI

/// The open island as a list: every live session, the ones that need the user first, the merge
/// requests that outlived their sessions, and the usage limits underneath. A row says where a click on it leads before it is clicked.
struct SessionListView: View {
    @ObservedObject var model: AppModel
    /// The height of the band above the list, which counts against the height the island may take.
    let bandHeight: CGFloat
    let jump: (Session) -> Void
    /// Opens the pipeline of a session's push in the browser.
    let openPipeline: (URL) -> Void

    /// The order the sessions were in when the list opened. Rows do not move under the pointer;
    /// a changed order shows the next time the list opens.
    @State private var order: [String] = []
    /// What is under the pointer: a session by its id, a merge request by the id of its row.
    @State private var hovered: String?
    /// Sessions whose subagents the user folded away.
    @State private var folded: Set<String> = []

    private enum Metrics {
        static let groupHeight: CGFloat = 28
        static let regionPadding: CGFloat = 6
        static let emptyHeight: CGFloat = 96
        static let usageHeight: CGFloat = 36
        static let mergeRequestHeight: CGFloat = 28
        static let mergeRequests = "Merge requests"
        /// From this many sessions on, the list is grouped by state.
        static let groupingThreshold = 8
    }

    private enum Item: Identifiable {
        case group(String, Int)
        case row(Session)
        case subagent(Subagent, sessionID: String, isLast: Bool)
        /// The CI of what the session pushed, on a line of its own.
        case pipeline(SessionCI, sessionID: String, isLast: Bool)
        case mergeRequest(FollowedMergeRequest)

        var id: String {
            switch self {
            case .group(let label, _): "group:\(label)"
            case .row(let session): "row:\(session.id)"
            case .subagent(let subagent, let sessionID, _): "sub:\(sessionID):\(subagent.id)"
            case .pipeline(_, let sessionID, _): "ci:\(sessionID)"
            case .mergeRequest(let request): "mr:\(request.remote.host)/\(request.remote.path)!\(request.number)"
            }
        }

        var height: CGFloat {
            switch self {
            case .group: Metrics.groupHeight
            case .row: Island.rowHeight
            case .subagent, .pipeline: Island.subagentHeight
            case .mergeRequest: Metrics.mergeRequestHeight
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
                var lines: [Item] = [.row(session)]
                if model.ciView == .detailed, let ci = session.ci {
                    lines.append(.pipeline(ci, sessionID: session.id, isLast: subagents.isEmpty))
                }
                return lines + subagents.enumerated().map {
                    .subagent($1, sessionID: session.id, isLast: $0 == subagents.count - 1)
                }
            }
        }
        let sessions = sessions
        let followed = model.snapshot.mergeRequests
        let mergeRequests: [Item] = followed.isEmpty
            ? [] : [.group(Metrics.mergeRequests, followed.count)] + followed.map(Item.mergeRequest)
        guard sessions.count >= Metrics.groupingThreshold else { return rows(sessions) + mergeRequests }
        let groups: [(String, (SessionState) -> Bool)] = [
            ("Needs you", { $0.isWaiting }), ("Failed", { $0 == .failed }), ("Working", { $0 == .working }),
            ("Finished", { $0 == .finishedTurn }), ("Unknown", { $0 == .unknown }),
        ]
        return groups.flatMap { label, belongs -> [Item] in
            let members = sessions.filter { belongs($0.state) }
            return members.isEmpty ? [] : [.group(label, members.count)] + rows(members)
        } + mergeRequests
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
                showsCI: model.ciView == .compact, openPipeline: openPipeline,
                toggleSubagents: {
                    withAnimation(Island.content) { folded.formSymmetricDifference([session.id]) }
                })
                .background(HoverArea { inside in
                    if inside { hovered = session.id } else if hovered == session.id { hovered = nil }
                })
                .onTapGesture { jump(session) }
        case .subagent(let subagent, _, let isLast):
            SubagentRow(subagent: subagent, isLast: isLast)
        case .pipeline(let ci, _, let isLast):
            PipelineRow(ci: ci, isLast: isLast, isHovered: hovered == item.id, open: openPipeline)
                .background(HoverArea { inside in
                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                })
        case .mergeRequest(let request):
            MergeRequestRow(
                request: request, isHovered: hovered == item.id, open: openPipeline,
                remove: { model.stopFollowing(request) })
                .background(HoverArea { inside in
                    if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
                })
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
    /// Whether the CI of the session's push is told in this row, not on a line of its own.
    let showsCI: Bool
    let openPipeline: (URL) -> Void
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
                    if showsCI, let ci = session.ci {
                        if let request = ci.request { RequestMark(request: request, open: openPipeline) }
                        PipelineMark(ci: ci, open: openPipeline)
                        ApprovalsMark(approvals: ci.approvals, isReady: ci.isReadyToMerge)
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

/// The pull or merge request the session pushed to, by its number as its host writes it. A
/// click on it opens the request.
private struct RequestMark: View {
    let request: RequestLink
    let open: (URL) -> Void

    private var url: URL? {
        guard let url = URL(string: request.url), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    var body: some View {
        let mark = Text("\(request.url.contains("/merge_requests/") ? "!" : "#")\(request.number)")
            .font(Island.smallCode)
            .foregroundStyle(Island.text2)
            .layoutPriority(1)
        if let url {
            mark.contentShape(Rectangle())
                .onTapGesture { open(url) }
                .accessibilityAddTraits(.isLink)
                .accessibilityHint("Opens the request in the browser")
        } else {
            mark
        }
    }
}

private extension SessionCI {
    /// The pipeline, else the request of the branch. What a host handed out is opened only when
    /// it is a web address.
    var link: URL? {
        guard let url = (url ?? request?.url).flatMap(URL.init(string:)),
              url.scheme == "https" || url.scheme == "http"
        else { return nil }
        return url
    }

    var label: String {
        switch state {
        case .pending: "CI pending"
        case .running(let stage): stage.map { "CI running: \($0)" } ?? "CI running"
        case .passed: "CI passed"
        case .failed: "CI failed"
        case .held: "CI waits to be started"
        case .unknown: "CI unknown"
        case .noAccess(let host): "CI: no access to \(host)"
        }
    }

    var color: Color {
        switch state {
        case .running: Island.working
        case .passed: Island.finished
        case .failed: Island.failedText
        case .held: Island.text2
        case .pending, .unknown, .noAccess: Island.text3
        }
    }

    /// The mark of the session state that says the same of a pipeline.
    var mark: SessionState {
        switch state {
        case .running: .working
        case .passed: .finishedTurn
        case .failed: .failed
        case .pending, .held, .unknown, .noAccess: .unknown
        }
    }

    /// Whether there is a pipeline to speak of, not only a reason why none can be shown.
    var isKnown: Bool {
        switch state {
        case .running, .passed, .failed, .held: true
        case .pending, .unknown, .noAccess: false
        }
    }
}

/// How a merge request stands with its reviewers: how many approved of how many the project asks
/// for, and whether it is ready to merge. Nothing where nobody approved and nobody has to.
private struct ApprovalsMark: View {
    let approvals: Approvals?
    let isReady: Bool

    private var count: String? {
        guard let approvals, approvals.given > 0 || approvals.required > 0 else { return nil }
        if approvals.required > 0 { return "\(approvals.given)/\(approvals.required) approvals" }
        return approvals.given == 1 ? "1 approval" : "\(approvals.given) approvals"
    }

    private var text: String? {
        guard isReady else { return count }
        return count.map { "\($0) · ready to merge" } ?? "Ready to merge"
    }

    var body: some View {
        if let text {
            Text(text).font(Island.small).foregroundStyle(isReady ? Island.finished : Island.text3)
                .fixedSize()
        }
    }
}

/// Where the commit of a merge goes, as the host recorded it: "staging deployed · production
/// deploying". A click opens the pipeline that does it.
private struct DeploymentsMark: View {
    let deployments: [Deployment]
    let pipeline: URL?
    let open: (URL) -> Void

    private static func words(_ state: Deployment.State) -> String {
        switch state {
        case .waiting: "waits"
        case .running: "deploying"
        case .succeeded: "deployed"
        case .failed: "deploy failed"
        case .unknown: "deploy unknown"
        }
    }

    private static func color(_ state: Deployment.State) -> Color {
        switch state {
        case .running: Island.working
        case .succeeded: Island.finished
        case .failed: Island.failedText
        case .waiting, .unknown: Island.text3
        }
    }

    var body: some View {
        let mark = HStack(spacing: 4) {
            ForEach(Array(deployments.enumerated()), id: \.offset) { index, deployment in
                if index > 0 { Text("·").font(Island.small).foregroundStyle(Island.text4) }
                Text("\(deployment.environment) \(Self.words(deployment.state))")
                    .font(Island.small).foregroundStyle(Self.color(deployment.state))
            }
        }
        if let pipeline {
            mark.contentShape(Rectangle())
                .onTapGesture { open(pipeline) }
                .accessibilityAddTraits(.isLink)
                .accessibilityHint("Opens the pipeline in the browser")
        } else {
            mark
        }
    }
}

/// The CI of what the session pushed, as a tag in the row: its mark and a few words, on its
/// colour. A click on it opens the pipeline, on the job that failed when there is one; the rest
/// of the row keeps the jump to the session.
private struct PipelineMark: View {
    let ci: SessionCI
    let open: (URL) -> Void

    var body: some View {
        let mark = HStack(spacing: 4) {
            if ci.isKnown { StateMark(state: ci.mark, size: 6) }
            Text(ci.label).font(Island.small).foregroundStyle(ci.color)
        }
        .padding(.horizontal, ci.isKnown ? 6 : 0)
        .frame(height: 15)
        .background { if ci.isKnown { Capsule().fill(ci.color.opacity(0.13)) } }
        // The note about a host is long and gives way to what the session does.
        .layoutPriority(ci.isKnown ? 1 : 0)
        if let url = ci.link {
            mark.contentShape(Rectangle())
                .onTapGesture { open(url) }
                .accessibilityAddTraits(.isLink)
                .accessibilityHint("Opens the pipeline in the browser")
        } else {
            mark
        }
    }
}

/// The CI of what the session pushed, on a line of its own under the session: the request, the
/// branch and how the pipeline stands. A click opens the pipeline, a click on the request that.
private struct PipelineRow: View {
    let ci: SessionCI
    let isLast: Bool
    let isHovered: Bool
    let open: (URL) -> Void

    var body: some View {
        HStack(spacing: 7) {
            StateMark(state: ci.mark, size: 7)
            Text(ci.label).font(Island.detail).fontWeight(.medium).foregroundStyle(ci.color)
                .layoutPriority(1)
            if let request = ci.request { RequestMark(request: request, open: open) }
            if let branch = ci.request?.branch {
                Text(branch).font(Island.smallCode).foregroundStyle(Island.text3)
            }
            ApprovalsMark(approvals: ci.approvals, isReady: ci.isReadyToMerge)
            Spacer(minLength: 8)
            if isHovered, ci.link != nil {
                Text("Open pipeline").font(Island.small).foregroundStyle(Island.text3).fixedSize()
            }
        }
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        // The branch that ties the pipeline to its session, as for a subagent.
        .background(alignment: .topLeading) {
            let line = Island.branch
            ZStack(alignment: .topLeading) {
                line.frame(width: 1, height: isLast ? Island.subagentHeight / 2 : Island.subagentHeight)
                line.frame(width: 12, height: 1).offset(y: Island.subagentHeight / 2)
            }
            .offset(x: 13.5)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let url = ci.link { open(url) } }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(ci.link == nil ? [] : .isLink)
        .accessibilityHint("Opens the pipeline in the browser")
    }
}

/// A merge request whose session has left the list, or that was merged: what it is, how its CI
/// stands and, after the merge, where its commit is deployed to. A click opens it in the browser,
/// a click on the CI or the deployments its pipeline.
private struct MergeRequestRow: View {
    let request: FollowedMergeRequest
    let isHovered: Bool
    let open: (URL) -> Void
    let remove: () -> Void

    /// What a host handed out is opened only when it is a web address.
    private static func webAddress(_ text: String?) -> URL? {
        guard let url = text.flatMap(URL.init(string:)), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    private var url: URL? { Self.webAddress(request.url) }
    private var pipeline: URL? { Self.webAddress(request.pipelineURL) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        HStack(spacing: 6) {
            Text("!\(request.number)").font(Island.smallCode).foregroundStyle(Island.text3)
                .frame(minWidth: 14, alignment: .leading)
                .layoutPriority(1)
            Text(request.title ?? request.branch ?? "Merge request").font(Island.detail).foregroundStyle(Island.text)
            Text(request.project).font(Island.small).foregroundStyle(Island.text3)
            if request.isMerged { Text("merged").font(Island.small).foregroundStyle(Island.text3).fixedSize() }
            if let ci = request.ci {
                PipelineMark(ci: SessionCI(state: ci, url: request.pipelineURL ?? request.url), open: open)
                    .fixedSize()
            }
            if !request.deployments.isEmpty {
                DeploymentsMark(deployments: request.deployments, pipeline: pipeline, open: open)
            }
            ApprovalsMark(approvals: request.approvals, isReady: request.isReadyToMerge)
            Spacer(minLength: 8)
            if isHovered {
                Text(url == nil ? "No link" : "Open in browser").font(Island.small).foregroundStyle(Island.text3)
                    .fixedSize()
                Text("✕").font(Island.small).foregroundStyle(Island.text2)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: remove)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("Stop following this merge request")
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(maxHeight: .infinity)
        .background {
            if isHovered {
                shape.fill(LinearGradient(colors: Island.rowHover, startPoint: .top, endPoint: .bottom))
                    .overlay(shape.strokeBorder(Color.white.opacity(0.05), lineWidth: 0.5))
            }
        }
        .contentShape(shape)
        .onTapGesture { if let url { open(url) } }
        .padding(.horizontal, 8)
        .animation(Island.quick, value: isHovered)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(url == nil ? [] : .isLink)
        .accessibilityHint("Opens the merge request in the browser")
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

/// Account-wide usage, in one line: both windows with their figure and bar. When they reset and
/// how old the figures are is said on hovering, and in the menu.
private struct UsageFooter: View {
    let limits: LimitsSnapshot

    var body: some View {
        // The clock ticks here so that an expired window does not wait for a payload.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            HStack(spacing: 22) {
                meter("5-hour", limits.fiveHour, now: timeline.date)
                meter("Weekly", limits.sevenDay, now: timeline.date)
            }
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .help(limits.fiveHour == .noData && limits.sevenDay == .noData
                ? LimitText.noDataExplanation : LimitText.freshness(limits))
        }
        .overlay(alignment: .top) { Island.divider.frame(height: 1) }
    }

    private func meter(_ name: String, _ window: LimitWindow, now: Date) -> some View {
        HStack(spacing: 6) {
            Text(name).foregroundStyle(Island.text3)
            Text(LimitText.figure(window))
                .fontWeight(.semibold)
                .monospacedDigit()
                .foregroundStyle(LimitText.color(window))
            GeometryReader { proxy in
                Capsule().fill(Island.barTrack)
                if case .known(let reading) = window {
                    Capsule().fill(LimitText.barColor(reading.usedPercentage))
                        .opacity(reading.isStale ? 0.5 : 1)
                        .frame(width: max(3, proxy.size.width * min(1, reading.usedPercentage / 100)))
                        .animation(Island.ring, value: reading.usedPercentage)
                }
            }
            .frame(height: 3)
        }
        .font(Island.small)
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .help(resets(window, now: now))
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
