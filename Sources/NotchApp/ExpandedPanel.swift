import AppKit
import Combine
import SwiftUI

/// The session list that drops out of the notch. Hovering the notch or pressing the global hotkey
/// opens it; the pointer leaving it closes it, and so does Escape or the hotkey when the hotkey
/// opened it. It never takes keyboard focus.
@MainActor
final class ExpandedPanelController {
    private static let openDelay: TimeInterval = 0.12
    private static let closeDelay: TimeInterval = 0.25

    private let panel: NSPanel
    private let model: AppModel
    private var monitors: [Any] = []
    private var observers: [NSObjectProtocol] = []
    private var snapshotChanges: AnyCancellable?
    private var hotkey: GlobalHotkey?
    /// Held only while a list opened by the hotkey is showing, so Escape works everywhere else as usual.
    private var escape: GlobalHotkey?
    private var pending: DispatchWorkItem?
    /// Opened by hotkey with the pointer elsewhere: leaving only counts once the pointer has come in.
    private var pointerHasEntered = false
    /// Closed with the pointer still on the notch: it has to leave before hovering opens the list again.
    private var pointerMustLeaveNotch = false
    /// Our own panel swallows the movement events over it, so while it is open the pointer is polled.
    private var pointerPoll: Timer?

    private var isExpanded: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false

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
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        })
        snapshotChanges = model.$snapshot.receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.isExpanded else { return }
            self.layout()
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
        guard !isExpanded, let screen = Self.screen else { return }
        pointerHasEntered = byPointer
        panel.contentView = NSHostingView(rootView: SessionListView(model: model, topInset: Self.topInset(on: screen)))
        layout()
        panel.orderFrontRegardless()
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

    private func collapse() {
        cancelPending()
        pointerPoll?.invalidate()
        pointerPoll = nil
        pointerMustLeaveNotch = true
        escape = nil
        panel.orderOut(nil)
        panel.contentView = nil
    }

    private func pointerMoved() {
        guard let screen = Self.screen else { return }
        let pointer = NSEvent.mouseLocation
        if isExpanded {
            let inside = panel.frame.insetBy(dx: -6, dy: -6).contains(pointer)
            if inside {
                pointerHasEntered = true
                cancelPending()
            } else if pointerHasEntered, pending == nil {
                schedule(after: Self.closeDelay) { $0.collapse() }
            }
        } else {
            // The pointer has to rest on the notch for a moment; passing over it does nothing.
            let onNotch = NotchGeometry(screen: screen).frame.contains(pointer)
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

    // MARK: Placement

    /// Same choice as the collapsed overlay: the notch when there is one, otherwise the first screen.
    private static var screen: NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
    }

    private static func topInset(on screen: NSScreen) -> CGFloat {
        NotchGeometry(screen: screen).frame.height
    }

    /// Hangs from the top edge, centred on the notch, as tall as its rows up to most of the screen.
    private func layout() {
        guard let screen = Self.screen else { return }
        let notch = NotchGeometry(screen: screen).frame
        let width = min(SessionListView.Metrics.width, screen.frame.width - 40)
        let wanted = SessionListView.Metrics.height(of: model.snapshot.sessions, topInset: notch.height)
        let height = min(wanted, screen.frame.height * 0.6)
        panel.setFrame(
            CGRect(x: notch.midX - width / 2, y: screen.frame.maxY - height, width: width, height: height),
            display: true)
    }
}
