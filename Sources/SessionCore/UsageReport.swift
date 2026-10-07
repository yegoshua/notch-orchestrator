import Foundation

/// One usage-limit window as Claude Code reports it.
public struct UsageWindow: Equatable, Sendable {
    /// 0 to 100.
    public var usedPercentage: Double
    public var resetsAt: Date

    public init(usedPercentage: Double, resetsAt: Date) {
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

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return number.doubleValue.isFinite ? number.doubleValue : nil
    }
}
