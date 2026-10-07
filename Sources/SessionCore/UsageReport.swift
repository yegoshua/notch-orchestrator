import Foundation

/// One usage-limit window as Claude Code reports it.
public struct UsageWindow: Equatable, Sendable, Codable {
    /// 0 to 100.
    public var usedPercentage: Double
    /// Nil when the figure comes from a source that does not say when the window ends.
    public var resetsAt: Date?

    public init(usedPercentage: Double, resetsAt: Date?) {
        self.usedPercentage = usedPercentage
        self.resetsAt = resetsAt
    }
}

/// The usage limits one session saw last, taken from the JSON Claude Code feeds its status line.
public struct UsageReport: Equatable, Sendable {
    public var fiveHour: UsageWindow?
    public var sevenDay: UsageWindow?

    public init(fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// Nil when the payload carries no usable limit data. `rate_limits` is absent until the first
    /// model response in a session, and always absent for accounts without limit data, so such a
    /// payload says nothing about the limits and must not disturb what is already known.
    public init?(statusLinePayload: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: statusLinePayload) as? [String: Any],
              let limits = root["rate_limits"] as? [String: Any]
        else { return nil }
        fiveHour = Self.window(limits["five_hour"])
        sevenDay = Self.window(limits["seven_day"])
        if fiveHour == nil && sevenDay == nil { return nil }
    }

    /// `used_percentage` is an unrounded float (28.999999999999996 was seen), `resets_at` epoch seconds.
    private static func window(_ value: Any?) -> UsageWindow? {
        guard let object = value as? [String: Any],
              let used = number(object["used_percentage"]), let resets = number(object["resets_at"])
        else { return nil }
        return UsageWindow(usedPercentage: min(max(used, 0), 100), resetsAt: Date(timeIntervalSince1970: resets))
    }

    fileprivate static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue.isFinite ? number.doubleValue : nil
    }
}

/// What the Claude desktop app last measured of the account's usage, taken from the history it
/// keeps in `plan-usage-history.json`. Desktop sessions run no status line, so for them this is
/// the only source. The format is undocumented: whole percentages under `fh` and `sd`, with the
/// time of the measurement and no word on when either window ends.
public struct UsageSample: Equatable, Sendable {
    public var takenAt: Date
    /// 0 to 100.
    public var fiveHour: Double?
    public var sevenDay: Double?

    public init(takenAt: Date, fiveHour: Double? = nil, sevenDay: Double? = nil) {
        self.takenAt = takenAt
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// The latest sample of the history. Nil when the data is not that history or holds no usable
    /// sample.
    public init?(desktopUsageHistory: Data) {
        guard let root = try? JSONSerialization.jsonObject(with: desktopUsageHistory) as? [String: Any],
              let samples = root["samples"] as? [[String: Any]]
        else { return nil }
        let read = samples.compactMap { sample -> UsageSample? in
            guard let milliseconds = UsageReport.number(sample["t"]), let usage = sample["u"] as? [String: Any] else {
                return nil
            }
            func percentage(_ key: String) -> Double? { UsageReport.number(usage[key]).map { min(max($0, 0), 100) } }
            let fiveHour = percentage("fh"), sevenDay = percentage("sd")
            guard fiveHour != nil || sevenDay != nil else { return nil }
            return UsageSample(
                takenAt: Date(timeIntervalSince1970: milliseconds / 1000), fiveHour: fiveHour, sevenDay: sevenDay)
        }
        guard let latest = read.max(by: { $0.takenAt < $1.takenAt }) else { return nil }
        self = latest
    }
}
