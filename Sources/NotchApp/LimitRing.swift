import SessionCore
import SwiftUI

/// The usage ring: how much of the five-hour limit is used, and how old that figure is.
///
/// Before any figure arrives it shows an empty dashed ring with a word instead of a number. That is
/// the state for a fresh start, for accounts without limit data, and for any kind of session whose
/// status line never reaches us. Whether Claude desktop app sessions run the status line at all is
/// NOT verified (prototype finding 3), so with desktop-only use this may stay empty.
struct LimitRing: View {
    let window: LimitWindow

    var body: some View {
        HStack(spacing: 4) {
            switch window {
            case .known(let reading):
                ring(reading)
                Text("\(LimitText.percent(reading.usedPercentage))%")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Color(white: 0.92))
                    .opacity(reading.isStale ? 0.5 : 1)
                    .contentTransition(.numericText())
                age(reading)
            case .noData:
                emptyRing
                caption("no data")
            case .reset:
                emptyRing
                caption("reset")
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LimitText.line("Five-hour limit", window, now: Date()))
    }

    private func ring(_ reading: LimitReading) -> some View {
        ZStack {
            Circle().stroke(Color(white: 0.28), lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, reading.usedPercentage / 100))
                // A stale figure is drawn broken, so it does not rely on dimming alone.
                .stroke(style: StrokeStyle(
                    lineWidth: Self.lineWidth, lineCap: reading.isStale ? .butt : .round,
                    dash: reading.isStale ? [2, 1.5] : []))
                .foregroundStyle(Self.color(for: reading.usedPercentage))
                .opacity(reading.isStale ? 0.6 : 1)
                .rotationEffect(.degrees(-90))
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .animation(.easeOut(duration: 0.3), value: reading.usedPercentage)
    }

    /// How old the figure is. A stale one gets a warning mark in front.
    private func age(_ reading: LimitReading) -> some View {
        HStack(spacing: 1) {
            if reading.isStale {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 7))
            }
            Text(LimitText.shortAge(reading.age)).font(.system(size: 9, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(reading.isStale ? Self.warningColor : Color(white: 0.55))
    }

    private var emptyRing: some View {
        Circle()
            .stroke(style: StrokeStyle(lineWidth: Self.lineWidth, dash: [2, 2]))
            .foregroundStyle(Color(white: 0.4))
            .frame(width: Self.diameter, height: Self.diameter)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .medium)).foregroundStyle(Color(white: 0.55))
    }

    private static let diameter: CGFloat = 11
    private static let lineWidth: CGFloat = 2.2
    private static let warningColor = Color(red: 1.0, green: 0.72, blue: 0.3)

    private static func color(for percentage: Double) -> Color {
        switch percentage {
        case ..<70: Color(white: 0.92)
        case ..<90: warningColor
        default: Color(red: 1.0, green: 0.42, blue: 0.38)
        }
    }
}

/// Wording for limits, shared by the ring and the menu.
enum LimitText {
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
            return "\(name): \(percent(reading.usedPercentage))% used, resets \(time(reading.resetsAt, now: now))"
                + " (updated \(updated)\(reading.isStale ? ", may be out of date" : ""))"
        }
    }

    /// Why there is no number, for the place that has room to say it.
    static let noDataExplanation =
        "Limits appear after the first response in a Claude Code session (Pro and Max plans)"

    private static func time(_ date: Date, now: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: now)
            ? "at " + date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}
