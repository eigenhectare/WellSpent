# WAT-19 — App Intents and Watch controls

Autonomous implementation on September 2, 2026. Keep In Review until the actual
system-discovery, Siri permission, Action button and paired-device gates pass.

## Implementation

- Five discoverable actions: Start Project, Pause, Resume, Switch Project, End.
  Five app-only shortcuts supply phrases such as “Pause my timer in WellSpent.”
- Bounded stable-UUID project query reads the protected store without a writer.
  Project names follow explicit iPhone privacy opt-in; otherwise system choices
  are generic numbered projects. Archived, unsupported and conflict catalogs
  cannot silently provide usable mutation targets.
- The watchOS 26 Control Widget can select a favorite project, or use the most
  recent available project. It becomes Pause or Resume while a run exists, and
  opens recovery UI for setup, missing store, archived favorite, update or review
  states. Control labels/dialogs contain no project identity.
- Every mutating intent explicitly requires foreground execution and local
  device authentication. The app registers the executor, and the widget process
  has no store writer. A missing executor fails safely instead of creating a
  second persistence path. No workout or unrelated background-runtime API is
  used to run actions invisibly.
- `WatchSystemCommandBoundary` delegates to the existing Start/control boundary
  and `performLocalCommand` atomic persist/outbox transaction. Successful actions
  refresh the app, retry durable delivery and reload control/widget projections.
- Controls carry a content-free precondition derived from Watch store identity,
  next local sequence and active/recent run UUID/revision. Old controls cannot
  end a newer run or replay an old Start after End. Unrelated catalog/privacy
  snapshots do not invalidate a still-current Pause control.
- Repeated Siri actions already in the requested state do not append mutations;
  Start never silently switches another active project. A fresh Siri command
  acts on the current run, while a rendered control acts on its observed state.
- Successful app actions donate only generic project identity to the system.
  Donation failures do not affect saved time. The app-only shortcut provider
  prevents duplicate extension registration.
- The picker includes a reachable “Siri & Controls” guide. Users configure
  Control Center and supported Ultra Action button placement in system UI.

## Verification

- Watch suite: 66 XCTest + 25 Swift Testing cases passed after foreground metadata
  correction, including eight system-action boundary/actual-perform regressions.
- Five focused UI cases passed together: four widget/privacy/navigation cases
  and the setup guide. The guide screenshot was visually inspected.
- Generated app AND extension metadata were inspected: all six executable
  intents have explicit authentication policy 2, supportedModes 2 and
  openAppWhenRun true (watchOS 26 toolchain representation). The app has five
  shortcuts; the extension has zero shortcut-provider entries.
- Final combined Release Simulator and unsigned Watch Release device builds
  passed, including app-only shortcut registration and explicit policies.
- Source/binary privacy audit and strict formatting passed. The intents source
  directory is included in both audits.

Final verification artifacts:

- `/tmp/wat19-verified-tests.log` — final full Watch + focused UI run.
- `/tmp/wat19-verified-release.log` — final combined Release Simulator build.
- `/tmp/wat19-verified-device.log` — final unsigned Watch Release device build.
- `.derivedData/WAT19-Visuals` — setup guide capture.
- `scripts/watch-intents-check.sh` — structural checks; with
  `WATCH_INTENTS_APP_BUNDLE` it validates the compiled metadata. CI runs both.

An important caught regression: inherited protocol-extension execution and auth
settings worked in direct Swift calls but initially extracted as background/no
authentication in App Intent metadata. Concrete declarations on every intent
fixed this; the metadata gate prevents silent recurrence. Simulator's linkd
helper may log unavailable shortcut-parameter discovery; direct test execution
and generated metadata are not claimed as physical Siri discovery evidence.

## Remaining gates

Verify actual Control Center/Smart Stack registration and execution with the app
foreground/background/terminated; physical Siri allow/deny and locked device
behavior; user-assigned Action button on supported Ultra hardware; offline
actions converging over real WC; simultaneous real app/widget/Live Activity
commands. These are tracked with WAT-24, and remain unpassed here until run.

Reference: [Apple intent execution modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes),
[Apple controls](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system),
and installed watchOS 26.5 AppIntents/WidgetKit interfaces. Foreground execution
is intentional: it gives one authenticated app-owned writer, not a claim of
background timer runtime.
