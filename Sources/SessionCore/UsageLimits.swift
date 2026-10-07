import Foundation

/// A known figure for one window, with how far it can be trusted.
public struct LimitReading: Equatable, Sendable {
    /// 0 to 100.
    public var usedPercentage: Double
    /// Nil when only the desktop app's own measurements are known: they do not say.
    public var resetsAt: Date?
    /// Time since this figure was last reported or measured.
    public var age: TimeInterval
    /// Old enough that the real figure may have moved on. Still the last known data, so it is shown.
    public var isStale: Bool

    public init(usedPercentage: Double, resetsAt: Date?, age: TimeInterval, isStale: Bool) {
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
/// Codable so that the last known figures survive an app restart; `staleAfter` is not stored.
public struct UsageLimits: Sendable, Codable {
    /// Age from which a reading is marked stale.
    public var staleAfter: TimeInterval = 900
    private var fiveHour: Record?
    private var sevenDay: Record?

    private struct Record: Sendable, Codable {
        var window: UsageWindow
        var reportedAt: Date
    }

    private enum CodingKeys: CodingKey {
        case fiveHour, sevenDay
    }

    /// Reset times of one window were only ever seen as round values, but nothing promises that
    /// every session reports the same second.
    private static let sameWindowTolerance: TimeInterval = 60

    public init(staleAfter: TimeInterval = 900) {
        self.staleAfter = staleAfter
    }

    private static let fiveHours: TimeInterval = 5 * 3600
    private static let sevenDays: TimeInterval = 7 * 86400
    /// The desktop app measures in whole percent, so its figure may sit this far under a session's.
    private static let roundingSlack = 1.0

    public mutating func handle(_ report: UsageReport, at time: Date) {
        Self.merge(report.fiveHour, into: &fiveHour, at: time, length: Self.fiveHours)
        Self.merge(report.sevenDay, into: &sevenDay, at: time, length: Self.sevenDays)
    }

    /// Takes in a measurement of the desktop app.
    public mutating func handle(_ sample: UsageSample) {
        Self.merge(sample.fiveHour, into: &fiveHour, at: sample.takenAt)
        Self.merge(sample.sevenDay, into: &sevenDay, at: sample.takenAt)
    }

    public func snapshot(at time: Date) -> LimitsSnapshot {
        LimitsSnapshot(
            fiveHour: window(fiveHour, at: time, length: Self.fiveHours),
            sevenDay: window(sevenDay, at: time, length: Self.sevenDays))
    }

    /// A measurement is what the account's usage was at `time`, so a later one simply replaces
    /// what is known, whether higher, lower or the same. The end of the window is kept while the
    /// measurement still fits the window it was reported for.
    private static func merge(_ percentage: Double?, into record: inout Record?, at time: Date) {
        guard let percentage else { return }
        var window = UsageWindow(usedPercentage: percentage, resetsAt: nil)
        if let known = record {
            guard time > known.reportedAt else { return }
            if let resetsAt = known.window.resetsAt, time < resetsAt,
               percentage >= known.window.usedPercentage - roundingSlack {
                window.resetsAt = resetsAt
            }
        }
        record = Record(window: window, reportedAt: time)
    }

    /// Every session reports the figure it saw last, so an idle session can report an old one long
    /// after another session moved the account on. Within one window usage only grows, and a window
    /// that resets earlier is an earlier window: both mark the incoming figure as the older one.
    /// The same figure again is no news either, so it does not make the reading any fresher.
    ///
    /// What is known may be a measurement of the desktop app, which has no end of window: a
    /// report then belongs to the same window when the measurement was taken inside it.
    private static func merge(
        _ incoming: UsageWindow?, into record: inout Record?, at time: Date, length: TimeInterval
    ) {
        // A session always says when its window ends; a figure without that is no report.
        guard let incoming, let incomingResets = incoming.resetsAt else { return }
        if let known = record {
            if let knownResets = known.window.resetsAt {
                let sameWindow = abs(incomingResets.timeIntervalSince(knownResets)) <= sameWindowTolerance
                if sameWindow && incoming.usedPercentage <= known.window.usedPercentage { return }
                if !sameWindow && incomingResets < knownResets { return }
            } else {
                // The window of the report was over when the measurement was taken.
                if incomingResets <= known.reportedAt { return }
                let sameWindow = known.reportedAt >= incomingResets.addingTimeInterval(-length)
                if sameWindow && incoming.usedPercentage <= known.window.usedPercentage + roundingSlack {
                    // Nothing new about the usage, but now it is known when the window ends.
                    record?.window.resetsAt = incomingResets
                    return
                }
            }
        }
        record = Record(window: incoming, reportedAt: time)
    }

    private func window(_ record: Record?, at time: Date, length: TimeInterval) -> LimitWindow {
        guard let record else { return .noData }
        if let resetsAt = record.window.resetsAt {
            // Past its reset time the figure describes a window that no longer exists.
            guard time < resetsAt else { return .reset(at: resetsAt) }
        } else if time.timeIntervalSince(record.reportedAt) >= length {
            // Its window has ended by now, whenever that was.
            return .noData
        }
        let age = max(0, time.timeIntervalSince(record.reportedAt))
        return .known(LimitReading(
            usedPercentage: record.window.usedPercentage, resetsAt: record.window.resetsAt,
            age: age, isStale: age >= staleAfter))
    }
}
