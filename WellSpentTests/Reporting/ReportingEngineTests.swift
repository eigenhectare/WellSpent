import Foundation
import XCTest

@testable import WellSpent

final class ReportingEngineTests: XCTestCase {
    private let engine = ReportingEngine()
    private let projectOneID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let projectTwoID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testIntersectionClipsToSelectedHalfOpenRangeAndRetainsSourceIdentity() throws {
        let calendar = calendar(timeZoneID: "UTC")
        let sessionID = UUID()
        let sourceStart = date(2026, 8, 21, 23, 30, calendar: calendar)
        let sourceEnd = date(2026, 8, 22, 1, 30, calendar: calendar)
        let range = DateInterval(
            start: date(2026, 8, 22, 0, 0, calendar: calendar),
            end: date(2026, 8, 22, 1, 0, calendar: calendar)
        )

        let segments = engine.segments(
            for: [session(id: sessionID, start: sourceStart, end: sourceEnd)],
            selection: ReportSelection(interval: range),
            calendar: calendar,
            now: sourceEnd
        )

        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].sessionID, sessionID)
        XCTAssertEqual(segments[0].sourceStartAt, sourceStart)
        XCTAssertEqual(segments[0].sourceEndAt, sourceEnd)
        XCTAssertEqual(segments[0].startAt, range.start)
        XCTAssertEqual(segments[0].endAt, range.end)
        XCTAssertEqual(segments[0].duration, 3_600, accuracy: 0.000_001)
    }

    func testCrossMidnightSessionSplitsAtLocalCalendarBoundary() {
        let calendar = calendar(timeZoneID: "America/New_York")
        let start = date(2026, 8, 21, 23, 30, calendar: calendar)
        let end = date(2026, 8, 22, 0, 30, calendar: calendar)
        let range = DateInterval(
            start: date(2026, 8, 21, 0, 0, calendar: calendar),
            end: date(2026, 8, 23, 0, 0, calendar: calendar)
        )

        let segments = engine.segments(
            for: [session(start: start, end: end)],
            selection: ReportSelection(interval: range),
            calendar: calendar,
            now: end
        )

        XCTAssertEqual(segments.map(\.duration), [1_800, 1_800])
        XCTAssertEqual(segments[0].endAt, date(2026, 8, 22, 0, 0, calendar: calendar))
        XCTAssertEqual(segments[0].sessionID, segments[1].sessionID)
    }

    func testSpringDSTDayIsTwentyThreeHoursWithoutAssumingTwentyFour() throws {
        let calendar = calendar(timeZoneID: "America/New_York")
        let interval = try XCTUnwrap(
            engine.dayInterval(
                containing: date(2026, 3, 8, 12, 0, calendar: calendar),
                calendar: calendar
            )
        )
        let segments = engine.segments(
            for: [session(start: interval.start, end: interval.end)],
            selection: ReportSelection(interval: interval),
            calendar: calendar,
            now: interval.end
        )

        XCTAssertEqual(interval.duration, 23 * 3_600, accuracy: 0.000_001)
        XCTAssertEqual(engine.total(of: segments), 23 * 3_600, accuracy: 0.000_001)
    }

    func testFallDSTDayIsTwentyFiveHoursWithoutAssumingTwentyFour() throws {
        let calendar = calendar(timeZoneID: "America/New_York")
        let interval = try XCTUnwrap(
            engine.dayInterval(
                containing: date(2026, 11, 1, 12, 0, calendar: calendar),
                calendar: calendar
            )
        )
        let segments = engine.segments(
            for: [session(start: interval.start, end: interval.end)],
            selection: ReportSelection(interval: interval),
            calendar: calendar,
            now: interval.end
        )

        XCTAssertEqual(interval.duration, 25 * 3_600, accuracy: 0.000_001)
        XCTAssertEqual(engine.total(of: segments), 25 * 3_600, accuracy: 0.000_001)
    }

    func testWeekBoundaryUsesConfiguredFirstWeekdayAndMinimumDays() throws {
        var mondayCalendar = calendar(timeZoneID: "UTC")
        mondayCalendar.firstWeekday = 2
        mondayCalendar.minimumDaysInFirstWeek = 4
        var sundayCalendar = mondayCalendar
        sundayCalendar.firstWeekday = 1
        sundayCalendar.minimumDaysInFirstWeek = 1
        let selected = date(2026, 1, 1, 12, 0, calendar: mondayCalendar)

        let mondayWeek = try XCTUnwrap(
            engine.weekInterval(containing: selected, calendar: mondayCalendar)
        )
        let sundayWeek = try XCTUnwrap(
            engine.weekInterval(containing: selected, calendar: sundayCalendar)
        )

        XCTAssertEqual(
            mondayWeek.start,
            date(2025, 12, 29, 0, 0, calendar: mondayCalendar)
        )
        XCTAssertEqual(
            sundayWeek.start,
            date(2025, 12, 28, 0, 0, calendar: sundayCalendar)
        )
    }

    func testActiveSessionUsesInjectedNowAndIsMarkedProvisional() {
        let calendar = calendar(timeZoneID: "UTC")
        let start = date(2026, 8, 22, 8, 0, calendar: calendar)
        let now = date(2026, 8, 22, 10, 15, calendar: calendar)
        let range = DateInterval(
            start: date(2026, 8, 22, 0, 0, calendar: calendar),
            end: date(2026, 8, 23, 0, 0, calendar: calendar)
        )

        let segments = engine.segments(
            for: [session(start: start, end: nil)],
            selection: ReportSelection(interval: range),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(engine.total(of: segments), 8_100, accuracy: 0.000_001)
        XCTAssertTrue(segments.allSatisfy(\.isActive))
        XCTAssertTrue(segments.allSatisfy { $0.sourceEndAt == nil })
    }

    func testOverlappingSessionsBothCountAndCarryVisibleMarkers() {
        let calendar = calendar(timeZoneID: "UTC")
        let dayStart = date(2026, 8, 22, 0, 0, calendar: calendar)
        let dayEnd = date(2026, 8, 23, 0, 0, calendar: calendar)
        let first = session(start: dayStart, end: dayEnd, projectID: projectOneID)
        let second = session(start: dayStart, end: dayEnd, projectID: projectTwoID)

        let segments = engine.segments(
            for: [first, second],
            selection: ReportSelection(interval: DateInterval(start: dayStart, end: dayEnd)),
            calendar: calendar,
            now: dayEnd
        )

        XCTAssertEqual(engine.total(of: segments), 48 * 3_600, accuracy: 0.000_001)
        XCTAssertTrue(segments.allSatisfy(\.overlapsAnotherSession))
        XCTAssertEqual(Set(segments.map(\.sessionID)), Set([first.id, second.id]))
    }

    func testAdjacentSessionsAreNotMarkedAsOverlaps() {
        let calendar = calendar(timeZoneID: "UTC")
        let start = date(2026, 8, 22, 8, 0, calendar: calendar)
        let boundary = date(2026, 8, 22, 9, 0, calendar: calendar)
        let end = date(2026, 8, 22, 10, 0, calendar: calendar)
        let range = DateInterval(
            start: date(2026, 8, 22, 0, 0, calendar: calendar),
            end: date(2026, 8, 23, 0, 0, calendar: calendar)
        )

        let segments = engine.segments(
            for: [session(start: start, end: boundary), session(start: boundary, end: end)],
            selection: ReportSelection(interval: range),
            calendar: calendar,
            now: end
        )

        XCTAssertFalse(segments.contains(where: \.overlapsAnotherSession))
        XCTAssertEqual(engine.total(of: segments), 7_200, accuracy: 0.000_001)
    }

    func testTimeZoneChangesPresentationBucketsWithoutChangingSourceTimestamps() {
        let utc = calendar(timeZoneID: "UTC")
        let pacific = calendar(timeZoneID: "America/Los_Angeles")
        let start = date(2026, 8, 22, 6, 30, calendar: utc)
        let end = date(2026, 8, 22, 7, 30, calendar: utc)
        let source = session(start: start, end: end)
        let range = DateInterval(
            start: date(2026, 8, 21, 0, 0, calendar: pacific),
            end: date(2026, 8, 23, 0, 0, calendar: pacific)
        )

        let segments = engine.segments(
            for: [source],
            selection: ReportSelection(interval: range),
            calendar: pacific,
            now: end
        )

        XCTAssertEqual(segments.count, 2)
        XCTAssertEqual(segments.first?.sourceStartAt, source.startAt)
        XCTAssertEqual(segments.last?.sourceEndAt, source.endAt)
        XCTAssertEqual(engine.total(of: segments), 3_600, accuracy: 0.000_001)
    }

    func testProjectFilterIncludesOnlySelectedProjectAndAggregateEqualsSegmentSum() {
        let calendar = calendar(timeZoneID: "UTC")
        let start = date(2026, 8, 22, 8, 0, calendar: calendar)
        let end = date(2026, 8, 22, 9, 0, calendar: calendar)
        let range = DateInterval(
            start: date(2026, 8, 22, 0, 0, calendar: calendar),
            end: date(2026, 8, 23, 0, 0, calendar: calendar)
        )
        let segments = engine.segments(
            for: [
                session(start: start, end: end, projectID: projectOneID),
                session(start: start, end: end, projectID: projectTwoID),
            ],
            selection: ReportSelection(interval: range, projectID: projectTwoID),
            calendar: calendar,
            now: end
        )

        XCTAssertEqual(Set(segments.map(\.projectID)), Set([projectTwoID]))
        XCTAssertEqual(
            engine.total(of: segments),
            segments.reduce(0) { $0 + $1.endAt.timeIntervalSince($1.startAt) },
            accuracy: 0.000_001
        )
    }

    func testEmptyAndInvalidRangesReturnNoSegments() {
        let calendar = calendar(timeZoneID: "UTC")
        let instant = date(2026, 8, 22, 8, 0, calendar: calendar)
        let source = session(start: instant.addingTimeInterval(-3_600), end: instant)

        XCTAssertTrue(
            engine.segments(
                for: [source],
                selection: ReportSelection(interval: DateInterval(start: instant, duration: 0)),
                calendar: calendar,
                now: instant
            ).isEmpty
        )
    }

    private func session(
        id: UUID = UUID(),
        start: Date,
        end: Date?,
        projectID: UUID? = nil
    ) -> TimeSessionSnapshot {
        TimeSessionSnapshot(
            id: id,
            projectID: projectID ?? projectOneID,
            source: end == nil ? .timer : .manual,
            startAt: start,
            endAt: end,
            startTimeZoneID: "UTC",
            endTimeZoneID: end == nil ? nil : "UTC",
            createdAt: start,
            updatedAt: end ?? start
        )
    }

    private func calendar(timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: timeZoneID)!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int,
        _ minute: Int,
        calendar: Calendar
    ) -> Date {
        calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
