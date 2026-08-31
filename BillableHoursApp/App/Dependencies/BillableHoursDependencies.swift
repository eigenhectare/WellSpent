import Foundation
import SwiftUI

struct NowProvider: Sendable {
    private let value: @Sendable () -> Date

    init(_ value: @escaping @Sendable () -> Date) {
        self.value = value
    }

    func now() -> Date {
        value()
    }

    static let live = NowProvider {
        Date()
    }
}

struct LocaleProvider: Sendable {
    private let value: @Sendable () -> Locale

    init(_ value: @escaping @Sendable () -> Locale) {
        self.value = value
    }

    func current() -> Locale {
        value()
    }

    static let live = LocaleProvider {
        .autoupdatingCurrent
    }
}

struct TimeZoneProvider: Sendable {
    private let value: @Sendable () -> TimeZone

    init(_ value: @escaping @Sendable () -> TimeZone) {
        self.value = value
    }

    func current() -> TimeZone {
        value()
    }

    static let live = TimeZoneProvider {
        .autoupdatingCurrent
    }
}

struct CalendarProvider: Sendable {
    private let value: @Sendable () -> Calendar

    init(_ value: @escaping @Sendable () -> Calendar) {
        self.value = value
    }

    func current() -> Calendar {
        value()
    }

    static let live = CalendarProvider {
        .autoupdatingCurrent
    }
}

struct UUIDProvider: Sendable {
    private let value: @Sendable () -> UUID

    init(_ value: @escaping @Sendable () -> UUID) {
        self.value = value
    }

    func generate() -> UUID {
        value()
    }

    static let live = UUIDProvider {
        UUID()
    }
}

struct BillableHoursDependencies: Sendable {
    let nowProvider: NowProvider
    let localeProvider: LocaleProvider
    let timeZoneProvider: TimeZoneProvider
    let calendarProvider: CalendarProvider
    let uuidProvider: UUIDProvider

    init(
        nowProvider: NowProvider,
        localeProvider: LocaleProvider,
        timeZoneProvider: TimeZoneProvider,
        calendarProvider: CalendarProvider,
        uuidProvider: UUIDProvider
    ) {
        self.nowProvider = nowProvider
        self.localeProvider = localeProvider
        self.timeZoneProvider = timeZoneProvider
        self.calendarProvider = calendarProvider
        self.uuidProvider = uuidProvider
    }

    var now: Date {
        nowProvider.now()
    }

    var locale: Locale {
        localeProvider.current()
    }

    var timeZone: TimeZone {
        timeZoneProvider.current()
    }

    func makeCalendar() -> Calendar {
        var calendar = calendarProvider.current()
        calendar.locale = locale
        calendar.timeZone = timeZone
        return calendar
    }

    func makeUUID() -> UUID {
        uuidProvider.generate()
    }

    static let live = BillableHoursDependencies(
        nowProvider: .live,
        localeProvider: .live,
        timeZoneProvider: .live,
        calendarProvider: .live,
        uuidProvider: .live
    )
}

private struct BillableHoursDependenciesKey: EnvironmentKey {
    static let defaultValue = BillableHoursDependencies.live
}

extension EnvironmentValues {
    var billableHoursDependencies: BillableHoursDependencies {
        get { self[BillableHoursDependenciesKey.self] }
        set { self[BillableHoursDependenciesKey.self] = newValue }
    }
}
