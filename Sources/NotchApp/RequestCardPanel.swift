import AppKit
import Carbon.HIToolbox
import Combine
import SessionCore
import SwiftUI

/// The card that drops out of the notch while a session waits for the user and the core raised
/// its request: the first of those, with the next one taking its place once it is answered. It
/// goes back into the notch as soon as nothing is raised, answered or not.
///
/// It appears without taking focus from the app in front. Its buttons work on the first click,
/// its window becomes key only when the user clicks into the text field, and Allow and Deny have
/// global shortcuts that exist only while a permission card is showing.
@MainActor
final class RequestCardController {
    /// A card that has only just appeared ignores decisions for this long: a key or click aimed
    /// at the request before it must not land on one the user has not seen yet.
    /// Longer than a double click, so the second click of one cannot answer the next card, whose
    /// button sits in the same place.
    private static let settleDelay: TimeInterval = max(0.6, NSEvent.doubleClickInterval + 0.1)

    private let panel: NSPanel
    private let model: AppModel
    private let presence: IslandPresence
    private let stage = IslandStage()
    private let sizer = IslandWindowSizer()
    private let draft = RequestCardDraft()
    /// Set while the card returns into the notch; its window goes when that is done.
    private var closing: DispatchWorkItem?
    private var queueChanges: AnyCancellable?
    private var screenObservers: [NSObjectProtocol] = []
    private var shown: PendingRequest?
    private var shownSince = Date.distantPast
    private var allowHotkey: GlobalHotkey?
    private var denyHotkey: GlobalHotkey?

    init(model: AppModel, presence: IslandPresence) {
        self.model = model
        self.presence = presence
        panel = CardPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The island draws its own shadow, which follows it as it grows.
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)

        stage.onOpenSizeChange = { [weak self] in self?.layout() }
        queueChanges = model.$snapshot.map(\.raised).removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] requests in self?.show(requests) }
        // The island is drawn for one screen's notch: on another it is laid out anew.
        screenObservers = IslandScreen.observe { [weak self] in
            guard let self else { return }
            self.show(self.model.snapshot.raised)
        }
    }

    private func show(_ requests: [PendingRequest]) {
        guard let head = requests.first, let screen = NSScreen.island else {
            hide()
            return
        }
        // A card caught on its way out gave up its shortcuts already.
        let wasClosing = closing != nil
        closing?.cancel()
        closing = nil
        if head.id != shown?.id || wasClosing {
            shownSince = Date()
            draft.reset()
            registerHotkeys(for: head)
        }
        shown = head
        let id = head.id
        let card = RequestCardView(
            request: head, next: requests.dropFirst().first, moreCount: requests.count - 1,
            allowShortcut: allowHotkey == nil ? nil : Shortcut.allow.title,
            denyShortcut: denyHotkey == nil ? nil : Shortcut.deny.title,
            draft: draft,
            decide: { [weak self] decision in self?.decide(decision, on: id) },
            openInSession: { [weak self] in self?.openInSession(id) })
        let geometry = NotchGeometry(screen: screen)
        let content = AnyView(IslandSurface(
            model: model, stage: stage, geometry: geometry, width: Island.cardWidth, maxHeight: Island.cardMaxHeight
        ) {
            ZStack(alignment: .top) {
                // A new identity per request, so nothing chosen for one card carries over to the
                // next, while the same card keeps what was chosen when the queue behind it changes.
                // The answered card leaves upward and the next one rises into its place.
                card.id(id).transition(.asymmetric(
                    insertion: .offset(y: 18).combined(with: .opacity),
                    removal: .offset(y: -12).combined(with: .opacity)))
            }
            .animation(Island.content, value: id)
        })
        if let hosting = panel.contentView as? FirstClickHostingView {
            hosting.rootView = content
        } else {
            let hosting = FirstClickHostingView(rootView: content)
            // The window has the size it is given; left to itself the hosting view would resize it.
            hosting.sizingOptions = []
            panel.contentView = hosting
        }
        layout()
        presence.cardIsOpen = true
        // Shown, never activated: the app in front keeps the keyboard.
        panel.orderFrontRegardless()
        if !stage.isOpen {
            // Once the collapsed shape is on screen, so that there is something to grow from.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.closing == nil, self.shown != nil else { return }
                self.stage.isOpen = true
            }
        }
    }

    /// The card returns into the notch before its window goes.
    private func hide() {
        guard shown != nil, closing == nil else { return }
        allowHotkey = nil
        denyHotkey = nil
        stage.isOpen = false
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.closing = nil
                self.shown = nil
                self.draft.reset()
                self.panel.orderOut(nil)
                self.panel.contentView = nil
                self.presence.cardIsOpen = false
            }
        }
        closing = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Island.closeDuration, execute: work)
    }

    private func decide(_ decision: Decision, on requestID: String) {
        guard isAnswerable(requestID) else { return }
        // A long command is allowed only once all of it has been shown, by key as much as by click.
        if decision == .allow, let shown, !RequestCardView.isArmed(shown, draft: draft) { return }
        model.decide(decision, on: requestID)
    }

    /// The card of this request is up, has been for long enough to be read, and is not leaving.
    private func isAnswerable(_ requestID: String) -> Bool {
        shown?.id == requestID && closing == nil && Date().timeIntervalSince(shownSince) >= Self.settleDelay
    }

    /// Takes the user to the asking session, where its own dialog is waiting, and stops asking here.
    private func openInSession(_ requestID: String) {
        guard let shown, isAnswerable(requestID) else { return }
        SessionJump.jump(
            to: shown.location, cwd: model.snapshot.sessions.first { $0.id == shown.sessionID }?.cwd)
        model.decide(.handBack, on: requestID)
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
            // What was typed counts only while the field for it is open.
            self.decide(.deny(explanation: self.draft.isExplaining ? self.draft.explanation : nil), on: id)
        }
    }

    private enum Shortcut {
        static let modifiers = UInt32(controlKey | optionKey)
        static let allow = (title: "⌃⌥Y", keyCode: UInt32(kVK_ANSI_Y))
        static let deny = (title: "⌃⌥X", keyCode: UInt32(kVK_ANSI_X))
    }

    // MARK: Placement

    /// Hangs from the top edge, centred on the notch, and follows the card as it grows, so that
    /// nothing invisible is left lying over other windows.
    private func layout() {
        guard shown != nil, let screen = NSScreen.island else { return }
        let size = stage.openSize == .zero ? CGSize(width: Island.cardWidth, height: Island.cardMaxHeight) : stage.openSize
        sizer.fit(panel, to: size, geometry: NotchGeometry(screen: screen), on: screen.frame)
    }
}

/// A borderless panel cannot become key unless it says so, and the text field needs a key window.
/// With `becomesKeyOnlyIfNeeded` it does so only when the user clicks into the field.
private final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
