import AppKit
import SessionCore

/// The menu bar item: connection state, usage limits and the way to the settings window.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let updater: AppUpdater
    private let settings: SettingsWindowController

    init(model: AppModel, updater: AppUpdater, settings: SettingsWindowController) {
        self.model = model
        self.updater = updater
        self.settings = settings
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
        addPipelineAccess(to: menu)
        menu.addItem(.separator())
        if model.connectionStatus != .connected { add("Repair Connection", #selector(repair), to: menu) }
        add("Settings…", #selector(openSettings), to: menu).keyEquivalent = ","
        menu.addItem(.separator())
        if let version = updater.version {
            menu.addItem(withTitle: "Version \(version)", action: nil, keyEquivalent: "").isEnabled = false
        }
        if updater.isAvailable { add("Check for Updates…", #selector(checkForUpdates), to: menu) }
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
        if model.connectionStatus == .connected && !model.forwardsUsageLimits {
            lines.append("Usage limits unavailable: the statusLine setting has a form the app cannot wrap")
        }
        for line in lines {
            menu.addItem(withTitle: line, action: nil, keyEquivalent: "").isEnabled = false
        }
    }

    /// The app holds no tokens: a host it cannot ask is fixed by signing in with the host's own tool.
    private func addPipelineAccess(to menu: NSMenu) {
        let hosts = model.unreachableHosts
        guard !hosts.isEmpty else { return }
        menu.addItem(.separator())
        for (host, command) in hosts {
            menu.addItem(withTitle: "CI: no access to \(host)", action: nil, keyEquivalent: "").isEnabled = false
            let copy = add("Copy Sign-In Command: \(command)", #selector(copyCommand(_:)), to: menu)
            copy.representedObject = command
        }
        if hosts.contains(where: { GitProvider(host: $0.host) == .gitLab }) {
            add("Set Up GitLab…", #selector(setUpGitLab), to: menu)
        }
    }

    @discardableResult
    private func add(_ title: String, _ action: Selector, to menu: NSMenu) -> NSMenuItem {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func repair() { model.repairConnection() }
    @objc private func openSettings() { settings.show() }
    @objc private func setUpGitLab() { settings.show(.gitLab) }

    @objc private func copyCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }
}
