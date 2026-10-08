import AppKit
import ClaudeConnection
import Combine
import ServiceManagement
import SessionCore
import SwiftUI

/// The sections of the settings window, in the order of its tabs.
enum SettingsTab: String, CaseIterable {
    case general = "General"
    case interruptions = "Interruptions"
    case connection = "Connection"
    case gitLab = "GitLab"
}

/// The settings window: an ordinary window of the system, unlike the island. It follows screen 6
/// of the "Notch Island v2" design.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let updater: AppUpdater
    private let state = SettingsState()
    private var window: NSWindow?
    private var offer: AnyCancellable?

    init(model: AppModel, updater: AppUpdater) {
        self.model = model
        self.updater = updater
        super.init()
        guard !model.config.gitLabSetupWasOffered else { return }
        offer = model.$snapshot.receive(on: RunLoop.main).sink { [weak self] _ in self?.offerGitLabSetup() }
    }

    /// Opens the window, on `tab` when one is named. Without `activating` it comes up without
    /// taking the keyboard from what the user is typing into.
    func show(_ tab: SettingsTab? = nil, activating: Bool = true) {
        if let tab { state.tab = tab }
        state.refresh()
        let window = window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        if activating {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    /// The first time a GitLab cannot be asked about a push, the steps that fix it are shown.
    private func offerGitLabSetup() {
        guard model.unreachableHosts.contains(where: { GitProvider(host: $0.host) == .gitLab }) else { return }
        offer = nil
        guard !model.config.gitLabSetupWasOffered else { return }
        model.config.gitLabSetupWasOffered = true
        show(.gitLab, activating: false)
    }

    private func makeWindow() -> NSWindow {
        let window = SettingsWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsView.width, height: 360),
            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hosting = NSHostingView(rootView: SettingsView(
            model: model, state: state, updater: updater, onHeight: { [weak self] in self?.fit($0) }))
        // The window is sized here, to the tab that shows.
        hosting.sizingOptions = []
        window.contentView = hosting
        return window
    }

    /// Makes the window as tall as its tab, keeping its top edge where it is.
    private func fit(_ height: CGFloat) {
        guard let window, height > 0, abs(window.frame.height - height) > 0.5 else { return }
        var frame = window.frame
        frame.origin.y += frame.height - height
        frame.size.height = height
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    /// Coming back from the terminal where the user signed in is when the answer changes.
    func windowDidBecomeKey(_ notification: Notification) {
        state.refresh()
        if state.tab == .gitLab { state.checkGitLab(model) }
    }
}

/// An app without a main menu has nothing that closes a window from the keyboard.
private final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// What the window shows of the settings that live outside the model, and of the GitLab check.
@MainActor
private final class SettingsState: ObservableObject {
    @Published var tab = SettingsTab.general
    @Published var hotkey = HotkeySetting.current {
        didSet { if hotkey != oldValue { HotkeySetting.current = hotkey } }
    }
    /// Nil leaves the choice of the screen to the app.
    @Published var screenID = IslandScreen.chosen?.id {
        didSet {
            guard screenID != oldValue else { return }
            let screen = NSScreen.screens.first { $0.displayID == screenID }
            IslandScreen.chosen = screenID.map { ($0, screen?.localizedName ?? IslandScreen.chosen?.name ?? "Display") }
        }
    }
    @Published var sound = InterruptionSound.current {
        didSet { if sound != oldValue { InterruptionSound.current = sound } }
    }
    @Published var finishSound = FinishSound.current {
        didSet { if finishSound != oldValue { FinishSound.current = finishSound } }
    }
    @Published var loginStatus = SMAppService.mainApp.status

    /// How each GitLab host answered the last check. Empty until the first one came back.
    @Published var access: [String: HostAccess] = [:]
    @Published var isChecking = false

    /// Takes in what may have changed outside the window.
    func refresh() {
        loginStatus = SMAppService.mainApp.status
        hotkey = HotkeySetting.current
        screenID = IslandScreen.chosen?.id
    }

    func setStartsAtLogin(_ starts: Bool) {
        let service = SMAppService.mainApp
        do {
            if starts { try service.register() } else { try service.unregister() }
        } catch {
            // Refused by the system; the switch shows the state it is left in.
            NSSound.beep()
        }
        loginStatus = service.status
    }

    func checkGitLab(_ model: AppModel) {
        guard !isChecking else { return }
        isChecking = true
        model.checkAccess(to: model.gitLabHosts) { [weak self] found in
            self?.access = found
            self?.isChecking = false
        }
    }
}

// MARK: - Look

/// The colours of the window: those of the design in light, their counterparts in dark.
private enum Pref {
    static let window = Color(light: 0xF4F3F1, dark: 0x1E1E1D)
    static let header = Color(light: 0xECEBE8, dark: 0x292928)
    static let headerLine = Color(light: 0xD9D8D4, dark: 0x0F0F0F)
    static let card = Color(light: 0xFFFFFF, dark: 0x2B2B2A)
    static let rowLine = Color(light: 0xEEEDEA, dark: 0x383836)
    static let secondary = Color(light: 0x6E6D6A, dark: 0x9C9B97)
    static let tabText = Color(light: 0x4A4946, dark: 0xB4B3AE)
    static let green = Color(light: 0x34C759, dark: 0x30D158)
    static let red = Color(light: 0xD70015, dark: 0xFF6961)

    static let title = Font.system(size: 13)
    static let detail = Font.system(size: 11)
    static let code = Font.system(size: 11.5, design: .monospaced)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// A white group of rows.
private struct PrefCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        VStack(spacing: 0) { content }
            .background(shape.fill(Pref.card))
            .overlay(shape.strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5))
    }
}

