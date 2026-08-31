# Production Live Activity lifecycle — ACT-02 through ACT-04

## Authority and projection

The SwiftData timed session remains authoritative. Start, Switch, and Stop
persist before the app asks `LiveActivityLifecycle` to change ActivityKit.
Request, update, or end failures therefore produce a recoverable projection
banner and never roll back, replace, or fabricate a session.

The persisted session UUID is also the ActivityKit attribute identity. Start
requests a running projection, Switch ends the previous projection at the
shared database boundary and requests the new one, and Stop ends the matching
projection with the first persisted end timestamp. Foreground reconciliation
ends duplicate/stale projections, updates the one exact match, recreates a
missing activity for a continuing timer, or removes all projections when no
timer is active.

## Lock Screen Stop handoff

The App Intent cannot assume the app process or its SwiftData context is
running. It therefore writes a content-free `BillableHoursStopRequest` as an
atomic JSON file in the shared App Group before ending the Live Activity. Each
request has its own file under
`Library/Application Support/BillableHours/StopHandoff`; it contains only the
session UUID, exact captured end timestamp, and time-zone identifier, with no
project name or note. Per-request files avoid relying on cross-process
`UserDefaults.synchronize()` and preserve first-write-wins behavior.

On activation or completion deep link, the app applies each pending request
through `TimerCommandService.stop(sessionID:capturedAt:endTimeZoneID:)`. The
handoff is acknowledged only after the authoritative save succeeds. A crash,
duplicate intent, or retry preserves the first timestamp. Completion UI is
routed only after SwiftData contains the stopped session. The ended activity's
widget URL remains the fallback when iOS does not foreground automatically.

Both the app and widget register the shared intent through
`AppIntentsPackage`. Their link settings force-load the static shared product so
the intent remains instantiable when iOS routes a repeated action through an
already-running host process.

## Eight-hour and foreground behavior

ActivityKit content uses a system timer derived from the persisted `startAt`;
the app never resets that timestamp. A continuing session older than eight
hours displays an in-app warning. Foreground reconciliation can recreate its
projection while leaving the source session unchanged. Activity dismissal,
expiration, disabled settings, and projection errors cannot stop or edit the
timer.

When authorization is disabled, the in-app recovery banner links directly to
the Billable Hours page in iPhone Settings while the persisted timer continues.
Transient projection failures retain a separate Retry action. Foreground
activation refreshes authorization and reconciles the projection after the
user returns from Settings.

Physical authentication, real suspended/terminated transitions, Dynamic
Island hardware, Always-On behavior, and the long-running soak are recorded in
the completed `IDK-323` release gate.

On 2026-08-29, the original physical failure sequence was verified on an
iPhone 17 Pro Max running iOS 26.6.1: Stop succeeded, the timer was restarted,
and a second Lock Screen Stop also succeeded. Both executions completed without
an App Intent error and left the app's Complete screen open. The wider process-
state matrix subsequently passed. On August 30, one authoritative timer ran
from 08:39:03 to 19:10:09 EDT (10:31:06), recovered with the long-running
warning after its Live Activity expired, and appeared once in Reports with the
same exact timestamps.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .derivedData/LiveActivityTests \
  -only-testing:BillableHoursTests/LiveActivityLifecycleTests \
  -only-testing:BillableHoursTests/TimerStopCommandServiceTests \
  test
```
