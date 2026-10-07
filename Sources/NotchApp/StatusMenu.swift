import AppKit

/// The menu bar item: connection state and the two connection actions.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
        super.init()
        item.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "Notch Orchestrator")
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let status: String
        switch model.connectionStatus {
        case .connected: status = "Connected to Claude Code"
        case .notConnected: status = "Not connected to Claude Code"
        case .failed(let message): status = message
        }
        menu.addItem(withTitle: status, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(.separator())
        addLimits(to: menu)
        menu.addItem(.separator())
        add("Repair Connection", #selector(repair), to: menu)
        add("Remove Completely", #selector(remove), to: menu)
        menu.addItem(.separator())

        let liveness = NSMenuItem(title: "Keep Finished Sessions For", action: nil, keyEquivalent: "")
        liveness.submenu = NSMenu()
        for minutes in [1, 5, 10, 30, 60] {
            let choice = add("\(minutes) min", #selector(setLiveness(_:)), to: liveness.submenu!)
            choice.tag = minutes
            choice.state = model.livenessMinutes == minutes ? .on : .off
        }
        menu.addItem(liveness)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    /// Usage limits in words: the ring has no room to explain itself.
    private func addLimits(to menu: NSMenu) {
        let limits = model.limits
        let now = Date()
        var lines = [
            LimitText.line("5-hour limit", limits.fiveHour, now: now),
            LimitText.line("Weekly limit", limits.sevenDay, now: now),
        ]
        if limits.fiveHour == .noData && limits.sevenDay == .noData {
            lines = ["Usage limits: no data yet", LimitText.noDataExplanation]
        }
        for line in lines {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func repair() { model.repairConnection() }
    @objc private func remove() { model.removeConnection() }
    @objc private func setLiveness(_ sender: NSMenuItem) { model.livenessMinutes = sender.tag }
}
