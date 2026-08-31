# DOM-04 idempotent timer Stop command

## Domain contract

`TimerCommandService.stop(sessionID:)` is the shared, path-independent Stop
boundary for the foreground app and future Live Activity App Intent adapter.
The persisted session UUID is its idempotency key:

- The target must exist and be a timed session.
- The first invocation for an active session captures one injected end instant
  and time-zone identifier, validates positive duration, and saves before
  returning success.
- A save failure rolls back the end fields and leaves the timer active. A later
  successful retry captures its own timestamp, which becomes the winner.
- Every later invocation with the same session UUID returns the already-saved
  completed session without reading a new clock/time zone or changing its end.
- `stopActive()` is a foreground convenience. An App Intent or any caller that
  may retry must retain and pass the session UUID to `stop(sessionID:)`.
- Missing, manual, multiple-active, and invalid-boundary states are explicit
  errors and never produce a success projection.

All command methods are main-actor isolated, serializing app and App Intent
requests that enter the app's command boundary. Connecting the production
App Intent and ActivityKit lifecycle remains ACT-03 scope; the FND-02 spike
store remains isolated until that integration.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM04-TimerStop \
  -only-testing:BillableHoursTests/TimerStopCommandServiceTests \
  test
```
