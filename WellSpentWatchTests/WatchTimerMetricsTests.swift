import Foundation
import Testing
import WellSpentWatchContracts

@testable import WellSpentWatch

struct WatchTimerMetricsTests {
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

    @Test
    func runningElapsedMatchesExactSegmentIntervals() {
        let run = makeRun(state: .running, goal: 1_000)
        let segments = [
            makeSegment(index: 1, start: 0, end: 600),
            makeSegment(index: 2, start: 900, end: nil),
            makeSegment(index: 3, runID: UUID(), start: 0, end: nil),
        ]

        let first = WatchTimerMetrics.calculate(
            run: run,
            segments: segments,
            at: epoch.addingTimeInterval(1_200)
        )
        let later = WatchTimerMetrics.calculate(
            run: run,
            segments: segments,
            at: epoch.addingTimeInterval(1_237)
        )

        #expect(first.billableSeconds == 900)
        #expect(first.pausedSeconds == 300)
        #expect(first.wallSeconds == 1_200)
        #expect(first.segmentCount == 2)
        #expect(first.goal?.remainingSeconds == 100)
        #expect(first.goal?.progress == 0.9)
        #expect(later.billableSeconds == 937)
        #expect(later.pausedSeconds == 300)
    }

    @Test
    func pausedBillableElapsedNeverAdvances() {
        let run = makeRun(state: .paused, goal: 1_800)
        let segments = [
            makeSegment(index: 1, start: 0, end: 600),
            makeSegment(index: 2, start: 900, end: 1_200),
        ]

        let first = WatchTimerMetrics.calculate(
            run: run,
            segments: segments,
            at: epoch.addingTimeInterval(1_300)
        )
        let later = WatchTimerMetrics.calculate(
            run: run,
            segments: segments,
            at: epoch.addingTimeInterval(1_900)
        )

        #expect(first.billableSeconds == 900)
        #expect(later.billableSeconds == 900)
        #expect(first.pausedSeconds == 400)
        #expect(later.pausedSeconds == 1_000)
    }

    @Test
    func goalStatesCoverNoGoalReachedAndOvertime() {
        let openRun = makeRun(state: .running, goal: nil)
        let reachedRun = makeRun(state: .paused, goal: 600)
        let overtimeRun = makeRun(state: .running, goal: 600)

        let open = WatchTimerMetrics.calculate(
            run: openRun,
            segments: [makeSegment(index: 1, start: 0, end: nil)],
            at: epoch.addingTimeInterval(500)
        )
        let reached = WatchTimerMetrics.calculate(
            run: reachedRun,
            segments: [makeSegment(index: 1, start: 0, end: 600)],
            at: epoch.addingTimeInterval(700)
        )
        let overtime = WatchTimerMetrics.calculate(
            run: overtimeRun,
            segments: [makeSegment(index: 1, start: 0, end: nil)],
            at: epoch.addingTimeInterval(725)
        )

        #expect(open.goal == nil)
        #expect(reached.goal?.isReached == true)
        #expect(reached.goal?.overtimeSeconds == 0)
        #expect(reached.goal?.progress == 1)
        #expect(overtime.goal?.isReached == true)
        #expect(overtime.goal?.overtimeSeconds == 125)
        #expect(overtime.goal?.progress == 1)
    }

    @Test
    func durationFormattingHandlesLargeValuesWithoutWrappingTheHour() {
        #expect(WatchDurationText.digital(0) == "0:00")
        #expect(WatchDurationText.digital(125) == "2:05")
        #expect(WatchDurationText.digital(3_661) == "1:01:01")
        #expect(WatchDurationText.digital(360_005) == "100:00:05")
        #expect(WatchDurationText.spoken(3_661, locale: Locale(identifier: "en_US")) == "1 hour, 1 minute, 1 second")
    }

    @Test
    func spokenDurationUsesLocaleAwareUnitsAndPlurals() {
        let english = Locale(identifier: "en_US")
        for (seconds, text) in [
            (0.0, "0 seconds"), (1, "1 second"), (2, "2 seconds"),
            (60, "1 minute"), (120, "2 minutes"), (3_600, "1 hour"),
            (7_200, "2 hours"), (360_005, "100 hours, 5 seconds"),
        ] {
            #expect(WatchDurationText.spoken(seconds, locale: english) == text)
        }
        // Formatting support is not a claim that the app ships translated UI.
        #expect(WatchDurationText.spoken(60, locale: Locale(identifier: "fr_FR")) == "1 minute")
        #expect(WatchDurationText.spoken(60, locale: Locale(identifier: "de_DE")) == "1 Minute")
    }

    @Test
    func durationFormattingRejectsInvalidIntervalsWithoutConversionTraps() {
        for seconds in [-1.0, -Double.greatestFiniteMagnitude, .infinity, -.infinity, .nan] {
            #expect(WatchDurationText.digital(seconds) == "0:00")
            #expect(WatchDurationText.spoken(seconds, locale: Locale(identifier: "en_US")) == "0 seconds")
        }
        #expect(WatchDurationText.digital(1.99) == "0:01")
        #expect(WatchDurationText.digital(.greatestFiniteMagnitude) == "2562047788015215:30:07")
    }

