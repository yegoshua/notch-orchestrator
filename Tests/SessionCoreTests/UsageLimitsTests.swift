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

    /// An idle session keeps reporting the figure it saw last, which says nothing new.
    @Test func aRepeatedFigureDoesNotMakeTheReadingFresh() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 50), at: now)
        limits.handle(report(fiveHour: 50), at: now.addingTimeInterval(300))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(300)).fiveHour).age == 300)
    }

    @Test func aResetTimeThatDiffersBySecondsIsTheSameWindow() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 80), at: now)
        limits.handle(report(fiveHour: 20, resets: fiveHourReset.addingTimeInterval(1)), at: now.addingTimeInterval(60))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(60)).fiveHour).usedPercentage == 80)
    }

    @Test func storedLimitsComeBackWithTheirAge() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 50, sevenDay: 3), at: now)

        let restored = try JSONDecoder().decode(UsageLimits.self, from: JSONEncoder().encode(limits))

        let later = now.addingTimeInterval(1200)
        #expect(restored.snapshot(at: later) == limits.snapshot(at: later))
        #expect(try reading(restored.snapshot(at: later).fiveHour).isStale)
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

/// The history the desktop app keeps, shaped as it was found on a real machine.
private let recordedHistory = """
{"version": 2, "samples": [
 {"t": 1791388834338, "org": "4d66bfa6", "u": {"fh": 23, "sd": 7}},
 {"t": 1791389734344, "org": "4d66bfa6", "u": {"fh": 25, "sd": 8}},
 {"t": 1791389370636, "org": "4d66bfa6", "u": {"fh": 24, "sd": 8}}]}
"""

@Suite struct ReadingLimitsFromTheDesktopAppsHistory {
    @Test func theLatestSampleIsRead() throws {
        let sample = try #require(UsageSample(desktopUsageHistory: Data(recordedHistory.utf8)))

        #expect(sample == UsageSample(takenAt: Date(timeIntervalSince1970: 1_791_389_734.344), fiveHour: 25, sevenDay: 8))
    }

    @Test func aSampleWithOneWindowIsStillASample() throws {
        let history = #"{"samples": [{"t": 1791389734344, "u": {"sd": 141}}, {"t": "soon", "u": {"fh": 1}}, {"u": {"fh": 2}}]}"#
        let sample = try #require(UsageSample(desktopUsageHistory: Data(history.utf8)))

        #expect(sample.fiveHour == nil)
        #expect(sample.sevenDay == 100)
    }

    @Test(arguments: [#"{"version": 2, "samples": []}"#, #"{"samples": [{"t": 1, "u": {}}]}"#, #"{"version": 2}"#, "[]", "not json", ""])
    func whatHoldsNoSampleIsNotRead(history: String) {
        #expect(UsageSample(desktopUsageHistory: Data(history.utf8)) == nil)
    }
}

@Suite struct LimitsMeasuredByTheDesktopApp {
    private func sample(_ fiveHour: Double?, sevenDay: Double? = nil, at time: Date) -> UsageSample {
        UsageSample(takenAt: time, fiveHour: fiveHour, sevenDay: sevenDay)
    }

    @Test func aMeasurementIsShownWithItsAgeAndNoResetTime() throws {
        var limits = UsageLimits()
        limits.handle(sample(25, sevenDay: 8, at: now))

        let snapshot = limits.snapshot(at: now.addingTimeInterval(120))

        #expect(try reading(snapshot.fiveHour) == LimitReading(usedPercentage: 25, resetsAt: nil, age: 120, isStale: false))
        #expect(try reading(snapshot.sevenDay) == LimitReading(usedPercentage: 8, resetsAt: nil, age: 120, isStale: false))
    }

    @Test func aLaterMeasurementReplacesAnEarlierOneEvenWhenLowerOrTheSame() throws {
        var limits = UsageLimits()
        limits.handle(sample(80, at: now))
        limits.handle(sample(2, at: now.addingTimeInterval(600)))
        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(600)).fiveHour).usedPercentage == 2)

