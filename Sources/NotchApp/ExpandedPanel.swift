import AppKit
import Combine
import SessionCore
import SwiftUI

/// The session list that drops out of the notch. Hovering the notch or pressing the global hotkey
/// opens it; the pointer leaving it closes it, and so does Escape or the hotkey when the hotkey
/// opened it. A click on its band pins it: then it stays until the band is clicked again, or
/// Escape or the hotkey is pressed. It never takes keyboard focus.
@MainActor
final class ExpandedPanelController {
    private static let openDelay: TimeInterval = 0.12
    private static let closeDelay: TimeInterval = 0.25

    private let panel: NSPanel
    private let model: AppModel
    private let presence: IslandPresence
    private let stage = IslandStage()
    private let sizer = IslandWindowSizer()
    /// Open or opening. While the list returns into the notch its window is still there.
    private var isExpanded = false
    private var closing: DispatchWorkItem?
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var snapshotChanges: AnyCancellable?
    private var hotkey: GlobalHotkey?
    /// Held only while a list opened by the hotkey is showing, so Escape works everywhere else as usual.
    private var escape: GlobalHotkey?
    private var pending: DispatchWorkItem?
    /// Pinned open by a click on the band: the pointer leaving no longer closes it.
    private var isPinned = false {
        didSet { stage.isPinned = isPinned }
    }
    /// Opened by hotkey with the pointer elsewhere: leaving only counts once the pointer has come in.
    private var pointerHasEntered = false
    /// Closed with the pointer still on the notch: it has to leave before hovering opens the list again.
    private var pointerMustLeaveNotch = false
    /// Our own panel swallows the movement events over it, so while it is open the pointer is polled.
    private var pointerPoll: Timer?

