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
    /// False when the hooks are connected but the status line could not be wrapped, so no usage
    /// limits will arrive.
    @Published private(set) var forwardsUsageLimits = true

    let config: AppConfig
    private var core: SessionCore
    private var usage = UsageLimits()
    private var receiver: HookReceiver?
    private var receiverFailure: String?
    private var timer: Timer?

    init(config: AppConfig) {
        self.config = config
        core = SessionCore(settings: Settings(
            livenessThreshold: TimeInterval(config.livenessMinutes * 60), requestTimeout: config.requestTimeout))
        snapshot = core.snapshot(at: Date())
        if let stored = try? Data(contentsOf: config.usageLimitsFile),
           let usage = try? JSONDecoder().decode(UsageLimits.self, from: stored) {
            self.usage = usage
            limits = usage.snapshot(at: Date())
        }
    }

    func start() {
        do {
            let connection = config.connection
            let receiver = try HookReceiver(
                port: connection.port, token: try config.token(),
                onStatusLine: { [weak self] payload in self?.receiveStatusLine(payload) },
                onPermissionRequest: { [weak self] payload, held in
                    guard let self else { return held.respond(with: Data()) }
                    self.receiveRequest(payload, held)
                }
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
        startReconciling()
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

    /// Run after every input and on the timer: it is also what answers the held connections.
    private func refreshSnapshot() {
        deliverResolutions()
        let next = core.snapshot(at: Date())
        if next != snapshot { snapshot = next }
    }

    // MARK: Requests to the user

    /// The open hook connections of the requests in the core, by the identifier given to each.
    private var heldRequests: [String: HeldRequest] = [:]

    private func receiveRequest(_ payload: Data, _ held: HeldRequest) {
        guard let event = HookEvent(payload: payload) else {
            held.respond(with: Data())
            return
        }
        let id = UUID().uuidString
        heldRequests[id] = held
        held.onClientGone = { [weak self] in
            guard let self, self.heldRequests[id] != nil else { return }
            self.core.connectionDropped(id, at: Date())
            self.refreshSnapshot()
        }
        core.handle(event, at: Date(), requestID: id)
        refreshSnapshot()
    }

    /// The user's decision on a request in the queue.
    func decide(_ decision: Decision, on requestID: String) {
        core.decide(decision, on: requestID, at: Date())
        refreshSnapshot()
    }

    /// Gives every request the core has finished with its answer and lets its connection go.
    /// Requests that ran out of time are finished here too, with no decision.
    private func deliverResolutions() {
        core.advance(to: Date())
        for resolution in core.drainResolutions() {
            heldRequests.removeValue(forKey: resolution.requestID)?
                .respond(with: PermissionResponse.body(for: resolution.outcome))
        }
    }

    // MARK: Usage limits

    /// Limits are account-wide, so a payload from any session counts. A payload without limit data
    /// (before the first response, or an account without limits) changes nothing.
    private func receiveStatusLine(_ payload: Data) {
        guard let report = UsageReport(statusLinePayload: payload) else { return }
        usage.handle(report, at: Date())
        refreshLimits()
        storeLimits()
    }

    /// Also run on the timer: readings age, go stale and expire without any payload arriving.
    private func refreshLimits() {
        let next = usage.snapshot(at: Date())
        if next != limits { limits = next }
    }

    /// The last known figures outlive the app, so a restart does not empty the ring. They are
    /// percentages and reset times of the account, nothing about any project.
    private func storeLimits() {
        guard let data = try? JSONEncoder().encode(usage) else { return }
        try? FileManager.default.createDirectory(at: config.supportDirectory, withIntermediateDirectories: true)
        try? data.write(to: config.usageLimitsFile, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: config.usageLimitsFile.path)
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
        forwardsUsageLimits = config.installer.forwardsUsageLimits
    }

    private static func describe(_ error: Error) -> String {
        if error as? SettingsError == .malformed {
            return "Claude Code settings are not valid JSON; left untouched"
        }
        return error.localizedDescription
    }

    // MARK: Reconciliation

    private lazy var probe: SessionProbe = ClaudeSessionProbe(directory: config.claudeDataDirectory)
    private var reconcileTimer: Timer?
    private var isReconciling = false

    /// At launch the list is rebuilt from what is on disk; after that the sessions the core tracks
    /// are checked against their process and transcript every few seconds.
    private func startReconciling() {
        reconcile(discover: true)
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reconcile(discover: false) }
        }
    }

    private func reconcile(discover: Bool) {
        guard !isReconciling else { return }
        isReconciling = true
        let tracked = core.trackedSessions
        let probe = probe
        let observedAt = Date()
        DispatchQueue.global(qos: .utility).async {
            let observations = probe.observe(tracked: tracked, discover: discover)
            Task { @MainActor [weak self] in
                guard let self else { return }
                for observation in observations {
                    self.core.reconcile(observation, observedAt: observedAt)
                }
                self.isReconciling = false
                self.refreshSnapshot()
            }
        }
    }
}
