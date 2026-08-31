# DOM-07 session overlap detection

## Domain contract

`SessionOverlapDetector` is the pure, reusable source of overlap truth for
session warnings and future report/UI markers:

- Intervals are half-open: `[startAt, endAt)`.
- Two intervals overlap only when each starts before the other ends.
- Intervals that merely touch at a boundary are adjacent, not overlapping.
- An active interval has no stored end and is provisionally resolved to the
  single injected `activeEndAt` reference instant for the whole calculation.
- Empty, reversed, nonfinite, and self intervals do not produce overlap
  results. Domain commands separately reject malformed user input.
- Results include every overlapping pair and a stable, deduplicated list of
  every affected session ID.

Detection is informational. It never rejects a valid save, changes source
timestamps, merges sessions, removes duplicated time, or clamps totals to 24
hours. Reporting remains responsible for summing every source session in full.

`SessionCommandService` now delegates its preview and post-validation warning
lookups to this detector. The command captures the current time once and uses
that value both for future-time validation and as the active interval end.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM07-OverlapDetection \
  -only-testing:BillableHoursTests/SessionOverlapDetectorTests \
  -only-testing:BillableHoursTests/SessionCommandServiceTests \
  clean test
```

The focused suite covers nested, partial, identical, adjacent, active versus
manual, complete pair/marker discovery, edited-session exclusion, stable
deduplication, and malformed interval behavior. The existing DOM-06 tests
prove that warnings remain nonblocking through the SwiftData command boundary.
