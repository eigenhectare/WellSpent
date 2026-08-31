# FND-02 Live Activity interaction spike

> Historical feasibility record: the temporary spike storage described below
> has been superseded for production by the content-free durable Stop handoff
> and SwiftData acknowledgement flow in `LIVE-ACTIVITY-LIFECYCLE.md`.

## Scope and design under test

This spike tests the critical interaction described in `PROJECT_PLAN.md`; it is
not the production timer, persistence layer, completion screen, or final Live
Activity design.

- `StopBillableTimerIntent` is a `LiveActivityIntent` exposed by the Lock
  Screen and Dynamic Island presentations.
- The intent requires local-device authentication, requests foreground launch,
  captures one `Date` when `perform()` begins, persists it, reads it back, and
  only then ends the ActivityKit projection.
- Repeated Stop execution is idempotent: the first persisted end timestamp wins.
- The intent writes a pending completion ID to the shared App Group. The app
  briefly reconciles that handoff on foreground to cover process-ordering races.
- The ended activity says `Stopped — tap to complete` and routes through
  `billablehours://completion/<activity-id>` as the tap-to-open fallback.

The timestamp assumption that still needs physical confirmation is explicit:
the exact stop time is the instant the App Intent begins executing after any
authentication required by iOS, not the initial locked-screen touch time.

## Temporary signing and persistence

The bundle IDs remain under `com.example.billablehours.fnd01`, and the temporary
App Group is `group.com.example.billablehours.fnd02`. They work with local
simulator signing but are not registered for a developer account. Before a
physical run, replace them with unique identifiers owned by the chosen Apple
Developer team, enable the same App Group on the app and extension, and set the
development team in `project.yml`.

The spike stores only `activityID`, `startedAt`, and `endedAt` in App Group
`UserDefaults`. FND-03 owns the versioned SwiftData schema; this store must not
be promoted to production persistence.

## Current-iOS validation scope and accepted residual risk

The project supports only the current iOS major. Automated build, persistence,
intent-logic, launch, and deep-link coverage runs on the native Xcode iOS 26.5
simulator. iOS 17 and iOS 18 are not product or QA targets.

For FND-02, the verified simulator evidence is sufficient to accept the spike
and continue development. On 2026-08-21, the product owner explicitly accepted
the residual risk of deferring the physical-device portion until they regain
access to this Mac and an iPhone. This decision does not convert simulator
evidence into physical evidence and does not remove the release gate.

The following behavior remains unverified on a physical iPhone:

- biometric/passcode authentication before the intent executes;
- foreground, background, suspended, and terminated process transitions;
- Lock Screen and Dynamic Island presentation behavior; and
- automatic foreground routing and the ended-card tap-to-open fallback.

These checks are tracked by Linear issue `IDK-323` / `QA-03`, which remains a
current-iOS physical-device and release-soak gate. Prefer a Dynamic-Island
device so both Lock Screen and Dynamic Island presentations can be observed in
the same pass.

On that current-iOS device, run Stop with the app foregrounded, backgrounded,
suspended, and terminated. Exercise unlocked and locked states. Record whether:

1. The locked device requests authentication before execution.
2. The stored `endedAt` is present and unchanged after relaunch.
3. The ended Live Activity uses the same timestamp.
4. iOS transitions to the app's completion route when permitted.
5. When foreground transition is unavailable, tapping the ended card opens the
   same completion route.

The current product baseline is iOS 26.0. A later baseline change requires an
explicit product and QA decision rather than compatibility testing against
older iOS majors.

## Repeatable verification commands

Regenerate and clean-build the app plus embedded extension for the simulator:

```sh
cd '/Users/dev/Documents/Billable Hours App'
xcodegen generate --spec project.yml
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/BillableHoursFND02DerivedData \
  clean build

xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/BillableHoursFND02ReleaseDerivedData \
  clean build
```

Compile the device architecture without claiming that it was installed or run:

```sh
cd '/Users/dev/Documents/Billable Hours App'
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/BillableHoursFND02DeviceDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

Run the unit and UI suites on the local simulator:

```sh
cd '/Users/dev/Documents/Billable Hours App'
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/BillableHoursFND02DerivedData \
  test -only-testing:BillableHoursTests

xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath /tmp/BillableHoursFND02DerivedData \
  test -only-testing:BillableHoursUITests
