import AppKit
import SwiftUI

/// The overlay at the notch. Display only: it never takes clicks or focus.
@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private var screenObserver: NSObjectProtocol?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
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
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.screens.first
        else { return }
        let geometry = NotchGeometry(screen: screen)
        panel.contentView = NSHostingView(rootView: CollapsedView(model: model, geometry: geometry))
        panel.setFrame(geometry.frame, display: true)
    }
}
