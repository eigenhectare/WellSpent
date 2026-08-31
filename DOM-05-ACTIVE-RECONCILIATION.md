# DOM-05 active-session startup reconciliation

## Domain contract

`TimerCommandService.reconcileActiveState()` reconstructs the authoritative
timer state from persisted `TimeSessionRecord` values. The app executes the
same boundary during startup through `BillableHoursStartup`, and every Start,
Switch, and Stop command inspects it again before attempting a mutation.

Reconciliation has three deterministic outcomes:

- No active timed records returns `noActiveSession`.
- One active timed record returns its exact persisted snapshot without reading
  the clock, time zone, or UUID provider and without saving.
- Multiple active timed records return `reviewRequired`. The record with the
  latest `startAt` is the canonical active timer. Exact timestamp ties use
  ascending UUID text order, with the final record selected as canonical. All
  older records are returned oldest-first as conflicts.

Malformed records are deliberately not auto-ended or deleted. There is no
trustworthy end timestamp available during startup, so manufacturing one would
silently alter billable history. The startup root shows a generic recovery
banner, and mutating timer commands return `activeSessionReviewRequired` until
the affected records are explicitly repaired. Because the original records
remain active in SwiftData, the warning repeats after every restart until that
repair is persisted.

This design covers backgrounding, app termination, and device restart without
an in-memory active flag: elapsed time continues to derive from the stored
`startAt`. Production review/edit UI belongs to the later session-correction
experience; ActivityKit projection reconciliation remains ACT-04 scope.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM05-StartupReconciliation \
  -only-testing:BillableHoursTests/ActiveSessionReconciliationTests \
  test
```

The focused suite creates real temporary SwiftData stores, releases and
reopens their containers, and covers zero, one, multiple, equal-timestamp,
command-blocking, and explicit-repair cases.
