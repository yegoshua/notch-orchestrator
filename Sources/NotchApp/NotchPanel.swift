import AppKit
import SwiftUI

/// The collapsed island at the notch. Display only: it never takes clicks or focus.
@MainActor
final class NotchPanelController {
    private let panel: NSPanel
    private let model: AppModel
    private let presence: IslandPresence
    private var screenObservers: [NSObjectProtocol] = []

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
        screenObservers = IslandScreen.observe { [weak self] in self?.layout() }
    }

    private func layout() {
        guard let screen = NSScreen.island else { return }
        let geometry = NotchGeometry(screen: screen)
        panel.contentView = NSHostingView(
            rootView: CollapsedView(model: model, presence: presence, geometry: geometry))
        panel.setFrame(geometry.collapsedWindowFrame, display: true)
    }
}

/// The user's choice of the screen that shows the island.
enum IslandScreen {
    static let changed = Notification.Name("IslandScreenChanged")

    /// A display by the identifier that stays with it across reconnections, and its name for the
    /// time it is not connected. Nil leaves the choice to the app.
    static var chosen: (id: String, name: String)? {
        get {
            let defaults = UserDefaults.standard
            guard let id = defaults.string(forKey: "islandScreenID"), !id.isEmpty else { return nil }
            return (id, defaults.string(forKey: "islandScreenName") ?? "Display")
        }
        set {
            UserDefaults.standard.set(newValue?.id, forKey: "islandScreenID")
            UserDefaults.standard.set(newValue?.name, forKey: "islandScreenName")
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// Runs `handler` whenever the island may have to move: the screens changed, or the choice did.
    @MainActor
    static func observe(_ handler: @escaping @MainActor () -> Void) -> [NSObjectProtocol] {
        [NSApplication.didChangeScreenParametersNotification, changed].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                Task { @MainActor in handler() }
            }
        }
    }
}

extension NSScreen {
    /// The screen the island lives on: the one the user chose while it is connected; otherwise
    /// the one with a notch; otherwise, as with the lid closed, the one with the menu bar.
    static var island: NSScreen? {
        if let chosen = IslandScreen.chosen, let screen = screens.first(where: { $0.displayID == chosen.id }) {
            return screen
        }
        return screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? screens.first
    }

    /// What identifies the display across reconnections and restarts.
    var displayID: String? {
        guard let number = deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number)?.takeRetainedValue()
        else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
