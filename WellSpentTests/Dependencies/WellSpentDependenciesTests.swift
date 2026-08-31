import Foundation
import XCTest

@testable import WellSpent

final class WellSpentDependenciesTests: XCTestCase {
    func testFixedFixtureControlsTimeLocaleTimeZoneCalendarAndUUID() {
        let dependencies = DependencyFixtures.fixed()
        let calendar = dependencies.makeCalendar()

        XCTAssertEqual(dependencies.now, DependencyFixtures.fixedNow)
        XCTAssertEqual(dependencies.locale.identifier, "en_GB")
        XCTAssertEqual(dependencies.timeZone.identifier, "Europe/London")
        XCTAssertEqual(dependencies.makeUUID(), DependencyFixtures.fixedUUID)
        XCTAssertEqual(calendar.identifier, .gregorian)
        XCTAssertEqual(calendar.locale?.identifier, "en_GB")
        XCTAssertEqual(calendar.timeZone.identifier, "Europe/London")
        XCTAssertEqual(calendar.firstWeekday, 2)
        XCTAssertEqual(calendar.minimumDaysInFirstWeek, 4)
    }

    func testCalendarUsesInjectedLocaleAndTimeZoneWithoutLosingWeekRules() throws {
        let timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let dependencies = DependencyFixtures.fixed(
            locale: Locale(identifier: "en_US"),
            timeZone: timeZone,
            calendarIdentifier: .iso8601,
            firstWeekday: 7,
            minimumDaysInFirstWeek: 1
        )

        let calendar = dependencies.makeCalendar()

        XCTAssertEqual(calendar.identifier, .iso8601)
        XCTAssertEqual(calendar.locale?.identifier, "en_US")
        XCTAssertEqual(calendar.timeZone.identifier, "America/New_York")
        XCTAssertEqual(calendar.firstWeekday, 7)
        XCTAssertEqual(calendar.minimumDaysInFirstWeek, 1)
    }

    func testProvidersAreEvaluatedAtUseTime() {
        let firstNow = Date(timeIntervalSince1970: 100)
        let secondNow = Date(timeIntervalSince1970: 200)
        let callCount = LockedCounter()
        let dependencies = WellSpentDependencies(
            nowProvider: NowProvider {
                callCount.increment()
                return callCount.value == 1 ? firstNow : secondNow
            },
            localeProvider: LocaleProvider { .init(identifier: "en_US_POSIX") },
            timeZoneProvider: TimeZoneProvider { .gmt },
            calendarProvider: CalendarProvider { .init(identifier: .gregorian) },
            uuidProvider: UUIDProvider { DependencyFixtures.fixedUUID }
        )

        XCTAssertEqual(dependencies.now, firstNow)
        XCTAssertEqual(dependencies.now, secondNow)
        XCTAssertEqual(callCount.value, 2)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}
