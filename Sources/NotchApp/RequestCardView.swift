import AppKit
import SessionCore
import SwiftUI

/// What the user has done with the card so far. It lives outside the view so that the keyboard
/// shortcuts can act on it too.
@MainActor
final class RequestCardDraft: ObservableObject {
    @Published var explanation = ""
    /// The card shows the field for explaining a denial instead of its actions.
    @Published var isExplaining = false
    /// The user opened a long command to read all of it.
    @Published var isUnfolded = false
    /// The end of an opened long command has been on screen. Until then it cannot be allowed.
    @Published var hasReachedEnd = false

    func reset() {
        explanation = ""
        isExplaining = false
        isUnfolded = false
        hasReachedEnd = false
    }
}

/// The request at the head of the queue: who asks, for what, and the ways to answer.
struct RequestCardView: View {
    let request: PendingRequest
    /// The request that takes this one's place once it is answered.
    let next: PendingRequest?
    /// Requests queued behind this one.
    let moreCount: Int
    /// The global shortcuts, when the system granted them.
    let allowShortcut: String?
    let denyShortcut: String?
    @ObservedObject var draft: RequestCardDraft
    let decide: (Decision) -> Void
    /// Takes the user to the session and leaves the request to the session's own dialog.
    let openInSession: () -> Void

    /// The labels chosen so far, per question.
    @State private var chosen: [Int: [String]] = [:]
    @State private var hoveredOption: String?

    /// A command longer than this is shown cut, and has to be opened before it can be allowed.
    private static let foldedLines = 4
    private static let foldedCharacters = 240

    /// Whether the command is too long to be taken in at a glance.
    static func isLong(_ request: PendingRequest) -> Bool {
        request.questions.isEmpty && request.excerpt == nil
            && (request.detail.count > foldedCharacters
                || request.detail.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count > foldedLines)
    }

