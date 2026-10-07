import Foundation
import Testing
import SessionCore

/// The `rate_limits` object exactly as the status line received it in the prototype (finding 3).
private let recordedPayload = """
{"session_id": "e9952653", "model": {"id": "claude-opus"}, "rate_limits": {"five_hour": \
{"used_percentage": 28.999999999999996, "resets_at": 1791380400}, "seven_day": \
{"used_percentage": 3, "resets_at": 1791936000}}}
"""

private let fiveHourReset = Date(timeIntervalSince1970: 1_791_380_400)
private let weeklyReset = Date(timeIntervalSince1970: 1_791_936_000)
/// Two hours before the five-hour window resets.
private let now = fiveHourReset.addingTimeInterval(-7200)

private func report(fiveHour: Double? = nil, resets: Date = fiveHourReset, sevenDay: Double? = nil) -> UsageReport {
    UsageReport(
        fiveHour: fiveHour.map { UsageWindow(usedPercentage: $0, resetsAt: resets) },
        sevenDay: sevenDay.map { UsageWindow(usedPercentage: $0, resetsAt: weeklyReset) })
}

private struct NotAReading: Error {}

private func reading(_ window: LimitWindow) throws -> LimitReading {
    guard case .known(let reading) = window else {
        Issue.record("expected a reading, got \(window)")
        throw NotAReading()
    }
    return reading
}

@Suite struct ReadingLimitsFromAStatusLinePayload {
    @Test func bothWindowsAreReadFromTheRecordedPayload() throws {
        let report = try #require(UsageReport(statusLinePayload: Data(recordedPayload.utf8)))

        #expect(report.fiveHour == UsageWindow(usedPercentage: 28.999999999999996, resetsAt: fiveHourReset))
        #expect(report.sevenDay == UsageWindow(usedPercentage: 3, resetsAt: weeklyReset))
    }

    @Test(arguments: [
        #"{"session_id": "e9952653"}"#,
        #"{"session_id": "e9952653", "rate_limits": null}"#,
        #"{"rate_limits": {}}"#,
        #"{"rate_limits": {"five_hour": {"used_percentage": "many"}}}"#,
        #"{"rate_limits": {"five_hour": {"used_percentage": 12}}}"#,
        "[1, 2]",
        "not json",
        "",
    ])
    func aPayloadWithoutLimitDataIsNotAReport(payload: String) {
        #expect(UsageReport(statusLinePayload: Data(payload.utf8)) == nil)
    }

    @Test func oneWindowAloneIsStillAReport() throws {
        let payload = #"{"rate_limits": {"seven_day": {"used_percentage": 41.5, "resets_at": 1791936000}}}"#
        let report = try #require(UsageReport(statusLinePayload: Data(payload.utf8)))

        #expect(report.fiveHour == nil)
        #expect(report.sevenDay == UsageWindow(usedPercentage: 41.5, resetsAt: weeklyReset))
    }

    @Test func aPercentageOutsideTheScaleIsBroughtBackIntoIt() throws {
        let payload = #"{"rate_limits": {"five_hour": {"used_percentage": 104.2, "resets_at": 1791380400}}}"#
        let report = try #require(UsageReport(statusLinePayload: Data(payload.utf8)))

        #expect(report.fiveHour?.usedPercentage == 100)
    }
}

@Suite struct LimitFreshness {
    @Test func beforeAnyReportBothWindowsHaveNoData() {
        let limits = UsageLimits()

        #expect(limits.snapshot(at: now) == LimitsSnapshot(fiveHour: .noData, sevenDay: .noData))
    }

    @Test func aReportIsShownWithItsAge() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 29, sevenDay: 3), at: now)

        let snapshot = limits.snapshot(at: now.addingTimeInterval(120))

        #expect(try reading(snapshot.fiveHour) == LimitReading(usedPercentage: 29, resetsAt: fiveHourReset, age: 120, isStale: false))
        #expect(try reading(snapshot.sevenDay) == LimitReading(usedPercentage: 3, resetsAt: weeklyReset, age: 120, isStale: false))
    }

    @Test func aReadingOlderThanTheThresholdIsStaleButStillShown() throws {
        var limits = UsageLimits(staleAfter: 600)
        limits.handle(report(fiveHour: 29), at: now)

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(599)).fiveHour).isStale == false)
        let stale = try reading(limits.snapshot(at: now.addingTimeInterval(600)).fiveHour)
        #expect(stale.isStale)
        #expect(stale.usedPercentage == 29)
    }

    @Test func aNewReportMakesTheReadingFreshAgain() throws {
        var limits = UsageLimits(staleAfter: 600)
        limits.handle(report(fiveHour: 29), at: now)
        limits.handle(report(fiveHour: 35), at: now.addingTimeInterval(900))

        let fresh = try reading(limits.snapshot(at: now.addingTimeInterval(930)).fiveHour)

        #expect(fresh == LimitReading(usedPercentage: 35, resetsAt: fiveHourReset, age: 30, isStale: false))
    }

    @Test func aReportForOneWindowLeavesTheOtherAsItWas() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 29, sevenDay: 3), at: now)
        limits.handle(report(fiveHour: 31), at: now.addingTimeInterval(60))

        let snapshot = limits.snapshot(at: now.addingTimeInterval(60))

        #expect(try reading(snapshot.fiveHour).age == 0)
        #expect(try reading(snapshot.sevenDay) == LimitReading(usedPercentage: 3, resetsAt: weeklyReset, age: 60, isStale: false))
    }
}

