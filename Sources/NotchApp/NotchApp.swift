import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel(config: AppConfig())
    private var panel: NotchPanelController?
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
        panel = NotchPanelController(model: model)
        menu = StatusMenuController(model: model)
    }
}
