import AppKit
import ServiceManagement
import SessionCore

/// The menu bar item: connection state and the two connection actions.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let updater: AppUpdater

    init(model: AppModel, updater: AppUpdater) {
        self.model = model
        self.updater = updater
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
        HotkeyMenu.shared.add(to: menu)
        addInterruptions(to: menu)
        addScreens(to: menu)
        addLoginItem(to: menu)
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
    }

    private static let modes: [(mode: InterruptionMode, title: String)] = [
        (.loud, "Loud: expand and sound for every request and every finished turn"),
        (.smart, "Smart: expand and sound only for a session that is not in front"),
        (.quiet, "Quiet: counters only"),
    ]

    private func addInterruptions(to menu: NSMenu) {
        let interruptions = NSMenuItem(title: "Interruptions", action: nil, keyEquivalent: "")
        interruptions.submenu = NSMenu()
        for (index, choice) in Self.modes.enumerated() {
            let entry = add(choice.title, #selector(setMode(_:)), to: interruptions.submenu!)
            entry.tag = index
            entry.state = model.interruptionMode == choice.mode ? .on : .off
        }
        interruptions.submenu!.addItem(.separator())
        let focus = model.attentionMonitor.canReadFocus
            ? "A Focus silences every mode"
            : "Focus cannot be read, so it is not respected (needs Full Disk Access)"
        interruptions.submenu!.addItem(withTitle: focus, action: nil, keyEquivalent: "").isEnabled = false
        menu.addItem(interruptions)

        let sound = NSMenuItem(title: "Sound", action: nil, keyEquivalent: "")
        sound.submenu = NSMenu()
        add("None", #selector(setSound(_:)), to: sound.submenu!).state = InterruptionSound.current == nil ? .on : .off
        sound.submenu!.addItem(.separator())
        for name in InterruptionSound.names {
            let entry = add(name, #selector(setSound(_:)), to: sound.submenu!)
            entry.representedObject = name
            entry.state = InterruptionSound.current == name ? .on : .off
        }
        menu.addItem(sound)

        let finish = NSMenuItem(title: "Finish Sound", action: nil, keyEquivalent: "")
        finish.submenu = NSMenu()
        add("None", #selector(setFinishSound(_:)), to: finish.submenu!).state = FinishSound.current == nil ? .on : .off
        finish.submenu!.addItem(.separator())
        for voice in FinishSound.Voice.allCases {
            let entry = add(voice.rawValue, #selector(setFinishSound(_:)), to: finish.submenu!)
            entry.representedObject = voice.rawValue
            entry.state = FinishSound.current == voice ? .on : .off
        }
        menu.addItem(finish)
    }

    private func addScreens(to menu: NSMenu) {
        let screens = NSMenuItem(title: "Show Island On", action: nil, keyEquivalent: "")
        screens.submenu = NSMenu()
        let chosen = IslandScreen.chosen
        add("Automatic", #selector(setScreen(_:)), to: screens.submenu!).state = chosen == nil ? .on : .off
        screens.submenu!.addItem(.separator())
        var isConnected = false
        for screen in NSScreen.screens {
            guard let id = screen.displayID else { continue }
            let entry = add(screen.localizedName, #selector(setScreen(_:)), to: screens.submenu!)
            entry.representedObject = [id, screen.localizedName]
            entry.state = chosen?.id == id ? .on : .off
            isConnected = isConnected || chosen?.id == id
        }
        if let chosen, !isConnected {
            // The choice is kept for when the display comes back; until then the app picks.
            let entry = screens.submenu!.addItem(withTitle: "\(chosen.name) (not connected)", action: nil, keyEquivalent: "")
            entry.state = .on
            entry.isEnabled = false
        }
        menu.addItem(screens)
    }

    /// The system keeps the login item and may want the user to allow it in System Settings.
    private func addLoginItem(to menu: NSMenu) {
        let status = SMAppService.mainApp.status
        let title = status == .requiresApproval ? "Start at Login (allow it in System Settings)" : "Start at Login"
        add(title, #selector(toggleLoginItem), to: menu).state = status == .enabled ? .on : .off
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
    @objc private func setMode(_ sender: NSMenuItem) { model.interruptionMode = Self.modes[sender.tag].mode }

    @objc private func copyCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }

    @objc private func checkForUpdates() { updater.checkForUpdates() }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            // Refused by the system; the item shows the state it is left in.
            NSSound.beep()
        }
    }

    @objc private func setSound(_ sender: NSMenuItem) {
        InterruptionSound.current = sender.representedObject as? String
        // So the choice can be made by ear.
        InterruptionSound.play()
    }

    @objc private func setFinishSound(_ sender: NSMenuItem) {
        FinishSound.current = (sender.representedObject as? String).flatMap(FinishSound.Voice.init)
        // So the choice can be made by ear.
        FinishSound.play(after: 0)
    }

    @objc private func setScreen(_ sender: NSMenuItem) {
        let screen = sender.representedObject as? [String]
        IslandScreen.chosen = screen.map { ($0[0], $0[1]) }
    }
}
