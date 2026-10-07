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

    let config: AppConfig
    private var core: SessionCore
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
            let receiver = try HookReceiver(port: connection.port, token: try config.token()) { [weak self] payload in
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
            Task { @MainActor in self?.refreshSnapshot() }
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
