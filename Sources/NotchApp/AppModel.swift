import ClaudeConnection
import Foundation
import SessionCore

/// Owns the session core and the connection to Claude Code. Lives for the whole app run,
/// independent of any window.
@MainActor
final class AppModel: ObservableObject {
    enum ConnectionStatus: Equatable {
        case connected
        case notConnected
        case failed(String)
    }

    @Published private(set) var snapshot: Snapshot
    @Published private(set) var connectionStatus: ConnectionStatus = .notConnected
    /// Usage limits of the account, as last reported through the status line wrapper.
    @Published private(set) var limits = LimitsSnapshot(fiveHour: .noData, sevenDay: .noData)

    let config: AppConfig
    private var core: SessionCore
    private var usage = UsageLimits()
    private var receiver: HookReceiver?
    private var receiverFailure: String?
    private var timer: Timer?

    init(config: AppConfig) {
        self.config = config
        core = SessionCore(settings: Settings(livenessThreshold: TimeInterval(config.livenessMinutes * 60)))
        snapshot = core.snapshot(at: Date())
    }

    func start() {
        do {
            let connection = config.connection
            let receiver = try HookReceiver(
                port: connection.port, token: try config.token(),
                onStatusLine: { [weak self] payload in self?.receiveStatusLine(payload) }
            ) { [weak self] payload in
                self?.receive(payload)
            }
            receiver.start { [weak self] error in
                self?.receiverFailure = "Cannot listen on port \(connection.port): \(error.localizedDescription)"
                self?.refreshConnectionStatus()
            }
            self.receiver = receiver
            if !config.connectionRemovedByUser {
                try config.installer.install(connection)
            }
            refreshConnectionStatus()
        } catch {
            connectionStatus = .failed(Self.describe(error))
        }
        // Finished sessions age out without any event arriving.
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshSnapshot()
                self?.refreshLimits()
            }
        }
    }

    func repairConnection() {
        perform {
            _ = try config.token()
            try config.installer.install(config.connection)
            config.connectionRemovedByUser = false
        }
    }

    func removeConnection() {
        perform {
            try config.installer.remove()
            config.connectionRemovedByUser = true
        }
    }

    var livenessMinutes: Int {
        get { config.livenessMinutes }
        set {
            config.livenessMinutes = newValue
            core.settings.livenessThreshold = TimeInterval(newValue * 60)
            refreshSnapshot()
        }
    }

    private func receive(_ payload: Data) {
        guard let event = HookEvent(payload: payload) else { return }
        core.handle(event, at: Date())
        refreshSnapshot()
    }

    private func refreshSnapshot() {
        let next = core.snapshot(at: Date())
        if next != snapshot { snapshot = next }
    }

    // MARK: Usage limits

    /// Limits are account-wide, so a payload from any session counts. A payload without limit data
    /// (before the first response, or an account without limits) changes nothing.
    private func receiveStatusLine(_ payload: Data) {
        guard let report = UsageReport(statusLinePayload: payload) else { return }
        usage.handle(report, at: Date())
        refreshLimits()
    }

    /// Also run on the timer: readings age, go stale and expire without any payload arriving.
    private func refreshLimits() {
        let next = usage.snapshot(at: Date())
        if next != limits { limits = next }
    }

    private func perform(_ change: () throws -> Void) {
        do {
            try change()
            refreshConnectionStatus()
        } catch {
            connectionStatus = .failed(Self.describe(error))
        }
    }

    private func refreshConnectionStatus() {
        if let receiverFailure {
            connectionStatus = .failed(receiverFailure)
            return
        }
        connectionStatus = config.installer.isInstalled(config.connection) ? .connected : .notConnected
    }

    private static func describe(_ error: Error) -> String {
        if error as? SettingsError == .malformed {
            return "Claude Code settings are not valid JSON; left untouched"
        }
        return error.localizedDescription
    }
}
