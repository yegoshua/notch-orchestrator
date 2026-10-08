import AppKit
import Combine
import SessionCore

/// The menu bar item: connection state, usage limits and the way to the settings window.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private let updater: AppUpdater
    private let settings: SettingsWindowController
    private var watching: AnyCancellable?
    private var shownGlyph: StatusGlyph?

    init(model: AppModel, updater: AppUpdater, settings: SettingsWindowController) {
        self.model = model
        self.updater = updater
        self.settings = settings
        super.init()
        showGlyph()
        // The model says that it is about to change; what it changed to is there a moment later.
        watching = model.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.showGlyph() }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    /// The glyph says what the island would: nothing runs, sessions work, one waits for the user,
    /// or no session can report at all.
    private func showGlyph() {
        let counters = model.snapshot.counters
        let glyph: StatusGlyph = model.connectionStatus != .connected ? .notConnected
            : counters.waiting > 0 ? .waiting : counters.working > 0 ? .working : .idle
        guard glyph != shownGlyph else { return }
        shownGlyph = glyph
        item.button?.image = glyph.image
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
            LimitText.menuLine("5-hour limit", limits.fiveHour, now: now),
            LimitText.menuLine("Weekly limit", limits.sevenDay, now: now),
        ]
        // Short lines: the menu is as wide as its longest one. The list says why there are none.
        if limits.fiveHour == .noData && limits.sevenDay == .noData {
            lines = ["Usage limits: no data yet"]
        }
        if model.connectionStatus == .connected && !model.forwardsUsageLimits {
            lines.append("Usage limits: status line cannot be wrapped")
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

/// The menu bar glyph, the "Keycap" of the design: a key with its lip, and on its face a mark for
/// sessions that work or, in amber, for one that waits. 18 points, drawn on the design's grid.
private enum StatusGlyph {
    case idle
    case working
    case waiting
    case notConnected

    var image: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let isOff = self == .notConnected
            // Black for a template image; the amber mark keeps its colour, so beside it the ink
            // is the menu bar's own.
            let ink = self == .waiting ? NSColor.labelColor : NSColor.black
            let key = NSBezierPath(roundedRect: NSRect(x: 2.75, y: 2.75, width: 12.5, height: 12.5), xRadius: 3.2, yRadius: 3.2)
            key.lineWidth = 1.5
            if isOff { key.setLineDash([2, 1.6], count: 2, phase: 0) }
            ink.withAlphaComponent(isOff ? 0.45 : 1).setStroke()
            key.stroke()
            let lip = NSBezierPath()
            lip.move(to: NSPoint(x: 5, y: 12.6))
            lip.line(to: NSPoint(x: 13, y: 12.6))
            lip.lineWidth = 1.2
            lip.lineCapStyle = .round
            ink.withAlphaComponent(isOff ? 0.3 : 0.55).setStroke()
            lip.stroke()
            func mark(_ radius: CGFloat, _ color: NSColor) {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: 9 - radius, y: 8 - radius, width: 2 * radius, height: 2 * radius)).fill()
            }
            if self == .working { mark(2, ink) }
            if self == .waiting { mark(2.5, NSColor(Island.waiting)) }
            return true
        }
        image.isTemplate = self != .waiting
        image.accessibilityDescription = "Notch Orchestrator"
        return image
    }
}
