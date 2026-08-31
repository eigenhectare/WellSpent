# Development

## Requirements

- Xcode 26.6 (build 17F113) with the iOS 26.5 SDK and simulator runtime.
- Swift 6.3.3 as bundled with Xcode.
- XcodeGen 2.45.4 from the existing local toolchain.

No third-party runtime dependencies are used.

## Continuous integration and formatting

The checked-in `.github/workflows/ci.yml` workflow and local `scripts/ci.sh`
entry point run the same strict format, clean Debug/Release simulator build,
and full unit-test gates without production credentials:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer scripts/ci.sh
```

Run only the Apple `swift-format` lint gate with `scripts/lint.sh`. See
[FND-05-CI.md](FND-05-CI.md) for the pipeline contract, runner assumptions,
clean-checkout verification, and simulator override.

## Generate the Xcode project

`project.yml` is the source of truth for targets, settings, configurations, and
shared schemes. Regenerate the checked-in Xcode project after changing it:

```sh
cd '/Users/dev/Documents/Billable Hours App'
xcodegen generate --spec project.yml
```

## Build

The commands below use the locally available iPhone 17 Pro simulator on iOS
26.5 and keep derived data inside the ignored `.derivedData` directory.

Clean Debug build of the app (which also embeds and builds the extension):

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .derivedData/App-Debug \
  clean build
```

Clean Debug build of the widget/Live Activity extension target:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHoursWidgets \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -derivedDataPath .derivedData/Widgets-Debug \
  clean build
```

Release builds:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData/App-Release \
  clean build

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHoursWidgets \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath .derivedData/Widgets-Release \
  clean build
```

Unsigned arm64 device-SDK compile check (this does not install or validate on a
physical iPhone):

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'generic/platform=iOS' \
  -derivedDataPath .derivedData/Device-Compile \
  CODE_SIGNING_ALLOWED=NO \
  clean build
```

## Test

Unit tests:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -derivedDataPath .derivedData/UnitTests \
  -only-testing:BillableHoursTests \
  test
```

UI smoke test:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 60 \
  -maximum-test-execution-time-allowance 120 \
  -derivedDataPath .derivedData/UITests \
  -only-testing:BillableHoursUITests \
  test
```

Accessibility audit matrix:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/Accessibility \
  -only-testing:BillableHoursUITests/BillableHoursAccessibilityUITests \
  clean test
```

See [ACCESSIBILITY.md](ACCESSIBILITY.md) for the audited flow matrix, the Dark
Mode and Increase Contrast commands, documented system-owned exclusions, and
the remaining manual VoiceOver and Reduce Motion gate.

## Temporary foundation decisions

- The deployment target is iOS 26.0. The project intentionally supports only
  the current iOS major; iOS 17 and iOS 18 are no longer product or QA targets.
- Device builds use the `com.drewreilly.billablehours` bundle namespace and
  `group.com.drewreilly.billablehours` App Group with development team
  `68LEY459MW`.
- Xcode automatic signing owns the development provisioning profiles for the
  app and widget targets. Simulator builds continue to use Xcode's local
  signing path and do not require Apple developer services.
- The statically linked shared framework owns ActivityKit attributes, the Stop
  App Intent, deep-link value, and the content-free durable Stop handoff. The
  app acknowledges a handoff only after the exact timestamp is saved through
  the authoritative SwiftData timer command.
- FND-02 is accepted on verified current-iOS simulator evidence. Physical
  Lock Screen authentication, real process-state transitions, Dynamic Island
  behavior, and the ended-card fallback remain unverified and are explicitly
  deferred to `IDK-323` / `QA-03` as a release gate. No simulator result should
  be reported as physical-device evidence.
- Debug Dylib Support is disabled for the app target so app-hosted XCTest loads
  deterministically with the current Xcode 26.6/iOS 26.5 simulator toolchain.
  Re-evaluate this compatibility setting when the local Xcode/runtime changes.
- Production ActivityKit lifecycle/command integration is implemented.
  Calendar integration and iCloud sync remain later milestones.
- `BillableHoursDependencies.live` is injected at the app root. Domain and
  reporting work should receive time, locale, time zone, calendar, and UUID
  inputs through that container rather than reading mutable system globals.
  Deterministic fixture helpers remain in the unit-test target only.

See [FND-02-SPIKE.md](FND-02-SPIKE.md) for the interaction design, accepted
simulator evidence, residual risk, and deferred current-iOS physical check.

## SwiftData persistence foundation

The app root now opens the versioned SwiftData v2 store through
`BillableHoursMigrationPlan`. Tests use the same construction path with either
an in-memory configuration or an explicit temporary store URL. The standard
unit-test command above runs schema initialization, disk-container recreation,
and oldest-version fixture coverage in addition to the Live Activity spike
tests.

See [FND-03-PERSISTENCE.md](FND-03-PERSISTENCE.md) for the current schema contract,
CloudKit-compatibility assumptions, migration rules, and focused verification
command.

## Deterministic dependency foundation

The dependency container exposes production system providers and resolves a
calendar by combining the injected calendar configuration, locale, and time
zone. This lets future timer and reporting tests control every boundary input
without changing production UI behavior.

See [FND-04-DEPENDENCIES.md](FND-04-DEPENDENCIES.md) for the provider contract,
test-fixture rules, and focused verification command.

## Project domain

