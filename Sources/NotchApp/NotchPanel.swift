import AppKit
import SwiftUI

/// The collapsed island at the notch. Display only: it never takes clicks or focus.
@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private let presence: IslandPresence
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel, presence: IslandPresence) {
        self.model = model
        self.presence = presence
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false

        layout()
        panel.orderFrontRegardless()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    /// The built-in display's notch when there is one, otherwise the screen with the menu bar.
    private func layout() {
        guard let screen = NSScreen.island else { return }
        let geometry = NotchGeometry(screen: screen)
        panel.contentView = NSHostingView(
            rootView: CollapsedView(model: model, presence: presence, geometry: geometry))
        panel.setFrame(geometry.collapsedWindowFrame, display: true)
    }
}

extension NSScreen {
    /// The screen the island lives on: the one with a notch, otherwise the first.
    static var island: NSScreen? {
        screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first
    }
}
