import Foundation
import XCTest

@testable import WellSpent

/// QA-02's invariant suite deliberately computes expectations from source
/// intervals instead of using `ReportingEngine` helpers. This keeps the tests
/// capable of catching a shared segmentation or grouping defect.
final class ReportingInvariantTests: XCTestCase {
    private let engine = ReportingEngine()
    private let projectOneID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let projectTwoID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func testLocaleDerivedWeekBoundariesDifferAcrossTheYearBoundary() throws {
        let usCalendar = calendar(localeID: "en_US", timeZoneID: "UTC")
        let britishCalendar = calendar(localeID: "en_GB", timeZoneID: "UTC")
        let selected = date(2026, 1, 1, 12, 0, calendar: usCalendar)

        let usWeek = try XCTUnwrap(
            engine.weekInterval(containing: selected, calendar: usCalendar)
        )
        let britishWeek = try XCTUnwrap(
            engine.weekInterval(containing: selected, calendar: britishCalendar)
        )

        XCTAssertEqual(usWeek.start, date(2025, 12, 28, 0, 0, calendar: usCalendar))
        XCTAssertEqual(britishWeek.start, date(2025, 12, 29, 0, 0, calendar: britishCalendar))
        XCTAssertNotEqual(usWeek, britishWeek)
    }

    func testCrossYearWeekTotalsEqualTheThreeDisplayedDayBuckets() throws {
        var calendar = calendar(localeID: "en_GB", timeZoneID: "UTC")
        calendar.firstWeekday = 2
        calendar.minimumDaysInFirstWeek = 4
        let selection = try XCTUnwrap(
            engine.weekInterval(
                containing: date(2026, 1, 1, 12, 0, calendar: calendar),
                calendar: calendar
            )
        )
        let sessions = [
            session(
                id: uuid(1),
                start: date(2025, 12, 31, 23, 30, calendar: calendar),
                end: date(2026, 1, 1, 1, 30, calendar: calendar),
                projectID: projectOneID
            ),
            session(
                id: uuid(2),
                start: date(2026, 1, 4, 23, 30, calendar: calendar),
                end: date(2026, 1, 5, 0, 30, calendar: calendar),
                projectID: projectTwoID
            ),
        ]

        let segments = engine.segments(
            for: sessions,
            selection: ReportSelection(interval: selection),
            calendar: calendar,
            now: selection.end
        )
        let dayGroups = engine.segmentsByDay(segments, calendar: calendar)

        XCTAssertEqual(segments.map(\.duration), [1_800, 5_400, 1_800])
        XCTAssertEqual(dayGroups.count, 3)
        XCTAssertEqual(engine.total(of: segments), 9_000, accuracy: 0.000_001)
        XCTAssertEqual(
            dayGroups.values.reduce(0) { total, group in total + engine.total(of: group) },
            engine.total(of: segments),
            accuracy: 0.000_001
        )
    }

    func testLongSessionAcrossFallDSTProducesExactGreaterThanTwentyFourHourTotal() throws {
        let calendar = calendar(localeID: "en_US", timeZoneID: "America/New_York")
        let selection = DateInterval(
            start: date(2026, 10, 30, 0, 0, calendar: calendar),
            end: date(2026, 11, 3, 0, 0, calendar: calendar)
        )
        let source = session(
            id: uuid(3),
            start: selection.start,
            end: selection.end,
            projectID: projectOneID
        )

        let segments = engine.segments(
            for: [source],
            selection: ReportSelection(interval: selection),
            calendar: calendar,
            now: selection.end
        )

        XCTAssertEqual(segments.count, 4)
        XCTAssertEqual(segments.map(\.duration), [24, 24, 25, 24].map { TimeInterval($0 * 3_600) })
        XCTAssertEqual(engine.total(of: segments), 97 * 3_600, accuracy: 0.000_001)
        try assertReportInvariants(
            sessions: [source],
            selection: ReportSelection(interval: selection),
            calendar: calendar,
            now: selection.end
        )
    }