        limits.handle(sample(2, at: now.addingTimeInterval(1200)))
        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(1260)).fiveHour).age == 60)
    }

    @Test func anEarlierMeasurementChangesNothing() throws {
        var limits = UsageLimits()
        limits.handle(sample(25, at: now))
        limits.handle(sample(18, at: now.addingTimeInterval(-900)))
        limits.handle(sample(25, at: now))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(30)).fiveHour) == LimitReading(usedPercentage: 25, resetsAt: nil, age: 30, isStale: false))
    }

    @Test func aMeasurementWhoseWindowMustHaveEndedIsNoDataAnyMore() {
        var limits = UsageLimits()
        limits.handle(sample(25, sevenDay: 8, at: now))

        let snapshot = limits.snapshot(at: now.addingTimeInterval(5 * 3600))

        #expect(snapshot.fiveHour == .noData)
        #expect(snapshot.sevenDay != .noData)
    }

    @Test func aMeasurementKeepsTheEndOfTheWindowASessionReported() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 29.99), at: now)
        // Whole percent: a little under the session's figure is still the same window.
        limits.handle(sample(29, at: now.addingTimeInterval(300)))

        let known = try reading(limits.snapshot(at: now.addingTimeInterval(300)).fiveHour)

        #expect(known == LimitReading(usedPercentage: 29, resetsAt: fiveHourReset, age: 0, isStale: false))
    }

    @Test func aMeasurementFarBelowTheSessionsFigureIsANewWindowWithUnknownEnd() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 80), at: now)
        limits.handle(sample(3, at: now.addingTimeInterval(300)))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(300)).fiveHour).resetsAt == nil)
    }

    @Test func aMeasurementTakenAfterTheReportedWindowEndedDropsItsEnd() throws {
        var limits = UsageLimits()
        limits.handle(report(fiveHour: 29), at: now)
        limits.handle(sample(40, at: fiveHourReset.addingTimeInterval(60)))

        let known = try reading(limits.snapshot(at: fiveHourReset.addingTimeInterval(60)).fiveHour)

        #expect(known.usedPercentage == 40)
        #expect(known.resetsAt == nil)
    }

    @Test func aSessionsReportTellsWhenTheMeasuredWindowEnds() throws {
        var limits = UsageLimits()
        limits.handle(sample(25, at: now))
        limits.handle(report(fiveHour: 25.4), at: now.addingTimeInterval(60))

        let known = try reading(limits.snapshot(at: now.addingTimeInterval(60)).fiveHour)

        // The figure is no news, so the reading is as old as the measurement.
        #expect(known == LimitReading(usedPercentage: 25, resetsAt: fiveHourReset, age: 60, isStale: false))
    }

    @Test func aSessionsHigherReportReplacesTheMeasurement() throws {
        var limits = UsageLimits()
        limits.handle(sample(25, at: now))
        limits.handle(report(fiveHour: 31), at: now.addingTimeInterval(60))

        #expect(try reading(limits.snapshot(at: now.addingTimeInterval(60)).fiveHour) == LimitReading(usedPercentage: 31, resetsAt: fiveHourReset, age: 0, isStale: false))
    }

    @Test func anIdleSessionsReportOfAWindowThatEndedBeforeTheMeasurementIsIgnored() throws {
        var limits = UsageLimits()
        limits.handle(sample(4, at: fiveHourReset.addingTimeInterval(600)))
        limits.handle(report(fiveHour: 90), at: fiveHourReset.addingTimeInterval(700))

        #expect(try reading(limits.snapshot(at: fiveHourReset.addingTimeInterval(700)).fiveHour) == LimitReading(usedPercentage: 4, resetsAt: nil, age: 100, isStale: false))
    }

    @Test func aReportOfAWindowThatBeganAfterTheMeasurementReplacesIt() throws {
        var limits = UsageLimits()
        limits.handle(sample(90, at: fiveHourReset.addingTimeInterval(-6 * 3600)))
        limits.handle(report(fiveHour: 5), at: now)

        #expect(try reading(limits.snapshot(at: now).fiveHour) == LimitReading(usedPercentage: 5, resetsAt: fiveHourReset, age: 0, isStale: false))
    }

    @Test func measurementsSurviveBeingStored() throws {
        var limits = UsageLimits()
        limits.handle(sample(25, sevenDay: 8, at: now))

        let restored = try JSONDecoder().decode(UsageLimits.self, from: JSONEncoder().encode(limits))

        #expect(restored.snapshot(at: now) == limits.snapshot(at: now))
    }
}