    @Test
    func elapsedUsesAbsoluteInstantsAcrossMidnightAndDaylightSavingChanges() throws {
        let parser = ISO8601DateFormatter()
        let beforeMidnight = try #require(parser.date(from: "2026-08-31T23:55:00-04:00"))
        let afterMidnight = try #require(parser.date(from: "2026-09-01T00:15:00-04:00"))
        let beforeFallback = try #require(parser.date(from: "2026-11-01T01:55:00-04:00"))
        let afterFallback = try #require(parser.date(from: "2026-11-01T01:05:00-05:00"))

        let midnightMetrics = WatchTimerMetrics.calculate(
            run: makeRun(state: .running, goal: nil, startedAt: beforeMidnight),
            segments: [makeSegment(index: 1, startedAt: beforeMidnight, endedAt: nil)],
            at: afterMidnight
        )
        let fallbackMetrics = WatchTimerMetrics.calculate(
            run: makeRun(state: .running, goal: nil, startedAt: beforeFallback),
            segments: [makeSegment(index: 2, startedAt: beforeFallback, endedAt: nil)],
            at: afterFallback
        )

        #expect(midnightMetrics.billableSeconds == 20 * 60)
        #expect(fallbackMetrics.billableSeconds == 10 * 60)
    }

    @Test
    func totalsRemainPhoneAuthoredAndFreshnessUsesTheSnapshotTimeZone() throws {
        let parser = ISO8601DateFormatter()
        let calculatedAt = try #require(parser.date(from: "2026-03-08T01:58:00-05:00"))
        let afterDSTJump = try #require(parser.date(from: "2026-03-08T03:02:00-04:00"))
        let nextDay = try #require(parser.date(from: "2026-03-09T00:01:00-04:00"))
        let totals = TimerTotalsSnapshot(
            todaySeconds: 2_700,
            weekSeconds: 14_400,
            calculatedAt: calculatedAt,
            calendarTimeZoneID: "America/New_York"
        )

        #expect(totals.todaySeconds == 2_700)
        #expect(totals.weekSeconds == 14_400)
        #expect(
            WatchTotalsFreshness.classify(
                totals,
                at: afterDSTJump,
                isReachable: true
            ) == .current
        )
        #expect(
            WatchTotalsFreshness.classify(
                totals,
                at: nextDay,
                isReachable: true,
                staleAfter: 24 * 60 * 60
            ) == .stale
        )
        #expect(
            WatchTotalsFreshness.classify(
                totals,
                at: afterDSTJump,
                isReachable: false
            ) == .offline
        )
    }

    @Test
    func reducedLuminanceIdentityUsesNeutralPrivacyCopy() {
        #expect(
            WatchProjectIdentity.displayName("Secret Client", redacted: false)
                == "Secret Client"
        )
        #expect(
            WatchProjectIdentity.displayName("Secret Client", redacted: true)
                == "Billable timer"
        )
    }

    private func makeRun(
        state: TimerRunState,
        goal: Int?,
        startedAt: Date? = nil
    ) -> TimerRunSnapshot {
        let startedAt = startedAt ?? epoch
        return TimerRunSnapshot(
            id: runID,
            workspaceID: nil,
            projectID: projectID,
            state: state,
            startedAt: startedAt,
            endedAt: nil,
            startTimeZoneID: "UTC",
            endTimeZoneID: nil,
            durationGoalSeconds: goal,
            normalizedNote: nil,
            tagIDs: [],
            originDeviceID: originID,
            revision: 1,
            lastAppliedMutationID: nil,
            createdAt: startedAt,
            updatedAt: startedAt,
            updatedTimeZoneID: "UTC"
        )
    }

    private func makeSegment(
        index: Int,
        runID: UUID? = nil,
        start: TimeInterval,
        end: TimeInterval?
    ) -> TimerSegmentSnapshot {
        makeSegment(
            index: index,
            runID: runID,
            startedAt: epoch.addingTimeInterval(start),
            endedAt: end.map(epoch.addingTimeInterval)
        )
    }

    private func makeSegment(
        index: Int,
        runID: UUID? = nil,
        startedAt: Date,
        endedAt: Date?
    ) -> TimerSegmentSnapshot {
        TimerSegmentSnapshot(
            id: UUID(uuidString: String(format: "40000000-0000-0000-0000-%012d", index))!,
            runID: runID ?? self.runID,
            workspaceID: nil,
            projectID: projectID,
            startedAt: startedAt,
            endedAt: endedAt,
            startTimeZoneID: "UTC",
            endTimeZoneID: endedAt == nil ? nil : "UTC",
            revision: 1
        )
    }
}
