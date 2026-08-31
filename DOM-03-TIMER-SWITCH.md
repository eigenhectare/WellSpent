# DOM-03 atomic timer Switch command

## Domain contract

`TimerCommandService.switchTimer(to:)` switches from the single persisted
active timed session to another active project as one logical command:

- The target project must exist and be active.
- Exactly one active timed session must exist. Missing or malformed
  multiple-active state is surfaced without mutation.
- Selecting the already-active project returns its persisted session and does
  not consume a clock, time-zone, or UUID input.
- A real switch captures one injected boundary timestamp and one time-zone
  identifier. The previous session's `endAt` and the new session's `startAt`
  use the exact same instant; their mutation/creation timestamps match it.
- Zero- or negative-duration completion boundaries are rejected.
- The old-session mutation and new-session insertion are sent through one
  SwiftData context save. A failed save rolls both back, leaving the old timer
  active and creating no partial new session.

Main-actor isolation serializes in-process timer mutations. ActivityKit remains
a later projection concern and is not changed by this issue.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM03-TimerSwitch \
  -only-testing:BillableHoursTests/TimerSwitchCommandServiceTests \
  test
```
