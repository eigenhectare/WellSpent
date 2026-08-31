# FND-04 deterministic dependencies

## Contract

`BillableHoursDependencies` is the app-level dependency container for values
that would otherwise make domain and reporting tests depend on wall-clock or
device state. It owns five narrow providers:

- `NowProvider` captures the current authoritative instant.
- `LocaleProvider` supplies the current locale.
- `TimeZoneProvider` supplies the current time zone.
- `CalendarProvider` supplies calendar identity and week-rule configuration.
- `UUIDProvider` generates stable application identifiers.

Production injects `BillableHoursDependencies.live` at the SwiftUI app root.
The live providers read autoupdating system locale, time zone, and calendar
values at use time. `makeCalendar()` overlays the injected locale and time zone
onto the injected calendar so tests can vary each input independently while
preserving configured week rules.

These dependencies provide inputs only. They do not own timer commands,
persistence repositories, reporting behavior, or UI state.

## Test fixtures

`BillableHoursTests/Support/DependencyFixtures.swift` provides fixed values for
time, locale, time zone, calendar rules, and UUIDs. The fixture is compiled only
into the unit-test target, keeping test conveniences out of the production app.

Tests that need a different boundary case should construct a fixture with the
specific locale, time zone, calendar identifier, first weekday, and
minimum-days-in-first-week required by that case. Tests should never mutate
global `Locale`, `TimeZone`, or `Calendar` state.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/FND04-Dependencies \
  -only-testing:BillableHoursTests/BillableHoursDependenciesTests \
  test
```