private struct PrefDivider: View {
    var body: some View { Pref.rowLine.frame(height: 1) }
}

/// A setting: what it is on the left, with a line of explanation where it needs one, and its
/// control on the right.
private struct PrefRow<Control: View>: View {
    let title: String
    var detail: String?
    var titleColor = Color.primary
    @ViewBuilder var control: Control

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Pref.title).foregroundStyle(titleColor)
                if let detail {
                    Text(detail).font(Pref.detail).foregroundStyle(Pref.secondary).lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control.fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// A command for the user to run in a terminal, with a button that copies it.
private struct CommandLine: View {
    let command: String
    @State private var wasCopied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(command).font(Pref.code).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(wasCopied ? "Copied" : "Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                wasCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { wasCopied = false }
            }
            .controlSize(.small)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Pref.window))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
    }
}

// MARK: - The window

private struct SettingsView: View {
    static let width: CGFloat = 520

    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState
    let updater: AppUpdater
    let onHeight: (CGFloat) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Group {
                switch state.tab {
                case .general: GeneralTab(model: model, state: state, updater: updater)
                case .interruptions: InterruptionsTab(model: model, state: state)
                case .connection: ConnectionTab(model: model)
                case .gitLab: GitLabTab(model: model, state: state)
                }
            }
            .padding(20)
        }
        .frame(width: Self.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { geometry in
            Color.clear
                .onAppear { onHeight(geometry.size.height) }
                .onChange(of: geometry.size.height) { _, height in onHeight(height) }
        })
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Pref.window)
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(spacing: 0) {
            Text(state.tab.rawValue).font(.system(size: 13, weight: .semibold)).frame(height: 30)
            HStack(spacing: 4) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    let isChosen = tab == state.tab
                    Button { state.tab = tab } label: {
                        Text(tab.rawValue)
                            .font(.system(size: 12, weight: isChosen ? .medium : .regular))
                            .foregroundStyle(isChosen ? Color.primary : Pref.tabText)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(Color.primary.opacity(isChosen ? 0.08 : 0)))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 76)
        .background(Pref.header)
        .overlay(alignment: .bottom) { Pref.headerLine.frame(height: 1) }
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState
    let updater: AppUpdater

    private static let liveness: [(minutes: Int, title: String)] = [
        (1, "1 minute"), (5, "5 minutes"), (10, "10 minutes"), (30, "30 minutes"), (60, "1 hour"),
    ]

    var body: some View {
        VStack(spacing: 14) {
            PrefCard {
                PrefRow(
                    title: "Start at login",
                    detail: state.loginStatus == .requiresApproval ? "Allow it in System Settings, under Login Items." : nil
                ) {
                    Toggle("", isOn: Binding(
                        get: { state.loginStatus == .enabled }, set: { state.setStartsAtLogin($0) }))
                        .toggleStyle(.switch).controlSize(.small).labelsHidden()
                }
                PrefDivider()
                PrefRow(title: "Hotkey", detail: "Opens the session list; press again to close.") {
                    Picker("", selection: $state.hotkey) {
                        ForEach(hotkeys, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
                PrefDivider()
                PrefRow(title: "Show the island on", detail: "Screens without a notch get a pill at the top centre.") {
                    Picker("", selection: $state.screenID) {
                        Text("Automatic").tag(String?.none)
                        Divider()
                        ForEach(screens, id: \.id) { Text($0.name).tag(String?.some($0.id)) }
                    }
                    .labelsHidden()
                }
                PrefDivider()
                PrefRow(
                    title: "Keep finished sessions visible for", detail: "Then they drop out of the counter and the list."
                ) {
                    Picker("", selection: $model.livenessMinutes) {
                        ForEach(Self.liveness, id: \.minutes) { Text($0.title).tag($0.minutes) }
                    }
                    .labelsHidden()
                }
                PrefDivider()
                PrefRow(title: "Show CI as", detail: "The pipeline of what a session pushed.") {
                    Picker("", selection: $model.ciView) {
                        Text("A line under the session").tag(CIView.detailed)
                        Text("A mark in the session's row").tag(CIView.compact)
                    }
                    .labelsHidden()
                }
            }
            if let version = updater.version {
                PrefCard {
                    PrefRow(title: "Version \(version)") {
                        if updater.isAvailable {
                            Button("Check for Updates…") { updater.checkForUpdates() }
                        }
                    }
                }
            }
        }
    }

    /// The presets, and before them a combination that was stored by hand.
    private var hotkeys: [HotkeySetting] {
        HotkeySetting.presets.contains(state.hotkey) ? HotkeySetting.presets : [state.hotkey] + HotkeySetting.presets
    }

    /// The connected screens, and the chosen one when it is not among them: the choice is kept
    /// for when the display comes back.
    private var screens: [(id: String, name: String)] {
        var screens = NSScreen.screens.compactMap { screen in screen.displayID.map { (id: $0, name: screen.localizedName) } }
        if let chosen = IslandScreen.chosen, !screens.contains(where: { $0.id == chosen.id }) {
            screens.append((chosen.id, "\(chosen.name) (not connected)"))
        }
        return screens
    }
}

// MARK: - Interruptions

private struct InterruptionsTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState

    private static let modes: [(mode: InterruptionMode, title: String, detail: String)] = [
        (.loud, "Loud", "Every request opens the card with a sound and every finished turn shows its line with a sound, also for the session in front."),
        (.smart, "Smart", "A request opens the card with a sound only when its session is not in front. Otherwise only the counter changes."),
        (.quiet, "Quiet", "Nothing opens by itself. The counters are the only signal."),
    ]

    var body: some View {
        VStack(spacing: 14) {
            PrefCard {
                ForEach(Array(Self.modes.enumerated()), id: \.offset) { index, choice in
                    if index > 0 { PrefDivider() }
                    modeRow(choice.mode, choice.title, choice.detail)
                }
            }
            PrefCard {
                PrefRow(title: "Request sound") {
                    HStack(spacing: 8) {
                        Button("Play") { InterruptionSound.play() }.buttonStyle(.link).disabled(state.sound == nil)
                        Picker("", selection: $state.sound) {
                            Text("None").tag(String?.none)
                            Divider()
                            ForEach(InterruptionSound.names, id: \.self) { Text($0).tag(String?.some($0)) }
                        }
                        .labelsHidden()
                    }
                }
                PrefDivider()
                PrefRow(title: "Finished turn sound", detail: "Quiet on purpose: it may be missed.") {
                    HStack(spacing: 8) {
                        Button("Play") { FinishSound.play(after: 0) }.buttonStyle(.link).disabled(state.finishSound == nil)
                        Picker("", selection: $state.finishSound) {
                            Text("None").tag(FinishSound.Voice?.none)
                            Divider()
                            ForEach(FinishSound.Voice.allCases, id: \.self) { Text($0.rawValue).tag(FinishSound.Voice?.some($0)) }
                        }
                        .labelsHidden()
                    }
                }
                PrefDivider()
                focusRow
            }
        }
        // So the choice can be made by ear.
        .onChange(of: state.sound) { _, _ in InterruptionSound.play() }
        .onChange(of: state.finishSound) { _, _ in FinishSound.play(after: 0) }
    }

    private func modeRow(_ mode: InterruptionMode, _ title: String, _ detail: String) -> some View {
        let isChosen = model.interruptionMode == mode
        return Button { model.interruptionMode = mode } label: {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    if isChosen {
                        Circle().fill(Color.accentColor)
                        Circle().fill(.white).frame(width: 5, height: 5)
                    } else {
                        Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    }
                }
                .frame(width: 15, height: 15)
                .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    (Text(title) + Text(mode == .smart ? " (default)" : "").foregroundColor(Pref.secondary)).font(Pref.title)
                    Text(detail).font(Pref.detail).foregroundStyle(Pref.secondary).lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
    }

    @ViewBuilder private var focusRow: some View {
        if model.attentionMonitor.canReadFocus {
            PrefRow(title: "Respect Focus", detail: "While a Focus is on, behave as Quiet.") {
                Toggle("", isOn: $model.respectsFocus).toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
        } else {
            PrefRow(
                title: "Respect Focus",
                detail: "macOS keeps Focus from apps without Full Disk Access, so no Focus is seen until you grant it."
            ) {
                Button("Open System Settings") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

// MARK: - Connection

private struct ConnectionTab: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 14) {
            PrefCard {
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(statusColor).frame(width: 8, height: 8).padding(.top, 5)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle).font(Pref.title)
                        Text(statusDetail).font(Pref.detail).foregroundStyle(Pref.secondary).lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            PrefCard {
                PrefRow(
                    title: "Repair connection",
                    detail: "Rewrites the hooks if they were edited or removed. Other settings are left alone."
                ) {
                    Button("Repair") { model.repairConnection() }
                }
                PrefDivider()
                PrefRow(
                    title: "Remove completely",
                    detail: "Removes everything the app added to the settings file, and it is not added again until you repair the connection. Your sessions and history are not touched."
                ) {
                    Button { confirmRemoval() } label: { Text("Remove…").foregroundStyle(Pref.red) }
                }
            }
        }
    }

    private var settingsPath: String { (model.config.claudeSettings.path as NSString).abbreviatingWithTildeInPath }

    private var statusColor: Color {
        switch model.connectionStatus {
        case .connected: Pref.green
        case .notConnected: Pref.secondary
        case .failed: Pref.red
        }
    }

    private var statusTitle: String {
        switch model.connectionStatus {
        case .connected: "Connected to Claude Code"
        case .notConnected: "Not connected to Claude Code"
        case .failed: "Connection failed"
        }
    }

    private var statusDetail: String {
        switch model.connectionStatus {
        case .connected:
            let hooks = "\(ClaudeSettings.events.count) hooks installed in \(settingsPath)"
            return model.forwardsUsageLimits
                ? hooks : "\(hooks). Usage limits are unavailable: the statusLine setting has a form the app cannot wrap."
        case .notConnected:
            return "No hooks in \(settingsPath). Repair the connection to add them."
        case .failed(let message):
            return message
        }
    }

    private func confirmRemoval() {
        let alert = NSAlert()
        alert.messageText = "Remove the connection to Claude Code?"
        alert.informativeText = "The island stops showing sessions until you repair the connection."
        alert.addButton(withTitle: "Remove").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.removeConnection() }
    }
}

// MARK: - GitLab

/// The steps that let the island follow pipelines and merge requests on a GitLab, each with
/// whether it is done already.
private struct GitLabTab: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: SettingsState
    @State private var newHost = ""

    var body: some View {
        let hosts = model.gitLabHosts
        let known = hosts.compactMap { state.access[$0] }
        let hasTool = known.contains { $0 != .noTool }
        VStack(spacing: 14) {
            PrefCard {
                PrefRow(
                    title: "Pipelines and merge requests",
                    detail: "The island shows the CI of what a session pushed and follows its merge request until it is merged. It asks GitLab through your own glab sign-in and holds no tokens."
                ) {
                    if state.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Check Again") { state.checkGitLab(model) }
                    }
                }
            }
            PrefCard {
                step(1, "Install glab", isDone: known.isEmpty ? nil : hasTool,
                     detail: hasTool ? "GitLab's command line tool is installed." : "GitLab's command line tool. With Homebrew:") {
                    if !known.isEmpty, !hasTool { CommandLine(command: "brew install glab") }
                }
                PrefDivider()
                step(2, "Sign in to your GitLab", isDone: known.isEmpty ? nil : known.contains(.signedIn),
                     detail: "Run the command in a terminal and follow its questions. A token it asks for needs the scopes api and read_repository.") {
                    ForEach(hosts, id: \.self) { host in hostRow(host) }
                    HStack(spacing: 8) {
                        TextField("gitlab.example.com", text: $newHost)
                            .textFieldStyle(.roundedBorder).font(.system(size: 12)).onSubmit(addHost)
                        Button("Add Host", action: addHost).disabled(Self.host(from: newHost) == nil)
                    }
                }
                PrefDivider()
                step(3, "Push from a session", isDone: nil,
                     detail: "After git push or glab mr create in a Claude Code session, the pipeline shows in the session's row, and the merge request stays in the list under the sessions until it is merged or closed.") {
                    EmptyView()
                }
            }
        }
        .onAppear { state.checkGitLab(model) }
    }

    /// A numbered step. `isDone` is nil while that is not known, or nothing can tell.
    private func step<Content: View>(
        _ number: Int, _ title: String, isDone: Bool?, detail: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                if isDone == true {
                    Circle().fill(Pref.green)
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else {
                    Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1)
                    Text("\(number)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Pref.secondary)
                }
            }
            .frame(width: 18, height: 18)
            .accessibilityLabel(isDone == true ? "Done" : "Step \(number)")
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Pref.title)
                    Text(detail).font(Pref.detail).foregroundStyle(Pref.secondary).lineSpacing(1.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder private func hostRow(_ host: String) -> some View {
        let access = state.access[host]
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(host).font(.system(size: 12, weight: .medium))
                switch access {
                case .signedIn: Text("Signed in").font(Pref.detail).foregroundStyle(Pref.green)
                case .signedOut: Text("Not signed in").font(Pref.detail).foregroundStyle(Pref.red)
                case .noTool: Text("Needs glab").font(Pref.detail).foregroundStyle(Pref.secondary)
                case nil: EmptyView()
                }
                Spacer()
                if model.config.gitLabHosts.contains(host) {
                    Button("Remove") {
                        model.config.gitLabHosts.removeAll { $0 == host }
                        model.objectWillChange.send()
                    }
                    .buttonStyle(.link).font(Pref.detail)
                }
            }
            if access != .signedIn { CommandLine(command: GitProvider.gitLab.signInCommand(host: host)) }
        }
    }

    private func addHost() {
        guard let host = Self.host(from: newHost) else { return }
        if !model.gitLabHosts.contains(host) {
            model.config.gitLabHosts.append(host)
            model.objectWillChange.send()
        }
        newHost = ""
        state.checkGitLab(model)
    }

    /// The host in what was typed, which may be a whole address. Nil when it is none, or is not
    /// one the app would take for a GitLab.
    private static func host(from text: String) -> String? {
        var host = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let scheme = host.range(of: "://") { host = String(host[scheme.upperBound...]) }
        host = String(host.prefix { $0 != "/" })
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-:")
        guard host.contains("."), !host.hasPrefix("-"), host.unicodeScalars.allSatisfy(allowed.contains),
              GitProvider(host: host) == .gitLab
        else { return nil }
        return host
    }
}
