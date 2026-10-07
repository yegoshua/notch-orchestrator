import AppKit
import SessionCore
import SwiftUI

/// What the user has typed into the card. It lives outside the view so that the keyboard shortcut
/// for Deny can carry it too.
@MainActor
final class RequestCardDraft: ObservableObject {
    @Published var explanation = ""
}

/// The request at the head of the queue: who asks, for what, and the ways to answer.
struct RequestCardView: View {
    let request: PendingRequest
    /// Requests queued behind this one.
    let moreCount: Int
    /// Room to leave at the top for the notch itself.
    let topInset: CGFloat
    /// The global shortcuts, when the system granted them.
    let allowShortcut: String?
    let denyShortcut: String?
    @ObservedObject var draft: RequestCardDraft
    let decide: (Decision) -> Void
    /// Reports the height the card needs, so its window can follow.
    let onHeight: (CGFloat) -> Void

    /// The labels chosen so far, per question.
    @State private var chosen: [Int: [String]] = [:]

    static let width: CGFloat = 460
    private static let scrollHeight: CGFloat = 132
    static let waitingColor = Color(red: 1.0, green: 0.82, blue: 0.25)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Color.clear.frame(height: topInset)
            header
            if request.questions.isEmpty { permission } else { questions }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear.preference(key: CardHeight.self, value: proxy.size.height)
        })
        .onPreferenceChange(CardHeight.self, perform: onHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16).fill(.black))
    }

    // MARK: Who asks

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: request.questions.isEmpty ? "hand.raised.fill" : "ellipsis.bubble.fill")
                .font(.system(size: 11))
                .foregroundStyle(Self.waitingColor)
            Text(request.project ?? "Unknown project")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(white: 0.95))
                .layoutPriority(1)
            if let title = request.sessionTitle {
                Text(title).font(.system(size: 12)).foregroundStyle(Color(white: 0.6))
            }
            Spacer(minLength: 8)
            if moreCount > 0 {
                Text("+\(moreCount) more")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Self.waitingColor)
                    .layoutPriority(1)
                    .accessibilityLabel("\(moreCount) more requests waiting")
            }
        }
        .lineLimit(1)
        .truncationMode(.tail)
    }

    // MARK: Permission request

    private var permission: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Wants to use \(request.toolName)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color(white: 0.85))
            if !request.detail.isEmpty {
                scrollable {
                    Text(request.detail)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Color(white: 0.95))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let excerpt = request.excerpt {
                scrollable {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(excerpt.split(separator: "\n", omittingEmptySubsequences: false).enumerated()), id: \.offset) { _, line in
                            Text(line.isEmpty ? " " : String(line))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Self.excerptColor(line))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 8) {
                Button { decide(.allow) } label: { label("Allow", shortcut: allowShortcut) }
                    .buttonStyle(CardButtonStyle(kind: .allow))
                Button { decide(.deny(explanation: draft.explanation)) } label: { label("Deny", shortcut: denyShortcut) }
                    .buttonStyle(CardButtonStyle(kind: .deny))
                Spacer(minLength: 0)
                Button("Hand back") { decide(.handBack) }
                    .buttonStyle(CardButtonStyle(kind: .plain))
                    .help("Leave it to the session's own dialog")
            }
            HStack(spacing: 8) {
                // Return in an empty field does nothing: denying takes a deliberate click or shortcut.
                ExplanationField(text: $draft.explanation) {
                    if !hasNoExplanation { decide(.deny(explanation: draft.explanation)) }
                }
                    .frame(height: 18)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
                Button("Deny with explanation") { decide(.deny(explanation: draft.explanation)) }
                    .buttonStyle(CardButtonStyle(kind: .plain))
                    .disabled(hasNoExplanation)
            }
        }
    }

    private var hasNoExplanation: Bool {
        draft.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func label(_ title: String, shortcut: String?) -> some View {
        HStack(spacing: 6) {
            Text(title)
            if let shortcut {
                Text(shortcut).font(.system(size: 10, weight: .medium)).opacity(0.7)
            }
        }
    }

    /// As tall as its content up to a limit, then scrolling: a long command is never cut off.
    private func scrollable(@ViewBuilder _ content: () -> some View) -> some View {
        ScrollView(.vertical, showsIndicators: true) { content().padding(8) }
            .frame(maxHeight: Self.scrollHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.13)))
    }

    private static func excerptColor(_ line: Substring) -> Color {
        if line.hasPrefix("+") { return Color(red: 0.45, green: 0.85, blue: 0.55) }
        if line.hasPrefix("-") { return Color(red: 1.0, green: 0.50, blue: 0.47) }
        return Color(white: 0.6)
    }

    // MARK: Question

    private var questions: some View {
        VStack(alignment: .leading, spacing: 9) {
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(request.questions.enumerated()), id: \.offset) { index, question in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(question.text)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color(white: 0.95))
                                .fixedSize(horizontal: false, vertical: true)
                            if question.allowsMultiple {
                                Text("Choose one or more").font(.system(size: 10)).foregroundStyle(Color(white: 0.55))
                            }
                            ForEach(question.options, id: \.label) { option in
                                Button { choose(option.label, for: index) } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(option.label).font(.system(size: 12, weight: .medium))
                                        if let description = option.description, !description.isEmpty {
                                            Text(description).font(.system(size: 11)).opacity(0.65)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(CardButtonStyle(
                                    kind: chosen[index, default: []].contains(option.label) ? .chosen : .plain))
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if !answersAtOnce {
                    Button("Submit") { decide(.answer(answers)) }
                        .buttonStyle(CardButtonStyle(kind: .allow))
                        .disabled(!isComplete)
                }
                Spacer(minLength: 0)
                Button("Hand back") { decide(.handBack) }
                    .buttonStyle(CardButtonStyle(kind: .plain))
                    .help("Leave it to the session's own dialog")
            }
            Text("To answer in your own words, type the answer in the session.")
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.55))
        }
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

private struct CardHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct CardButtonStyle: ButtonStyle {
    enum Kind { case allow, deny, plain, chosen }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1))
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.7 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 6))
    }

    private var foreground: Color {
        switch kind {
        case .allow: .black
        case .deny, .plain, .chosen: Color(white: 0.95)
        }
    }

    private var background: Color {
        switch kind {
        case .allow: Color(red: 0.45, green: 0.85, blue: 0.55)
        case .deny: Color(red: 0.55, green: 0.17, blue: 0.16)
        case .plain: Color(white: 0.18)
        case .chosen: Color(red: 0.16, green: 0.30, blue: 0.52)
        }
    }

    private var border: Color {
        kind == .chosen ? Color(red: 0.45, green: 0.68, blue: 1.0) : .clear
    }
}

/// An AppKit text field: it is what tells a panel that never takes focus by itself to become key
/// when, and only when, the user clicks into it.
private struct ExplanationField: NSViewRepresentable {
    @Binding var text: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.delegate = context.coordinator
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 12)
        field.textColor = NSColor(white: 0.95, alpha: 1)
        field.placeholderAttributedString = NSAttributedString(
            string: "Why not? The agent is told (optional)",
            attributes: [.foregroundColor: NSColor(white: 0.5, alpha: 1), .font: NSFont.systemFont(ofSize: 12)])
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.setAccessibilityLabel("Explanation for denying")
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
            guard selector == #selector(NSResponder.insertNewline(_:)) else { return false }
            parent.text = control.stringValue
            parent.onSubmit()
            return true
        }
    }
}