    init(model: AppModel, presence: IslandPresence) {
        self.model = model
        self.presence = presence
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // The island draws its own shadow, which follows it as it grows.
        panel.hasShadow = false
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.appearance = NSAppearance(named: .darkAqua)

        let moved: (NSEvent) -> Void = { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
        // Mouse movement can be watched system-wide without any permission; keys cannot.
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved], handler: { moved($0); return $0 }) {
            monitors.append(monitor)
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: HotkeySetting.changed, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.registerHotkey() }
        })
        observers += IslandScreen.observe { [weak self] in self?.collapse(animated: false) }
        stage.onOpenSizeChange = { [weak self] in self?.fitWindow() }
        stage.onBandClick = { [weak self] in self?.togglePin() }
        snapshotChanges = model.$snapshot.receive(on: DispatchQueue.main).sink { [weak self] snapshot in
            // A request card takes the place under the notch, at once.
            if !snapshot.raised.isEmpty { self?.collapse(animated: false) }
        }
        registerHotkey()
    }

    private func registerHotkey() {
        hotkey = nil
        let setting = HotkeySetting.current
        guard !setting.isNone else { return }
        hotkey = GlobalHotkey(keyCode: setting.keyCode, modifiers: setting.modifiers) { [weak self] in
            guard let self else { return }
            if self.isExpanded { self.collapse() } else { self.expand(byPointer: false) }
        }
    }

    // MARK: Expanding and collapsing

    private func expand(byPointer: Bool) {
        cancelPending()
        // A request card has the place under the notch, also while it is still leaving. A request
        // that was not raised has no card: the list is where it is found.
        guard !isExpanded, model.snapshot.raised.isEmpty, !presence.cardIsOpen, let screen = NSScreen.island
        else { return }
        isExpanded = true
        pointerHasEntered = byPointer
        presence.listIsOpen = true
        if let closing {
            // Caught on its way back into the notch: it grows again from where it is.
            closing.cancel()
            self.closing = nil
            stage.isOpen = true
        } else {
            let geometry = NotchGeometry(screen: screen)
            let list = IslandSurface(
                model: model, stage: stage, geometry: geometry, width: Island.listWidth, maxHeight: Island.maxHeight
            ) {
                SessionListView(model: model, bandHeight: geometry.frame.height) { [weak self] session in
                    self?.jump(to: session)
                }
            }
            panel.contentView = FirstClickHostingView(rootView: AnyView(list))
            sizer.fit(panel, to: CGSize(width: Island.listWidth, height: Island.maxHeight), geometry: geometry, on: screen.frame)
            panel.orderFrontRegardless()
            // Once the collapsed shape is on screen, so that there is something to grow from.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.isExpanded else { return }
                self.stage.isOpen = true
            }
        }
        // Taking Escape away from the frontmost app is only fair when a key opened the list.
        // Opened by hovering, it closes when the pointer leaves.
        if !byPointer {
            escape = GlobalHotkey(keyCode: HotkeySetting.escapeKeyCode, modifiers: 0) { [weak self] in
                self?.collapse()
            }
        }
        pointerPoll = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pointerMoved() }
        }
    }

    private func togglePin() {
        guard isExpanded else { return }
        if isPinned { return collapse() }
        isPinned = true
        cancelPending()
        // With the pointer free to leave, a key has to be able to close the list.
        if escape == nil {
            escape = GlobalHotkey(keyCode: HotkeySetting.escapeKeyCode, modifiers: 0) { [weak self] in
                self?.collapse()
            }
        }
    }

    /// Animated, the list returns into the notch before its window goes.
    private func collapse(animated: Bool = true) {
        isPinned = false
        cancelPending()
        pointerPoll?.invalidate()
        pointerPoll = nil
        pointerMustLeaveNotch = true
        escape = nil
        if isExpanded {
            isExpanded = false
            stage.isOpen = false
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated { self?.removeWindow() }
            }
            closing = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Island.closeDuration, execute: work)
        }
        if !animated, closing != nil { removeWindow() }
    }

    /// The window follows the list, so that nothing invisible is left lying over other windows.
    private func fitWindow() {
        guard panel.contentView != nil, let screen = NSScreen.island else { return }
        sizer.fit(panel, to: stage.openSize, geometry: NotchGeometry(screen: screen), on: screen.frame)
    }

    private func removeWindow() {
        closing?.cancel()
        closing = nil
        panel.orderOut(nil)
        panel.contentView = nil
        presence.listIsOpen = false
    }

    private func jump(to session: Session) {
        guard session.location.jumpTarget != nil else { return }
        SessionJump.jump(to: session.location, cwd: session.cwd)
        collapse()
    }

    private func pointerMoved() {
        guard let screen = NSScreen.island else { return }
        let pointer = NSEvent.mouseLocation
        let geometry = NotchGeometry(screen: screen)
        if isExpanded {
            // The window is larger than the list; only the list itself counts.
            let inside = geometry.openFrame(ofSize: stage.openSize, on: screen.frame).union(geometry.frame)
                .insetBy(dx: -6, dy: -6).contains(pointer)
            if inside {
                pointerHasEntered = true
                cancelPending()
            } else if pointerHasEntered, !isPinned, pending == nil {
                schedule(after: Self.closeDelay) { $0.collapse() }
            }
        } else {
            // The pointer has to rest on the notch for a moment; passing over it does nothing.
            let onNotch = geometry.hoverFrame(drawn: presence.collapsedSpan).contains(pointer)
            if !onNotch {
                pointerMustLeaveNotch = false
                cancelPending()
            } else if !pointerMustLeaveNotch, pending == nil {
                schedule(after: Self.openDelay) { $0.expand(byPointer: true) }
            }
        }
    }

    private func cancelPending() {
        pending?.cancel()
        pending = nil
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping @MainActor (ExpandedPanelController) -> Void) {
        let work = DispatchWorkItem { [weak self] in
            // Already on the main queue; running here keeps a cancellation from arriving in between.
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = nil
                action(self)
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
}