/// Limits are account-wide, but every session reports the figure it saw last.
@Suite struct LimitReportsFromSeveralSessions {
    @Test func anOlderFigureFromAnIdleSessionDoesNotReplaceANewerOne() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 50), at: now)
        limits.handle(report(fiveHour: 20), at: now.addingTimeInterval(300))

        let reading = try reading(limits.snapshot(at: now.addingTimeInterval(300)).fiveHour)

        #expect(reading.usedPercentage == 50)
        #expect(reading.age == 300)
    }

    @Test func theSameFigureAgainConfirmsTheReading() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 50), at: now)
        limits.handle(report(fiveHour: 50), at: now.addingTimeInterval(300))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(300)).fiveHour).age == 0)
    }

    @Test func aReportForAnEarlierWindowIsIgnored() throws {
        var limits = UsageLimits()
        let nextReset = fiveHourReset.addingTimeInterval(5 * 3600)
        limits.handle(report(fiveHour: 4, resets: nextReset), at: now)
        limits.handle(report(fiveHour: 97, resets: fiveHourReset), at: now.addingTimeInterval(60))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(60)).fiveHour).usedPercentage == 4)
    }

    @Test func aReportForALaterWindowReplacesTheReadingEvenWithALowerFigure() throws {
        var limits = UsageLimits()
        let nextReset = fiveHourReset.addingTimeInterval(5 * 3600)
        limits.handle(report(fiveHour: 97), at: now)
        limits.handle(report(fiveHour: 4, resets: nextReset), at: fiveHourReset.addingTimeInterval(60))

        let reading = try reading(limits.snapshot(at: fiveHourReset.addingTimeInterval(60)).fiveHour)

        #expect(reading == LimitReading(usedPercentage: 4, resetsAt: nextReset, age: 0, isStale: false))
    }
}

@Suite struct LimitWindowExpiry {
    @Test func aWindowIsClearedOnceItsResetTimeHasPassed() {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 96, sevenDay: 40), at: now)

        guard case .known = limits.snapshot(at: fiveHourReset.addingTimeInterval(-1)).fiveHour else {
            Issue.record("the window is still open one second before its reset")
            return
        }
        #expect(limits.snapshot(at: fiveHourReset).fiveHour == .reset(at: fiveHourReset))
        #expect(limits.snapshot(at: fiveHourReset.addingTimeInterval(3600)).fiveHour == .reset(at: fiveHourReset))
    }

    @Test func theOtherWindowOutlivesTheOneThatReset() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 96, sevenDay: 40), at: now)

        let weekly = try reading(limits.snapshot(at: fiveHourReset.addingTimeInterval(60)).sevenDay)

        #expect(weekly.usedPercentage == 40)
        #expect(limits.snapshot(at: weeklyReset).sevenDay == .reset(at: weeklyReset))
    }

    @Test func aReportThatArrivesAfterItsOwnResetTimeShowsNoNumber() {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 96), at: fiveHourReset.addingTimeInterval(10))

        #expect(limits.snapshot(at: fiveHourReset.addingTimeInterval(10)).fiveHour == .reset(at: fiveHourReset))
    }

    @Test func aNewWindowAfterAResetIsShownAgain() throws {
        var limits = UsageLimits()
        let nextReset = fiveHourReset.addingTimeInterval(5 * 3600)
        limits.handle(report(fiveHour: 96), at: now)
        limits.handle(report(fiveHour: 2, resets: nextReset), at: fiveHourReset.addingTimeInterval(600))

        #expect(try reading(limits.snapshot(at: fiveHourReset.addingTimeInterval(600)).fiveHour).usedPercentage == 2)
    }
}
