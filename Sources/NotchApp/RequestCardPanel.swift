import AppKit
import Carbon.HIToolbox
import Combine
import SessionCore
import SwiftUI

/// The card that drops out of the notch while a session waits for the user: the request at the
/// head of the queue, with the next one taking its place once it is answered.
///
/// It appears without taking focus from the app in front. Its buttons work on the first click,
/// its window becomes key only when the user clicks into the text field, and Allow and Deny have
/// global shortcuts that exist only while a permission card is showing.
@MainActor
final class RequestCardController {
    /// A card that has only just appeared ignores decisions for this long: a key or click aimed
    /// at the request before it must not land on one the user has not seen yet.
    private static let settleDelay: TimeInterval = 0.4

    private let panel: NSPanel
    private let model: AppModel
    private let draft = RequestCardDraft()
    private var queueChanges: AnyCancellable?
    private var screenObserver: NSObjectProtocol?
    private var shown: PendingRequest?
    private var shownSince = Date.distantPast
    private var contentHeight: CGFloat = 0
    private var allowHotkey: GlobalHotkey?
    private var denyHotkey: GlobalHotkey?

    init(model: AppModel) {
        self.model = model
        panel = CardPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)

        queueChanges = model.$snapshot.map(\.requests).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in self?.show(requests) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    private func show(_ requests: [PendingRequest]) {
        guard let head = requests.first, let screen = Self.screen else {
            hide()
            return
        }
        if head.id != shown?.id {
            shownSince = Date()
            draft.explanation = ""
            registerHotkeys(for: head)
        }
        shown = head
        let id = head.id
        let view = RequestCardView(
            request: head, moreCount: requests.count - 1, topInset: NotchGeometry(screen: screen).frame.height,
            allowShortcut: allowHotkey == nil ? nil : Shortcut.allow.title,
            denyShortcut: denyHotkey == nil ? nil : Shortcut.deny.title,
            draft: draft,
            decide: { [weak self] decision in self?.decide(decision, on: id) },
            onHeight: { [weak self] height in
                guard let self, self.shown?.id == id, height > 0, height != self.contentHeight else { return }
                self.contentHeight = height
                self.layout()
            })
        // A new identity per request, so nothing chosen for one card carries over to the next,
        // while the same card keeps what was chosen when the queue behind it changes.
        let content = AnyView(view.id(id))
        if let hosting = panel.contentView as? FirstClickHostingView {
            hosting.rootView = content
        } else {
            let hosting = FirstClickHostingView(rootView: content)
            panel.contentView = hosting
            contentHeight = hosting.fittingSize.height
        }
        layout()
        // Shown, never activated: the app in front keeps the keyboard.
        panel.orderFrontRegardless()
    }

    private func hide() {
        shown = nil
        allowHotkey = nil
        denyHotkey = nil
        draft.explanation = ""
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func decide(_ decision: Decision, on requestID: String) {
        guard shown?.id == requestID, Date().timeIntervalSince(shownSince) >= Self.settleDelay else { return }
        model.decide(decision, on: requestID)
    }

    /// Only a permission request can be allowed or denied by a key; a question needs a choice.
    /// The shortcuts are taken from the system only for as long as such a card is showing.
    private func registerHotkeys(for request: PendingRequest) {
        allowHotkey = nil
        denyHotkey = nil
        guard request.questions.isEmpty else { return }
        let id = request.id
        allowHotkey = GlobalHotkey(keyCode: Shortcut.allow.keyCode, modifiers: Shortcut.modifiers) { [weak self] in
            self?.decide(.allow, on: id)
        }
        denyHotkey = GlobalHotkey(keyCode: Shortcut.deny.keyCode, modifiers: Shortcut.modifiers) { [weak self] in
            guard let self else { return }
            self.decide(.deny(explanation: self.draft.explanation), on: id)
        }
    }

    private enum Shortcut {
        static let modifiers = UInt32(controlKey | optionKey)
        static let allow = (title: "⌃⌥Y", keyCode: UInt32(kVK_ANSI_Y))
        static let deny = (title: "⌃⌥X", keyCode: UInt32(kVK_ANSI_X))
    }

    // MARK: Placement

    /// Same choice as the collapsed overlay: the notch when there is one, otherwise the first screen.
    private static var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    /// Hangs from the top edge, centred on the notch, as tall as the card needs.
    private func layout() {
        guard shown != nil, let screen = Self.screen else { return }
        let notch = NotchGeometry(screen: screen).frame
        let width = min(RequestCardView.width, screen.frame.width - 40)
        let height = min(max(contentHeight, notch.height + 60), screen.frame.height * 0.8)
        panel.setFrame(
            CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height),
            display: true)
    }
}

/// A borderless panel cannot become key unless it says so, and the text field needs a key window.
/// With `becomesKeyOnlyIfNeeded` it does so only when the user clicks into the field.
private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Buttons in a window that is not key answer the first click instead of swallowing it.
private final class FirstClickHostingView: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
