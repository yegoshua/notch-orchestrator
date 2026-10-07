import SessionCore
import SwiftUI

/// The usage ring: how much of the five-hour limit is used. A figure that has gone stale is drawn
/// broken and dimmed, so that it does not pass for a fresh one.
///
/// Before any figure arrives it is an empty dashed ring with a dash for a number. That is the
/// state for a fresh start, for accounts without limit data, and for any kind of session whose
/// status line never reaches us. Whether Claude desktop app sessions run the status line at all is
/// NOT verified (prototype finding 3), so with desktop-only use this may stay empty.
struct LimitRing: View {
    let window: LimitWindow

    var body: some View {
        HStack(spacing: 5) {
            dial
            Text(LimitText.figure(window))
                .font(.system(size: 11, weight: LimitText.isNearLimit(window) ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(LimitText.color(window))
                .opacity(LimitText.isStale(window) ? 0.55 : 1)
                .contentTransition(.numericText())
                .frame(minWidth: 24, alignment: .trailing)
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LimitText.line("Five-hour limit", window, now: Date()))
    }

    private var dial: some View {
        Group {
            if case .known(let reading) = window {
                ZStack {
                    Circle().stroke(Island.ringTrack, lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: max(0.01, min(1, reading.usedPercentage / 100)))
                        // A stale figure is drawn broken, so it does not rely on dimming alone.
                        .stroke(style: StrokeStyle(
                            lineWidth: 2, lineCap: reading.isStale ? .butt : .round, dash: reading.isStale ? [2, 1.5] : []))
                        .foregroundStyle(LimitText.barColor(reading.usedPercentage))
                        .opacity(reading.isStale ? 0.6 : 1)
                        .rotationEffect(.degrees(-90))
                        .animation(Island.ring, value: reading.usedPercentage)
                }
            } else {
                Circle().stroke(Island.text5, style: StrokeStyle(lineWidth: 1.5, dash: [2.2, 2.2]))
            }
        }
        .padding(1.5)
        .frame(width: 14, height: 14)
    }
}

/// Wording for limits, shared by the ring and the menu.
enum LimitText {
    /// The number beside a ring or a bar; a dash while there is none.
    static func figure(_ window: LimitWindow) -> String {
        if case .known(let reading) = window { return "\(percent(reading.usedPercentage))%" }
        return "\u{2014}"
    }

    static func isNearLimit(_ window: LimitWindow) -> Bool {
        if case .known(let reading) = window { return reading.usedPercentage >= 90 }
        return false
    }

    static func isStale(_ window: LimitWindow) -> Bool {
        if case .known(let reading) = window { return reading.isStale }
        return false
    }

    /// The colour of the figure: it only stands out as the limit comes close.
    static func color(_ window: LimitWindow) -> Color {
        guard case .known(let reading) = window else { return Island.text3 }
        switch reading.usedPercentage {
        case ..<70: return Island.text2
        case ..<90: return Island.usageHigh
        default: return Island.failedText
        }
    }

    static func barColor(_ percentage: Double) -> Color {
        switch percentage {
        case ..<70: Island.usageCalm
        case ..<90: Island.usageHigh
        default: Island.failed
        }
    }

    /// When a window resets, as short as it can be said.
    static func resets(_ window: LimitWindow, now: Date) -> String? {
        guard case .known(let reading) = window, let resetsAt = reading.resetsAt else { return nil }
        return "resets " + (Calendar.current.isDate(resetsAt, inSameDayAs: now)
            ? resetsAt.formatted(date: .omitted, time: .shortened)
            : resetsAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
    }

    /// How old the figures are, by the fresher of the two windows.
    static func freshness(_ limits: LimitsSnapshot) -> String {
        let ages = [limits.fiveHour, limits.sevenDay].compactMap { window -> TimeInterval? in
            if case .known(let reading) = window { return reading.age }
            return nil
        }
        guard let age = ages.min() else { return "No usage data yet" }
        let stale = isStale(limits.fiveHour) || isStale(limits.sevenDay)
        let updated = age < 60 ? "Updated just now" : "Updated \(shortAge(age)) ago"
        return stale ? updated + " \u{00B7} may be out of date" : updated
    }

    /// Whole percent. Never 100 before the limit is actually reached.
    static func percent(_ percentage: Double) -> Int {
        percentage >= 100 ? 100 : min(99, Int(percentage.rounded()))
    }

    static func shortAge(_ age: TimeInterval) -> String {
        switch age {
        case ..<60: "now"
        case ..<3600: "\(Int(age / 60))m"
        case ..<86400: "\(Int(age / 3600))h"
        default: "\(Int(age / 86400))d"
        }
    }

    static func line(_ name: String, _ window: LimitWindow, now: Date) -> String {
        switch window {
        case .noData:
            return "\(name): no data yet"
        case .reset(let at):
            return "\(name): window reset \(time(at, now: now)), waiting for new data"
        case .known(let reading):
            let updated = reading.age < 60 ? "just now" : "\(shortAge(reading.age)) ago"
            let resets = reading.resetsAt.map { ", resets \(time($0, now: now))" } ?? ""
            return "\(name): \(percent(reading.usedPercentage))% used\(resets)"
                + " (updated \(updated)\(reading.isStale ? ", may be out of date" : ""))"
        }
    }

    /// Why there is no number, for the place that has room to say it.
    static let noDataExplanation =
        "Limits appear after the first response in a Claude Code session, or once the Claude desktop app has measured them"

    private static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? "at " + date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