```

Discover physical prerequisites before the manual matrix:

```sh
xcrun devicectl list devices
security find-identity -v -p codesigning
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -showdestinations
```

## Evidence from 2026-08-20

- Clean Debug simulator app/extension build: passed.
- Clean Release simulator app/extension build: passed.
- Clean unsigned arm64 iPhoneOS SDK build: passed.
- Unit tests on iPhone 17 Pro / iOS 26.5 simulator: 3 passed, 0 failed.
- UI tests on iPhone 17 Pro / iOS 26.5 simulator: 3 passed, 0 failed. They
  cover launch, start plus the in-app execution of the same Stop logic, and a
  terminated-app custom completion URL launch.
- A combined scheme-wide `xcodebuild test` invocation hung before test workers
  materialized and was interrupted. The isolated unit and UI commands above are
  the verified, repeatable paths with this Xcode/runtime combination.
- Compiler/metadata warning scan for product targets: no warnings.
- Physical discovery: `xcrun devicectl list devices` returned `No devices
  found.`
- Signing discovery: `security find-identity -v -p codesigning` returned `0
  valid identities found`.

Therefore lock-screen authentication, physical foreground transition,
ended-card fallback, and the foreground/background/suspended/terminated
physical matrix have not been run. FND-02 is accepted on the simulator evidence
above with that residual risk documented; `IDK-323` owns the deferred physical
validation and must pass before release.

## Physical-device addendum — 2026-08-29

This addendum supersedes the no-device status above for the exact repeated-Stop
failure path. The broader `IDK-323` matrix and eight-hour soak remain open.

The signed app and widget were installed on Drew's iPhone 17 Pro Max running
iOS 26.6.1 with bundle IDs `com.drewreilly.billablehours` and
`com.drewreilly.billablehours.widgets`, App Group
`group.com.drewreilly.billablehours`, and development team `68LEY459MW`.

The physical run reproduced the reported sequence: the first Lock Screen Stop
succeeded, then Stop on a restarted timer did nothing. Device Console showed
that the second action was routed through the already-running app process, where
iOS could not instantiate `BillableHoursShared.StopBillableTimerIntent` by its
mangled type name because the static shared-product symbols had been stripped
from that process. The production fix registers the shared intent through
`AppIntentsPackage` declarations in both host targets and force-loads the shared
product into the app and widget binaries.

That exposed a second device-only handoff failure: the intent was found and
invoked, but App Group `UserDefaults.synchronize()` returned false before the
app could consume the request. The production handoff now uses one atomically
written, content-free JSON file per request under
`Library/Application Support/BillableHours/StopHandoff` in the App Group
container. The app removes the exact request file only after the authoritative
SwiftData Stop save succeeds.

Final physical validation repeated the original sequence exactly:

1. Start a timer and stop it from the Lock Screen; the Complete screen appears
   and remains open.
2. Skip completion, restart the timer while the app process remains available,
   lock the phone, and press Stop again; the Complete screen again appears and
   remains open.

For both actions, Console recorded `StopBillableTimerIntent.perform() finished`,
`BackgroundShortcutRunner` with `error: false`, and `chronod` reporting that the
action ran successfully. The second successful execution was recorded at
18:04:22 local time.

Focused tests on the same iPhone passed 3 of 3, including intent-package
registration, 50 concurrent handoff cycles, and an atomic round trip through
the real production App Group. Result bundle:

`/Users/dev/Documents/Billable Hours App/.derivedData/DeviceTests/Logs/Test/Test-BillableHours-2026.08.29_18-01-53--0400.xcresult`

Simulator regression evidence after the device fix includes 94 unit tests with
zero failures. The 31 UI/accessibility scenarios also passed across the full
run and focused reruns; one transient report contrast audit passed unchanged on
rerun, and the largest-text onboarding test was corrected to dismiss the
software keyboard before tapping the button it covered on the Pro Max
simulator. Unit result bundle:

`/Users/dev/Documents/Billable Hours App/.derivedData/CI/TestsProMax/Logs/Test/Test-BillableHours-2026.08.29_18-15-13--0400.xcresult`

Still pending before release: the complete foreground/background/suspended/
terminated and locked/unlocked matrix, Dynamic Island and Always-On checks, the
ended-card fallback in every unavailable-foreground condition, and the full
eight-hour soak. This addendum proves the original Stop → restart → Stop defect
is fixed; it does not claim those remaining gates are complete.
