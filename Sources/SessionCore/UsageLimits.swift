import Foundation

/// A known figure for one window, with how far it can be trusted.
public struct LimitReading: Equatable, Sendable {
    /// 0 to 100.
    public var usedPercentage: Double
    public var resetsAt: Date
    /// Time since a session last reported this figure.
    public var age: TimeInterval
    /// Old enough that the real figure may have moved on. Still the last known data, so it is shown.
    public var isStale: Bool

    public init(usedPercentage: Double, resetsAt: Date, age: TimeInterval, isStale: Bool) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
        self.age = age
        self.isStale = isStale
    }
}

public enum LimitWindow: Equatable, Sendable {
    /// Nothing was ever reported: no session has answered yet, or the account has no limit data.
    case noData
    /// The last reported window ended at this time and nothing was reported since.
    case reset(at: Date)
    case known(LimitReading)
}

public struct LimitsSnapshot: Equatable, Sendable {
    public var fiveHour: LimitWindow
    public var sevenDay: LimitWindow

    public init(fiveHour: LimitWindow, sevenDay: LimitWindow) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }
}

/// Last known usage limits of the account. Pure: no UI, no system access, no clock of its own.
/// Kept apart from the session state: limits are account-wide, so a report from any session counts.
public struct UsageLimits: Sendable {
    /// Age from which a reading is marked stale.
    public var staleAfter: TimeInterval
    private var fiveHour: Record?
    private var sevenDay: Record?

    private struct Record: Sendable {
        var window: UsageWindow
        var reportedAt: Date
    }

    public init(staleAfter: TimeInterval = 900) {
        self.staleAfter = staleAfter
    }

    public mutating func handle(_ report: UsageReport, at time: Date) {
        Self.merge(report.fiveHour, into: &fiveHour, at: time)
        Self.merge(report.sevenDay, into: &sevenDay, at: time)
    }

    public func snapshot(at time: Date) -> LimitsSnapshot {
        LimitsSnapshot(fiveHour: window(fiveHour, at: time), sevenDay: window(sevenDay, at: time))
    }

    /// Every session reports the figure it saw last, so an idle session can report an old one long
    /// after another session moved the account on. Within one window usage only grows, and a window
    /// that resets earlier is an earlier window: both mark the incoming figure as the older one.
    private static func merge(_ incoming: UsageWindow?, into record: inout Record?, at time: Date) {
        guard let incoming else { return }
        if let known = record?.window {
            if incoming.resetsAt < known.resetsAt { return }
            if incoming.resetsAt == known.resetsAt && incoming.usedPercentage < known.usedPercentage { return }
        }
        record = Record(window: incoming, reportedAt: time)
    }

    private func window(_ record: Record?, at time: Date) -> LimitWindow {
        guard let record else { return .noData }
        // Past its reset time the figure describes a window that no longer exists.
        guard time < record.window.resetsAt else { return .reset(at: record.window.resetsAt) }
        let age = max(0, time.timeIntervalSince(record.reportedAt))
        return .known(LimitReading(
            usedPercentage: record.window.usedPercentage, resetsAt: record.window.resetsAt,
            age: age, isStale: age >= staleAfter))
    }
}