    /// Allow only works once everything that is being allowed has been on screen: at once for a
    /// short command, for a long one after it was opened and, where it scrolls, read to its end.
    static func isArmed(_ request: PendingRequest, draft: RequestCardDraft) -> Bool {
        !isLong(request) || draft.hasReachedEnd
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer().frame(height: 12)
                if request.questions.isEmpty { permission } else { questions }
            }
            .padding(.top, 10)
            .padding(.horizontal, Island.openPadding)
            .padding(.bottom, 14)
            if let next { queue(next) }
        }
    }

    // MARK: Who asks

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    StateMark(state: .waitingForPermission)
                    Text(request.sessionTitle ?? request.project ?? "Untitled session")
                        .font(Island.cardTitle)
                        .foregroundStyle(Island.text)
                }
                .frame(height: 18)
                // The clock ticks here so that the age of the request moves while it waits.
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    Text(meta(now: timeline.date)).font(Island.small).foregroundStyle(Island.text2)
                }
                .padding(.leading, 15)
                .frame(height: 15)
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                if moreCount > 0 {
                    Text("1 of \(moreCount + 1)")
                        .font(Island.label.monospacedDigit())
                        .foregroundStyle(Island.waiting)
                        .accessibilityLabel("\(moreCount) more request\(moreCount == 1 ? "" : "s") waiting")
                }
                Chip(text: request.questions.isEmpty ? request.toolName : "Question")
            }
            .frame(height: 18)
            .fixedSize()
        }
    }

    private func meta(now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(request.arrivedAt)))
        let age = seconds < 5 ? "just now" : seconds < 60 ? "\(seconds)s ago" : "\(seconds / 60)m ago"
        return [request.sessionTitle == nil ? nil : request.project, request.location.originDescription, age]
            .compactMap { $0 }.joined(separator: " · ")
    }

    // MARK: Permission request

    private var permission: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(Self.ask(request)).foregroundStyle(Island.text).layoutPriority(1)
                if let summary = request.summary {
                    Text("·").foregroundStyle(Island.text4)
                    Text("\u{201C}\(summary)\u{201D}").foregroundStyle(Island.text2)
                }
            }
            .font(Island.body)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: 16)
            Spacer().frame(height: 7)
            if let excerpt = request.excerpt {
                diff(excerpt)
            } else if !request.detail.isEmpty {
                command
            }
            Spacer().frame(height: 14)
            if draft.isExplaining {
                explain.transition(.offset(y: 10).combined(with: .opacity))
            } else {
                actions.transition(.offset(y: -6).combined(with: .opacity))
            }
        }
        .animation(Island.content, value: draft.isExplaining)
        .animation(Island.content, value: draft.isUnfolded)
        .animation(Island.quick, value: draft.hasReachedEnd)
    }

    private static func ask(_ request: PendingRequest) -> String {
        switch request.toolName {
        case "Bash": "Run a shell command"
        case "Edit", "MultiEdit", "NotebookEdit": "Edit a file"
        case "Write": "Write a file"
        case "Read": "Read a file"
        case "WebFetch": "Fetch a web page"
        case "WebSearch": "Search the web"
        default: "Use \(request.toolName)"
        }
    }

    private var isLong: Bool { Self.isLong(request) }

    /// The command in full, in monospace. A long one shows its first lines until it is opened;
    /// opened, it scrolls rather than push the card off the screen.
    @ViewBuilder
    private var command: some View {
        let isShell = request.toolName == "Bash"
        let isFolded = isLong && !draft.isUnfolded
        Well {
            ScrollView(.vertical, showsIndicators: !isFolded) {
              // Lazy, so that the mark under the command appears only when it scrolls into view.
              LazyVStack(spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    if isShell { Text("$").foregroundStyle(Island.text4).frame(width: 14, alignment: .leading) }
                    Text(request.detail)
                        .foregroundStyle(Island.text)
                        .lineLimit(isFolded ? Self.foldedLines : nil)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Island.code)
                .lineSpacing(Island.codeLineSpacing)
                .padding(.top, 9)
                .padding(.horizontal, 12)
                Color.clear.frame(height: 9).onAppear { if !isFolded { draft.hasReachedEnd = true } }
                    .id(isFolded)
              }
            }
            .scrollDisabled(isFolded)
            .frame(maxHeight: isFolded ? CGFloat(Self.foldedLines) * Island.codeLineHeight + 18 : 10 * Island.codeLineHeight + 18)
            .fixedSize(horizontal: false, vertical: true)
            .overlay(alignment: .bottom) {
                if isFolded {
                    LinearGradient(colors: [Island.wellRaised.opacity(0), Island.wellRaised], startPoint: .top, endPoint: .bottom)
                        .frame(height: 30)
                        .allowsHitTesting(false)
                }
            }
        }
        if isLong {
            HStack {
                Text("\(request.detail.count) characters · " + (isFolded
                    ? "Allow unlocks once the whole command is shown"
                    : draft.hasReachedEnd ? "shown in full" : "scroll to the end to unlock Allow"))
                    .foregroundStyle(Island.text3)
                Spacer(minLength: 8)
                Text(isFolded ? "Show all" : "Collapse")
                    .foregroundStyle(Island.text)
                    .contentShape(Rectangle())
                    .onTapGesture { draft.isUnfolded.toggle() }
                    .accessibilityAddTraits(.isButton)
            }
            .font(Island.small)
            .lineLimit(1)
            .frame(height: 23, alignment: .bottom)
        }
    }

    /// The file and the first lines of the change, removed and added lines told apart by their
    /// mark as well as their colour.
    private func diff(_ excerpt: String) -> some View {
        let lines = excerpt.split(separator: "\n", omittingEmptySubsequences: false)
        let added = lines.filter { $0.hasPrefix("+") }.count, removed = lines.filter { $0.hasPrefix("-") }.count
        return Well {
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Text(request.detail).font(Island.code).foregroundStyle(Island.text)
                        .truncationMode(.head)
                    Spacer(minLength: 8)
                    Text("+\(added)").foregroundStyle(Island.finished)
                    Text("\u{2212}\(removed)").foregroundStyle(Island.failed)
                }
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 30)
                .overlay(alignment: .bottom) { Island.divider.frame(height: 1) }
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            diffLine(line)
                        }
                    }
                    .padding(.vertical, 6)
                    .frame(minWidth: Island.cardWidth - 2 * Island.openPadding, alignment: .leading)
                }
            }
        }
    }

    private func diffLine(_ line: Substring) -> some View {
        let isAdded = line.hasPrefix("+"), isRemoved = line.hasPrefix("-")
        let tint = isAdded ? Island.finished : isRemoved ? Island.failed : Island.text5
        return HStack(spacing: 0) {
            Text(isAdded ? "+" : isRemoved ? "\u{2212}" : "").foregroundStyle(tint).frame(width: 22)
            Text(isAdded || isRemoved ? String(line.dropFirst(2)) : String(line))
                .foregroundStyle(isAdded || isRemoved ? Island.text : Island.text2)
            Spacer(minLength: 10)
        }
        .font(Island.code)
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: Island.codeLineHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isAdded || isRemoved ? tint.opacity(0.13) : .clear)
    }

    /// Allow and Deny look alike on purpose: nothing here invites approving without reading.
    private var actions: some View {
        HStack(spacing: 8) {
            openButton
            Spacer(minLength: 0)
            Button { draft.isExplaining = true } label: { ButtonLabel(title: "Deny with explanation") }
                .buttonStyle(IslandButtonStyle())
            Button { decide(.deny(explanation: nil)) } label: { ButtonLabel(title: "Deny", key: denyShortcut) }
                .buttonStyle(IslandButtonStyle())
            Button { decide(.allow) } label: { ButtonLabel(title: "Allow", key: allowShortcut) }
                .buttonStyle(IslandButtonStyle())
                .disabled(!Self.isArmed(request, draft: draft))
        }
        .frame(height: Island.buttonHeight)
    }

    private var explain: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Deny and tell the agent why").font(Island.small).foregroundStyle(Island.text2).frame(height: 15)
            Spacer().frame(height: 6)
            ExplanationField(
                text: $draft.explanation,
                onSubmit: { if !hasNoExplanation { decide(.deny(explanation: draft.explanation)) } },
                onCancel: { draft.isExplaining = false })
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous).fill(Island.field))
                .overlay(RoundedRectangle(cornerRadius: Island.wellRadius, style: .continuous).strokeBorder(Island.text5))
                .background(RoundedRectangle(cornerRadius: Island.wellRadius + 3, style: .continuous)
                    .fill(Island.text.opacity(0.07)).padding(-3))
            Spacer().frame(height: 10)
            HStack(spacing: 8) {
                Text("Sent to the session as the reason").font(Island.small).foregroundStyle(Island.text3)
                Spacer(minLength: 0)
                Button { draft.isExplaining = false } label: { ButtonLabel(title: "Cancel", key: "esc") }
                    .buttonStyle(IslandButtonStyle())
                // Return in an empty field does nothing: denying takes something to send.
                Button { decide(.deny(explanation: draft.explanation)) } label: {
                    ButtonLabel(title: "Deny and send", key: "\u{23CE}", onLight: true)
                }
                .buttonStyle(IslandButtonStyle(kind: .primary))
                .disabled(hasNoExplanation)
            }
            .frame(height: Island.buttonHeight)
        }
    }

    private var hasNoExplanation: Bool {
        draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var openButton: some View {
        // The button names where it leads and how close that gets; the request itself is left
        // to the session's own dialog.
        let target = request.location.jumpTarget
        return Button(action: openInSession) {
            HStack(spacing: 7) {
                Text(target?.label ?? "Answer in session")
                if let target { Text(target.reach).font(Island.small).foregroundStyle(Island.text3) }
            }
        }
        .buttonStyle(IslandButtonStyle(kind: .quiet))
        .accessibilityHint(target?.explanation ?? "Leaves the request to the session\u{2019}s own dialog")
    }

    // MARK: Queue

    private func queue(_ next: PendingRequest) -> some View {
        HStack(spacing: 8) {
            Text("Next").font(Island.small).foregroundStyle(Island.text3).frame(width: 32, alignment: .leading)
            StateMark(state: .waitingForPermission)
            Text(next.sessionTitle ?? next.project ?? "Untitled session")
                .font(Island.bodyMedium)
                .foregroundStyle(Island.text)
                .layoutPriority(1)
            Text(Self.short(next) + (moreCount > 1 ? ", and \(moreCount - 1) more" : ""))
                .font(Island.small)
                .foregroundStyle(Island.text2)
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, Island.openPadding)
        .frame(height: 41)
        .overlay(alignment: .top) { Island.divider.frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    private static func short(_ request: PendingRequest) -> String {
        let subject = request.questions.first?.text
            ?? String(request.detail.split(whereSeparator: \.isNewline).first ?? "")
        return [request.sessionTitle == nil ? nil : request.project, request.questions.isEmpty ? request.toolName : "Question", subject]
            .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · ")
    }

    // MARK: Question

    private var questions: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(question.text)
                                .font(.system(size: 13))
                                .lineSpacing(2)
                                .foregroundStyle(Island.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.bottom, 4)
                            if question.allowsMultiple {
                                Text("Choose one or more").font(Island.small).foregroundStyle(Island.text3)
                            }
                            ForEach(Array(question.options.enumerated()), id: \.offset) { number, option in
                                self.option(option, number: number + 1, question: index)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 268)
            .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 14)
            HStack(spacing: 8) {
                openButton
                Spacer(minLength: 0)
                if answersAtOnce {
                    Text("To answer in your own words, reply in the session").font(Island.small).foregroundStyle(Island.text3)
                } else {
                    Button { decide(.answer(answers)) } label: { ButtonLabel(title: "Submit") }
                        .buttonStyle(IslandButtonStyle(kind: .primary))
                        .disabled(!isComplete)
                }
            }
            .frame(height: Island.buttonHeight)
        }
    }

    private func option(_ option: Question.Option, number: Int, question index: Int) -> some View {
        let key = "\(index):\(option.label)"
        let isChosen = chosen[index, default: []].contains(option.label)
        let isLit = hoveredOption == key || isChosen
        let shape = RoundedRectangle(cornerRadius: Island.optionRadius, style: .continuous)
        return HStack(spacing: 11) {
            Keycap(text: isChosen ? "\u{2713}" : "\(number)")
            VStack(alignment: .leading, spacing: 0) {
                Text(option.label).font(Island.listTitle).foregroundStyle(Island.text).frame(height: 17)
                if let description = option.description, !description.isEmpty {
                    Text(description).font(Island.detail).foregroundStyle(Island.text2).frame(height: 16)
                }
            }
            .lineLimit(1)
            .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
        .background {
            if isLit {
                shape.fill(LinearGradient(colors: Island.optionLit, startPoint: .top, endPoint: .bottom))
            } else {
                shape.fill(Island.option)
            }
        }
        .overlay(shape.strokeBorder(isLit ? Color.white.opacity(isChosen ? 0.34 : 0.17) : Island.divider))
        .contentShape(shape)
        .background(HoverArea { inside in
            if inside { hoveredOption = key } else if hoveredOption == key { hoveredOption = nil }
        })
        .animation(Island.quick, value: isLit)
        .onTapGesture { choose(option.label, for: index) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isChosen ? [.isButton, .isSelected] : .isButton)
    }

    /// One question with one choice needs no Submit: picking the option is the answer.
    private var answersAtOnce: Bool {
        request.questions.count == 1 && !request.questions[0].allowsMultiple
    }

    private var answers: [[String]] {
        request.questions.indices.map { index in
            // In the order the options were offered, not the order they were clicked.
            request.questions[index].options.map(\.label).filter { chosen[index, default: []].contains($0) }
        }
    }

    private var isComplete: Bool { answers.allSatisfy { !$0.isEmpty } }

    private func choose(_ label: String, for index: Int) {
        if answersAtOnce {
            decide(.answer([[label]]))
        } else if !request.questions[index].allowsMultiple {
            chosen[index] = [label]
        } else if chosen[index, default: []].contains(label) {
            chosen[index]?.removeAll { $0 == label }
        } else {
            chosen[index, default: []].append(label)
        }
    }
}

/// An AppKit text field: it is what makes a panel that never takes focus by itself become key
/// when, and only when, the user chose to type an explanation.
private struct ExplanationField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = NSColor(white: 0.95, alpha: 1)
        field.placeholderAttributedString = NSAttributedString(
            string: "What should the agent do instead?",
            attributes: [.foregroundColor: NSColor(white: 0.5, alpha: 1), .font: NSFont.systemFont(ofSize: 12)])
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Explanation for denying")
        // The user asked for the field, so the keyboard goes to it without another click.
        DispatchQueue.main.async { [weak field] in
            guard let field, let window = field.window else { return }
            window.makeKey()
            window.makeFirstResponder(field)
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ExplanationField

        init(_ parent: ExplanationField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            if selector == #selector(NSResponder.cancelOperation(_:)) {
                parent.onCancel()
                return true
            }
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }
}
