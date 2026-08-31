# DOM-02 timer Start command

## Domain contract

`TimerCommandService.start(projectID:)` is the sole Start mutation boundary.
It reads persisted SwiftData state on every invocation and enforces these rules:

- The target project must exist and be active.
- A new Start captures the injected clock exactly once. That value is used for
  `startAt`, `createdAt`, and `updatedAt` without rounding or recomputation.
- The injected UUID and current time-zone identifier are captured only when a
  new session is required.
- The project workspace identifier is copied to the new session.
- The session is saved before a success result is returned. Save failure rolls
  back the context and produces no success state.
- Repeating Start for the already-active project returns the persisted session
  with an `alreadyActive` disposition and creates nothing.
- Starting a different project while one is active returns
  `activeSessionRequiresSwitch`; DOM-03 will own the atomic Switch behavior.
- Malformed multiple-active state is surfaced without creating another record;
  DOM-05 will own deterministic reconciliation.

The command is main-actor isolated so concurrent in-process Start requests are
serialized. Persisted `TimeSessionRecord` data remains authoritative; future UI
must not maintain an independent active flag.

This issue does not implement Stop, Switch, startup reconciliation, timer UI,
Live Activity lifecycle integration, or elapsed-time rendering.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM02-TimerStart \
  -only-testing:BillableHoursTests/TimerCommandServiceTests \
  test
```
