import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(config: AppConfig())
    private let presence = IslandPresence()
    private var panel: NotchPanelController?
    private var expandedPanel: ExpandedPanelController?
    private var requestCard: RequestCardController?
    private var transientLine: TransientLineController?
    private var menu: StatusMenuController?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.start()
        panel = NotchPanelController(model: model, presence: presence)
        expandedPanel = ExpandedPanelController(model: model, presence: presence)
        requestCard = RequestCardController(model: model, presence: presence)
        transientLine = TransientLineController(model: model, presence: presence)
        menu = StatusMenuController(model: model)
    }
}