    func testActiveSessionAcrossSpringDSTUsesInjectedNowAndExactDayBuckets() throws {
        let calendar = calendar(localeID: "en_US", timeZoneID: "America/New_York")
        let selection = DateInterval(
            start: date(2026, 3, 7, 0, 0, calendar: calendar),
            end: date(2026, 3, 10, 0, 0, calendar: calendar)
        )
        let now = date(2026, 3, 9, 12, 0, calendar: calendar)
        let source = session(
            id: uuid(4),
            start: date(2026, 3, 6, 20, 0, calendar: calendar),
            end: nil,
            projectID: projectOneID
        )

        let segments = engine.segments(
            for: [source],
            selection: ReportSelection(interval: selection),
            calendar: calendar,
            now: now
        )

        XCTAssertEqual(segments.map(\.duration), [24, 23, 12].map { TimeInterval($0 * 3_600) })
        XCTAssertEqual(engine.total(of: segments), 59 * 3_600, accuracy: 0.000_001)
        XCTAssertTrue(segments.allSatisfy(\.isActive))
        try assertReportInvariants(
            sessions: [source],
            selection: ReportSelection(interval: selection),
            calendar: calendar,
            now: now
        )
    }

    func testGeneratedCalendarMatrixMaintainsAllReportInvariants() throws {
        let scenarios = [
            CalendarScenario(localeID: "en_US", timeZoneID: "UTC", year: 2026, month: 1, day: 1),
            CalendarScenario(
                localeID: "en_US",
                timeZoneID: "America/New_York",
                year: 2026,
                month: 3,
                day: 8
            ),
            CalendarScenario(
                localeID: "en_GB",
                timeZoneID: "Europe/London",
                year: 2026,
                month: 10,
                day: 25
            ),
            CalendarScenario(
                localeID: "en_AU",
                timeZoneID: "Australia/Lord_Howe",
                year: 2026,
                month: 10,
                day: 4
            ),
            CalendarScenario(
                localeID: "en_NZ",
                timeZoneID: "Pacific/Chatham",
                year: 2026,
                month: 9,
                day: 27
            ),
            CalendarScenario(
                localeID: "ne_NP",
                timeZoneID: "Asia/Kathmandu",
                year: 2026,
                month: 8,
                day: 22
            ),
        ]

        for (index, scenario) in scenarios.enumerated() {
            let calendar = calendar(
                localeID: scenario.localeID,
                timeZoneID: scenario.timeZoneID
            )
            let anchor = date(
                scenario.year,
                scenario.month,
                scenario.day,
                12,
                0,
                calendar: calendar
            )
            let week = try XCTUnwrap(
                engine.weekInterval(containing: anchor, calendar: calendar),
                "Missing week for \(scenario.timeZoneID)"
            )
            let now = week.start.addingTimeInterval(week.duration * 0.8)
            let sessions = generatedSessions(
                in: week,
                scenarioIndex: index
            )

            try assertReportInvariants(
                sessions: sessions,
                selection: ReportSelection(interval: week),
                calendar: calendar,
                now: now
            )
            try assertReportInvariants(
                sessions: sessions,
                selection: ReportSelection(interval: week, projectID: projectOneID),
                calendar: calendar,
                now: now
            )
        }
    }