Project views must use `ProjectQueryService` and `ProjectCommandService`; they
must not mutate `ProjectRecord` directly. Archived projects remain queryable,
exact duplicate names surface as nonblocking command warnings, and an optional
single emoji plus color token can identify each project.

See [DOM-01-PROJECTS.md](DOM-01-PROJECTS.md) for validation, timestamp,
archive, history-retention, and focused-test details.

## Timer Start domain

Timer Start consumers must use `TimerCommandService`. The service derives
active state from persisted sessions, saves before returning success, and
returns the existing persisted session for a repeated Start on the same
project. Starting another project requires the later atomic Switch command.

See [DOM-02-TIMER-START.md](DOM-02-TIMER-START.md) for timestamp, persistence,
one-active-session, failure, and focused-test details.

## Atomic timer Switch domain

Switch consumers must use `TimerCommandService.switchTimer(to:)`. A real
switch completes the old session and starts the new one at a single exact
boundary, then persists both changes in one context save. Selecting the
already-active project is an idempotent no-op.

See [DOM-03-TIMER-SWITCH.md](DOM-03-TIMER-SWITCH.md) for boundary validation,
rollback behavior, rapid-switch coverage, and the focused-test command.

## Idempotent timer Stop domain

Foreground and future App Intent consumers must stop through
`TimerCommandService.stop(sessionID:)` using the persisted session UUID as the
idempotency key. The first successful save fixes the end timestamp; every
later retry returns that completed session unchanged.

See [DOM-04-TIMER-STOP.md](DOM-04-TIMER-STOP.md) for app/App Intent retry,
failure rollback, no-active behavior, and the focused-test command.

## Active-session startup reconciliation

The app bootstrap and every timer command use
`TimerCommandService.reconcileActiveState()` to reconstruct the active timer
from persisted timestamps. Zero and one active records are safe states. If
multiple active timed sessions exist, the newest start timestamp is canonical,
UUID order breaks exact timestamp ties, and every older record remains stored
and is returned as review-required. Mutating timer commands remain blocked
until the conflict is explicitly repaired.

See [DOM-05-ACTIVE-RECONCILIATION.md](DOM-05-ACTIVE-RECONCILIATION.md) for the
non-destructive recovery policy, persisted-fixture coverage, and focused-test
command.

## Session correction domain

Session editors must use `SessionCommandService`. Manual creation always
produces a completed `.manual` record; completed timer or manual records may be
reassigned and edited; active timed records expose only start/note correction.
Future/nonfinite timestamps and nonpositive intervals are rejected. Archived
projects remain valid for historical entry and reassignment.

Completed-session details may contain multiple assignments from the
user-managed tag catalog. Archiving a tag choice never removes historical
assignments.

Overlap warnings are nonblocking. `validateCompletedSession(...)` supports a
pre-save warning, while create/edit commands repeat detection and return the
definitive warning set. Those warnings use the same pure half-open interval
engine that future report and UI markers will consume.

See [DOM-06-SESSION-CORRECTIONS.md](DOM-06-SESSION-CORRECTIONS.md) for mutation,
confirmation, rollback, validation, and focused-test details.

## Session overlap detection

`SessionOverlapDetector` identifies every true overlapping pair plus every
affected session ID. Adjacent half-open intervals do not overlap, and active
intervals resolve to one injected reference time. Results never mutate source
sessions or change totals.

See [DOM-07-OVERLAP-DETECTION.md](DOM-07-OVERLAP-DETECTION.md) for the reusable
domain contract, edge-case policy, and focused-test command.

## Core app experience

`BillableHoursAppModel` projects persisted query state into onboarding, Track,
completion, project management, session history/editor, reports, and Settings.
All mutations continue through the explicit domain command services. Debug-only
UI fixtures seed deterministic product states without shipping test data in
Release builds.

See [CORE-EXPERIENCE.md](CORE-EXPERIENCE.md) for the UI-01 through UI-08
behavior, accessibility coverage, and lifecycle integration boundary.

## Exact reports

`ReportingEngine` intersects half-open source intervals with a selection and
splits only at boundaries returned by the injected `Calendar`. Day, Week, and
Project views aggregate those same source-linked segments and keep drill-downs
live after session changes.

Run the focused fixed-clock reporting suite:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/ReportingTests \
  -only-testing:BillableHoursTests/ReportingEngineTests \
  test
```

See [REPORTING.md](REPORTING.md) for RPT-01 through RPT-05 rules and evidence.

## Live Activity presentations

The extension contains Lock Screen and expanded/compact/minimal Dynamic Island
previews for privacy-hidden and explicit-name states. It adapts to Dark Mode,
Dynamic Type, and reduced luminance and uses a true Stop App Intent control.
The presentation is connected to persisted timer commands and foreground
reconciliation through the production lifecycle.

See [ACT-01-PRESENTATIONS.md](ACT-01-PRESENTATIONS.md) for the presentation
contract, preview matrix, and residual physical-device QA boundary.

See [LIVE-ACTIVITY-LIFECYCLE.md](LIVE-ACTIVITY-LIFECYCLE.md) for ACT-02 through
ACT-04 authority, intent handoff, reconciliation, and focused verification.
See [RELEASE-HARDENING.md](RELEASE-HARDENING.md) for recovery behavior and
[PRIVACY.md](PRIVACY.md) for the QA-05 audit and executable privacy check.
