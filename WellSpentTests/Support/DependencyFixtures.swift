import Foundation

@testable import WellSpent

enum DependencyFixtures {
    @MainActor
    static func disconnectedWatch(_ store: PhoneWatchSyncStore) -> IPhoneWatchConnectivityCoordinator {
        IPhoneWatchConnectivityCoordinator(
            syncStore: store, session: UITestDisconnectedWatchSession(), now: { fixedNow })
    }

    static let fixedNow = Date(timeIntervalSince1970: 1_735_732_800.125)
    static let fixedLocale = Locale(identifier: "en_GB")
    static let fixedTimeZone = TimeZone(identifier: "Europe/London")!
    static let fixedUUID = UUID(uuidString: "D45B7B8E-4EA6-44B6-AF40-BE8CB611DA2A")!

    static func fixed(
        now: Date = fixedNow,
        locale: Locale = fixedLocale,
        timeZone: TimeZone = fixedTimeZone,
        uuid: UUID = fixedUUID,
        calendarIdentifier: Calendar.Identifier = .gregorian,
        firstWeekday: Int = 2,
        minimumDaysInFirstWeek: Int = 4
    ) -> WellSpentDependencies {
        WellSpentDependencies(
            nowProvider: NowProvider { now },
            localeProvider: LocaleProvider { locale },
            timeZoneProvider: TimeZoneProvider { timeZone },
            calendarProvider: CalendarProvider {
                var calendar = Calendar(identifier: calendarIdentifier)
                calendar.firstWeekday = firstWeekday
                calendar.minimumDaysInFirstWeek = minimumDaysInFirstWeek
                return calendar
            },
            uuidProvider: UUIDProvider { uuid }
        )
    }
}