    private func assertReportInvariants(
        sessions: [TimeSessionSnapshot],
        selection: ReportSelection,
        calendar: Calendar,
        now: Date,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let segments = engine.segments(
            for: sessions,
            selection: selection,
            calendar: calendar,
            now: now
        )
        let expectedBySession = Dictionary(
            uniqueKeysWithValues: sessions.map { source in
                (source.id, independentlyClippedDuration(source, selection: selection, now: now))
            }
        )
        let includedSessions = sessions.filter {
            (selection.projectID == nil || $0.projectID == selection.projectID)
                && (expectedBySession[$0.id] ?? 0) > 0
        }
        let expectedTotal = includedSessions.reduce(0) {
            $0 + (expectedBySession[$1.id] ?? 0)
        }

        XCTAssertEqual(engine.total(of: segments), expectedTotal, accuracy: 0.000_001, file: file, line: line)
        XCTAssertEqual(Set(segments.map(\.sessionID)), Set(includedSessions.map(\.id)), file: file, line: line)
        XCTAssertTrue(segments.allSatisfy { $0.duration > 0 }, file: file, line: line)
        XCTAssertTrue(
            segments.allSatisfy {
                $0.startAt >= selection.interval.start && $0.endAt <= selection.interval.end
            },
            file: file,
            line: line
        )
        if let projectID = selection.projectID {
            XCTAssertTrue(segments.allSatisfy { $0.projectID == projectID }, file: file, line: line)
        }

        for segment in segments {
            let day = try XCTUnwrap(
                calendar.dateInterval(of: .day, for: segment.startAt),
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(segment.startAt, day.start, file: file, line: line)
            XCTAssertLessThanOrEqual(segment.endAt, day.end, file: file, line: line)
            let source = try XCTUnwrap(
                sessions.first { $0.id == segment.sessionID },
                file: file,
                line: line
            )
            XCTAssertEqual(segment.sourceStartAt, source.startAt, file: file, line: line)
            XCTAssertEqual(segment.sourceEndAt, source.endAt, file: file, line: line)
        }

        for source in includedSessions {
            let sourceTotal =
                segments
                .filter { $0.sessionID == source.id }
                .reduce(0) { $0 + $1.duration }
            XCTAssertEqual(
                sourceTotal,
                expectedBySession[source.id] ?? 0,
                accuracy: 0.000_001,
                file: file,
                line: line
            )
        }

        let projectGroups = engine.segmentsByProject(segments)
        XCTAssertEqual(
            projectGroups.values.flatMap { $0 }.count,
            segments.count,
            file: file,
            line: line
        )
        XCTAssertEqual(
            projectGroups.values.reduce(0) { $0 + engine.total(of: $1) },
            engine.total(of: segments),
            accuracy: 0.000_001,
            file: file,
            line: line
        )

        let dayGroups = engine.segmentsByDay(segments, calendar: calendar)
        XCTAssertEqual(dayGroups.values.flatMap { $0 }.count, segments.count, file: file, line: line)
        XCTAssertEqual(
            dayGroups.values.reduce(0) { $0 + engine.total(of: $1) },
            engine.total(of: segments),
            accuracy: 0.000_001,
            file: file,
            line: line
        )
        for (day, group) in dayGroups {
            XCTAssertTrue(
                group.allSatisfy { calendar.startOfDay(for: $0.startAt) == day },
                file: file,
                line: line
            )
        }

        for (first, second) in zip(segments, segments.dropFirst()) {
            XCTAssertTrue(
                first.startAt < second.startAt
                    || (first.startAt == second.startAt && first.endAt <= second.endAt),
                file: file,
                line: line
            )
        }
    }

    private func independentlyClippedDuration(
        _ session: TimeSessionSnapshot,
        selection: ReportSelection,
        now: Date
    ) -> TimeInterval {
        guard selection.projectID == nil || session.projectID == selection.projectID else {
            return 0
        }
        let resolvedEnd = session.endAt ?? now
        guard resolvedEnd > session.startAt else { return 0 }
        let start = max(session.startAt, selection.interval.start)
        let end = min(resolvedEnd, selection.interval.end)
        return max(0, end.timeIntervalSince(start))
    }

    private func generatedSessions(
        in selection: DateInterval,
        scenarioIndex: Int
    ) -> [TimeSessionSnapshot] {
        let span = selection.duration
        let baseID = scenarioIndex * 10
        return [
            session(
                id: uuid(baseID + 1),
                start: selection.start.addingTimeInterval(-1_800),
                end: selection.start.addingTimeInterval(span * 0.2),
                projectID: projectOneID
            ),
            session(
                id: uuid(baseID + 2),
                start: selection.start.addingTimeInterval(span * 0.15),
                end: selection.start.addingTimeInterval(span * 0.55),
                projectID: projectTwoID
            ),
            session(
                id: uuid(baseID + 3),
                start: selection.start.addingTimeInterval(span * 0.3),
                end: selection.start.addingTimeInterval(span * 0.42),
                projectID: projectOneID
            ),
            session(
                id: uuid(baseID + 4),
                start: selection.start.addingTimeInterval(span * 0.7),
                end: nil,
                projectID: projectOneID
            ),
            session(
                id: uuid(baseID + 5),
                start: selection.end.addingTimeInterval(3_600),
                end: selection.end.addingTimeInterval(7_200),
                projectID: projectTwoID
            ),
        ]
    }

    private func session(
        id: UUID,
        start: Date,
        end: Date?,
        projectID: UUID
    ) -> TimeSessionSnapshot {
        TimeSessionSnapshot(
            id: id,
            projectID: projectID,
            source: end == nil ? .timer : .manual,
            startAt: start,
            endAt: end,
            startTimeZoneID: "Fixture/Start",
            endTimeZoneID: end == nil ? nil : "Fixture/End",
            createdAt: start,
            updatedAt: end ?? start
        )
    }

    private func calendar(localeID: String, timeZoneID: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: localeID)
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

    private func uuid(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}

private struct CalendarScenario {
    let localeID: String
    let timeZoneID: String
    let year: Int
    let month: Int
    let day: Int
}
