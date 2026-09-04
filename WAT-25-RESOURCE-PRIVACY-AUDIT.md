# WAT-25 — Resource use and privacy audit

Status: In Progress. Source/unsigned-binary checks, the accelerated persistent
storage harness, sanitized physical storage/protection observations and a
host-side Watch Simulator CPU/memory regression baseline pass; physical energy,
network, restart-before-unlock and backup/restore gates are **not passed**. The
owner accepted the proposed physical resource/privacy budget on September 4,
2026; the required measurements against that budget remain open.

## Verified software evidence — September 3, 2026

`scripts/privacy-audit.sh` covers the phone, Watch, shared code and both widget
extensions. Existing checks reject app-owned network/analytics APIs, production
logging, interpolated crash messages, remote packages, unexpected entitlements,
tracking/data-collection declarations, missing manifests, embedded runtime
frameworks and prohibited linked/undefined symbols or endpoint literals.

This pass adds explicit source, linked-framework and undefined-symbol guards
for HealthKit, WorkoutKit and Watch extended runtime. Negative fixtures prove
that HealthKit/WorkoutKit imports and WKExtendedRuntimeSession construction fail
the source audit. Notification access remains confined to the existing local
goal adapter; this does not grant permission for APNs or remote notifications.

The strengthened audit and its negative tests passed. It also passed against
both completed combined Release products:

- `.derivedData/WAT23-Release/Build/Products/Release-iphonesimulator/WellSpent.app`
- `.derivedData/WAT23-Device-Release/Build/Products/Release-iphoneos/WellSpent.app`

Build logs: `/tmp/wat23-localization-final-release-sim.log` and
`/tmp/wat23-localization-final-release-device.log`. Release fixture isolation
passed for the phone, Watch, both extensions and copied resources. These are
unsigned compilation/static-inspection results, not a signed privacy report,
runtime network capture or proof of physical energy use.

## Storage and runtime findings from source

| Area | Implemented behavior | Still required |
| --- | --- | --- |
| Store | `WatchStorePersistence` requests backup exclusion on the store directory/children and complete-until-first-authentication file protection. Simulator tolerates unsupported protection attributes. The unlocked physical test host verified both attributes on the live directory, database and present sidecars. | Verify restart-before-first-unlock and execute backup/restore scenarios against the final signed candidate. |
| Goal preferences | Atomic writes request the same protection; the preference path is excluded from backup. The unlocked physical test host verified both attributes on the live directory and file. | Verify restart-before-first-unlock, lifecycle access and restore behavior against the final signed candidate. |
| Outbox | Only a named applied acknowledgement removes pending work; conflict/corrupt envelopes are quarantined, not silently discarded. Unit tests cover acknowledgement identity, restart and atomic erase. | Long-run retained-byte measurements, repeated reconnect/compaction cycles and physical recovery. Quarantine must not be discarded merely to meet a size budget. |
| Elapsed display | Timestamp-derived `TimelineView`, with requested one-second foreground and 60-second reduced-luminance cadence. | Measure actual scheduling, CPU and wakeups; a requested cadence is not a measured OS execution rate. |
| Widgets/controls | Runtime reload requests are gated by a changed `WatchWidgetState`; the provider requests a later timeline refresh and future goal boundaries. | Count actual reload requests and rendered updates during a physical long run. WidgetKit owns scheduling. |
| Notifications | User opt-in, local notification scheduling, finite reconciliation and cancellation; no workout/extended-runtime substitute. | Detached physical delivery, Focus/authorization behavior and energy impact. |

## Physical storage and protection observation — September 4, 2026

`scripts/watch-physical-storage-preflight.sh` now queries the physical Watch's
exact WellSpent App Group and app containers through CoreDevice, retains only
fixed file roles, logical sizes and backup-attribute booleans, and deletes the
raw device/account-identifying listings on exit. Its jq transformation and five
fail-closed fixtures cover missing stores, missing backup attributes, unexpected
App Group files and invalid sizes; the regression check is included in CI.

The first sanitized run at
`.derivedData/WAT25-PhysicalStorage1/summary.json` returned `observed` for the
aligned 0.1.0 (2) build on an Apple Watch Ultra 2 running watchOS 26.6:

- SQLite store: 102,400 logical bytes.
- SQLite SHM: 32,768 logical bytes.
- SQLite WAL: 1,421,432 logical bytes.
- Goal preferences: 101 logical bytes.
- Combined WellSpent-owned durable files: 1,556,701 logical bytes, below the
  subsequently owner-accepted 8 MiB offline high-water threshold.
- The database, both present sidecars and goal preferences all exposed Apple's
  backup-exclusion extended attribute. No unexpected regular file existed in
  the Watch App Group.

CoreDevice's file listing does not expose the data-protection class. A temporary
read-only Watch unit assertion therefore ran inside the physical app host and
verified `completeUntilFirstUserAuthentication` plus backup exclusion on the
live store directory, store, WAL, SHM, goal-preference directory and preference
file. The assertion passed and was removed immediately; its raw build and
result bundle were permanently deleted because they contained device/account
metadata. This is direct physical evidence for the unlocked/after-first-unlock
development build, not proof of restart-before-first-unlock behavior or of the
final signed candidate.

Two short Activity Monitor attempts could not attach to the physical Watch app
by name or PID. Their temporary traces/logs were deleted. No CPU, wakeup, memory
or energy result is inferred from those failed probes.

The four existing isolated resource workloads then ran successfully inside the
physical Watch test host: four passed, zero failures/skips, in 40.31 seconds.
Only the identifier-free JSON at
`.derivedData/WAT25-PhysicalResources1/summary.json` is retained; the Xcode
build, result bundle and attachment export were deleted. The physical samples
recorded:

| Scenario | Wall seconds between samples | Test-host CPU seconds | Peak logical bytes | Final logical bytes | Peak/final pending |
| --- | ---: | ---: | ---: | ---: | ---: |
| 48-hour projection loop | 1.512 | 1.597 | 345,320 | 345,320 | 1 / 1 |
| 128-command capacity/reopen | 2.071 | 1.997 | 3,402,000 | 249,856 | 128 / 128 |
| 64-item quarantine retention | 15.299 | 15.168 | 3,916,520 | 417,792 | 64 / 0 |
| 384 mutations / 12 acknowledgement cycles | 21.144 | 20.920 | 2,931,144 | 421,888 | 32 / 0 |

All four sampled peaks stay below the proposed 8 MiB high-water threshold while
preserving the semantic caps and byte-exact recovery assertions. These are
accelerated, debugger-attached test-host workloads, not foreground/background
production CPU rates or battery/wakeup measurements. CPU includes XCTest and
storage-instrumentation work and must not be compared with the proposed
per-minute production-app limits.

After the owner accepted the resource/privacy budget, a fresh read-only storage
observation at `.derivedData/WAT25-PhysicalStorage2/summary.json` returned
`observed` on September 4. The installed Watch product remains aligned at 0.1.0
(2); all present database components and goal preferences expose backup
exclusion, no unexpected App Group file was found, and combined logical size
remains 1,556,701 bytes. That is below the accepted 8 MiB high-water threshold.
The result retained no raw identifiers and did not inspect or mutate user data.
It is storage-metadata evidence, not candidate, backup/restore, energy, wakeup,
memory, network, or restart-before-unlock certification.

`WatchStoreTests.testPersistentStoreIsExcludedFromBackup` checks the resource
attribute in Simulator. It does **not** prove that a Watch backup, paired-phone
backup, restore or replacement device will recover or exclude the data. Do not
publish an unqualified Watch no-backup or reinstall-recovery claim from this
test. The actual semantics belong to WAT-24's authorized physical rows.

## Watch Simulator runtime baseline — September 4, 2026

`scripts/watch-simulator-runtime-probe.sh` installs a DEBUG Watch app only on an
explicit isolated Watch Simulator, launches one named fictitious fixture without
a debugger or profiler attachment, samples only that host process once per
second, and then terminates it. Reports retain elapsed seconds, CPU percentage
and resident KiB; simulator IDs, process IDs, paths and owner/host identifiers
remain temporary. The script requires a new evidence directory, rejects a
production-bundle ID mismatch and separates launch-inclusive samples from a
steady-state window beginning at second 10. CI now syntax-checks every shell
script so this opt-in local tool cannot silently become syntactically stale.

Three 30-second observations on the isolated 40mm watchOS 26.5 Simulator are
retained under `.derivedData/WAT25-SimulatorRuntime1/`:

| Fictitious fixture | Steady samples | Average host CPU | Maximum host CPU | Resident KiB range |
| --- | ---: | ---: | ---: | ---: |
| Active 1 Hz elapsed display | 21 | 1.233% | 3.300% | 187,984–188,064 |
| Paused timer | 21 | 0.467% | 1.500% | 187,776–187,840 |
| Setup/idle | 21 | 0.005% | 0.100% | 183,936–184,032 |

Every report has 31 consecutive samples, `rawIdentifiersRetained: false`,
`resourceBudgetPassed: false` and `releaseApproved: false`. The launch-inclusive
CPU maxima (33.3%, 29.7% and 6.9%) are retained separately instead of being
mixed into the steady window. Host Simulator RSS includes simulator/debug
runtime overhead and must not be compared with the proposed 50 MiB physical
Watch limit; these values are useful only for like-for-like future regressions.

The subsequent isolated full clean-checkout pipeline passed all 13 stages and
381 tests from synthetic snapshot
`1e929e74935550b891cf99dbe2348e99e03b8c49`; evidence is retained under
`WellSpentCleanCheckout.5Aqsso/DerivedData/run.HOdM21`. Its source-gate stage
includes the all-script syntax check and the existing resource/privacy
regressions. This verifies integration of the sampler and guards, not a physical
resource budget.

Two preceding Watch-targeted `xctrace` Time Profiler pilots—one direct launch
and one attachment—expired but never finalized. Each produced only an empty
52 KiB `RunIssues.storedata`, with no issues or samples, and left `xctrace`
running until the exact processes were terminated. Those raw traces were
deleted. No CPU, memory, wakeup or energy result is inferred from them. The
physical Watch also appeared offline to Instruments at this checkpoint, so the
required physical measurements remain open.

## Accelerated persistent-storage harness — verified September 3, 2026

`WellSpentWatchTests/WatchResourceTests.swift` uses UUID-named temporary stores,
the production SwiftData persistence/writer/reader, and fictitious projects.
It never opens the live App Group or sends Watch Connectivity traffic. Temporary
fixture stores are removed after each test; measurements remain in the results.

Four exact scenarios are required by `scripts/watch-resource-tests.txt` and the
main CI critical-test manifest:

- Fill the 128-command offline outbox with real Start/Pause/Resume/End commands.
  The next command fails explicitly without changing state, causal ordering,
  payload bytes, or sequence. Recreating the container preserves all 128.
- Run 96 sessions in quarter-hour slots: 384 mutations across 12 offline/ack
  cycles, with a captured-time span of 23 hours 48 minutes. Recreate containers
  between phases, retry delivery without rewriting bytes, deliver each ack
  twice, and verify the exact latest 256 retained acknowledgement IDs. Only
  named commands disappear. Every run counts 120 seconds, excluding its pause.
- Fill the 64-entry quarantine; the next conflicting acknowledgement fails
  without dropping its pending envelope. Compact remaining applied commands,
  prune acknowledgement history using late duplicates, then reopen and verify
  every quarantined envelope and associated conflict receipt byte-for-byte.
  The review block remains present.
- Read elapsed projections at 577 instants across 48 simulated hours. Values
  remain timestamp-derived; no save is attempted, pending state is unchanged,
  and database/sidecar bytes remain identical. This is not a 48-hour wall-clock
  run or proof of actual WidgetKit scheduling.

Run independently on an idle Watch Simulator:

```sh
bash scripts/watch-resource-check.sh
```

The script defaults to the 40mm SE 3/watchOS 26.5 simulator. Override
`WATCH_RESOURCE_DESTINATION` with an explicit `platform=watchOS Simulator,...`
destination if needed. Never share a simulator with an active job. Each run
creates a new directory under `.derivedData/WatchResources/`, uses normal
Simulator signing, verifies exact test IDs and rejects failures/skips. Retained
JSON attachments feed `report/summary.json`. To report an existing bundle, run
`scripts/watch-resource-report.sh BUNDLE NEW_REPORT_DIRECTORY`; existing reports
are not overwritten.

Samples record pending/quarantine/receipt/acknowledgement counts, payload bytes,
recursive logical/allocated file bytes including WAL/SHM, monotonic time and
cumulative test-host CPU/context-switch counters. Reports calculate deltas
between samples. CPU includes test/instrumentation work and can exceed wall time
across cores; context switches are **not wakeups**. Unknown allocated-byte values
stay unknown, never zero. Sampled maxima are not continuous peak measurements
or accepted resource budgets. Report arithmetic, unknown-value handling and ten
rejection fixtures pass in `scripts/watch-resource-regression-tests.sh`, now in CI.

Verified on the 40mm SE 3, watchOS Simulator 26.5, Xcode 26.6:

- Standalone workflow `.derivedData/WatchResources/run.GGadlh/`: four passed and
  report generated; log `/tmp/wat25-resource-harness.log`.
- Final `.derivedData/WAT25-FullUnitsAndHelp.xcresult`: **123 passed** (122 Watch
  units, one corrected guide UI test), no failures/skips/expected failures.
  Log `/tmp/wat25-full-units-help.log`; report
  `.derivedData/WAT25-FullUnitsAndHelp-Report/summary.json`.
- Final strengthened retention assertion compares both envelope and conflict
  acknowledgement bytes. All four resource cases passed again in
  `.derivedData/WAT25-QuarantineBytesFinal.xcresult`, log
  `/tmp/wat25-quarantine-bytes-final.log`, with report in
  `.derivedData/WAT25-QuarantineBytesFinal-Report/summary.json`.
- The final widget-source clean-checkout run passed 379 tests and all 13 stages;
  see the final WAT-23 checkpoint. It includes all 123 current Watch unit cases,
  including the strengthened acknowledgement-byte assertion and resource suite.
  The earlier 358-test checkpoint is retained as historical evidence only.
- Earlier `WAT25-ResourceStress1.xcresult` is a retained fixture compile failure,
  not a pass. Corrected `WAT25-ResourceStress2.xcresult` passed all four; later
  runs add baseline sampling and recursive file enumeration.

Representative final full-suite observations, **not pass/fail budgets**:

| Scenario | CPU seconds between samples | Largest sampled logical bytes | Final logical bytes | Final pending / quarantine / acknowledgements |
| --- | ---: | ---: | ---: | --- |
| 48-hour elapsed projection | 0.256 | 345,320 | 345,320 | 1 / 0 / 0 |
| Offline capacity and reopen | 0.416 | 3,402,000 | 249,856 | 128 / 0 / 0 |
| Quarantine retention | 2.912 | 3,916,520 | 417,792 | 0 / 64 / 256 |
| Twelve offline/ack cycles | 4.307 | 2,931,144 | 421,888 | 0 / 0 / 256 |

SQLite file shrinkage after reopen/checkpoint is separate from semantic
compaction: the capacity case still retains all 128 commands. These results
do not authorize user-data eviction to hit a byte target or certify physical
energy, memory, network silence, protection, or backup behavior.

## Accepted physical resource budget

The issue previously required an “accepted budget” without naming a decision.
The owner accepted the complete engineering proposal below on September 4,
2026, as recorded in `WAT-OWNER-DECISIONS.md`. These gates apply to the exact
signed candidate. The approval establishes the thresholds; it does not classify
an unmeasured physical run as Pass or Fail.

| Area | Proposed release gate |
| --- | --- |
| Correctness | Zero lost/duplicated counted intervals, false-success actions, premature outbox compactions, privacy leaks, jetsam terminations or unrecoverable stores. A single occurrence fails the candidate regardless of averages. |
| Battery | Across three debugger-detached LONG-01 and LONG-03 repetitions, median incremental drain is no more than 2 percentage points/hour above a matched idle/paused baseline and no repetition exceeds 4 incremental points/hour. Record total drain and screen/Always On/radio conditions separately. |
| CPU and wakeups | During foreground 1 Hz timer display, median app CPU is at most 1.5 CPU-seconds per wall-clock minute and app-attributed wakeups are at most 75/minute. With the wrist down/app backgrounded and no mutation, median CPU is at most 0.15 seconds/minute and app-attributed wakeups are at most 6/minute. Exclude Instruments/debugger overhead only through a separately repeated detached run. |
| Memory | Watch app peak resident memory stays below 50 MiB and Watch widget below 25 MiB, with no memory-pressure termination. Record OS/tool sampling limitations instead of substituting zero. |
| Durable storage | The combined Watch store, WAL/SHM and preferences remain below 8 MiB at the documented outbox/quarantine high-water mark and below 2 MiB after acknowledgement/checkpoint steady state. The hard semantic caps remain 128 pending commands, 64 quarantined envelopes and 256 retained acknowledgement IDs. No retained item may be discarded only to meet bytes. |
| Widget work | An uninterrupted active timer with no state mutation causes zero app-requested reloads per minute; each actual serialized widget-state change causes at most one explicit request per widget kind. System timeline renders and budget decisions are recorded separately and must keep state acceptably fresh without claiming a guaranteed interval. |
| Network | Zero app-attributed public Internet endpoints, HTTP requests, analytics/advertising traffic, APNs registration or content-bearing diagnostics. Apple's local Watch Connectivity/system traffic is expected and must be distinguished from an app-owned network client. |
| Protection/retention | Store, sidecars and preferences exhibit the configured file protection and backup exclusion on device. Restart-before-unlock, backup/restore, reinstall and replacement observations match the final support copy; no recovery behavior is inferred from Simulator attributes. |

These thresholds intentionally leave roughly 2× headroom above the largest
accelerated logical-store sample (3.92 MiB) and more than 4× above the observed
post-compaction steady state (0.42 MiB). Battery/CPU/wakeup/memory values are
provisional until the first controlled physical baseline; if instrumentation
shows a platform floor above a threshold, revise and approve the budget before
the candidate verdict rather than moving the line after seeing a failure.

Apple notes that WidgetKit owns a dynamic daily refresh budget and recommends
requesting a reload only when displayed data changes; debugging can bypass that
budget. Therefore this proposal gates WellSpent's explicit reload requests and
observed freshness separately from system-granted extension execution:
[Keeping a widget up to date](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date),
[TimelineProvider](https://developer.apple.com/documentation/widgetkit/timelineprovider),
and [Analyzing your app’s battery use](https://developer.apple.com/documentation/xcode/analyzing-your-app-s-battery-use).

## Physical runtime measurement protocol — prepared, not executed

The isolated physical storage workloads above are complete, but the following
debugger-detached runtime protocol has not been executed. Use the exact
candidate and fictitious data set recorded by WAT-24. Compare
like-for-like idle, running, paused, offline-queue and reconnect scenarios with
the same hardware, OS, display settings and radio conditions. Repeat detached
runs; separately capture Instruments diagnostics so debugger overhead is not
silently included in the battery result.

Record CPU time per wall-clock minute, wakeups per minute, battery percentage
change per hour, widget/control reload requests, outbox/quarantine counts,
logical store bytes and allocated bytes including WAL/SHM/preferences. Record
both the offline high-water mark and the post-acknowledgement steady state.
Distinguish durable counted-time records from reclaimable acknowledgements.

Run WAT-24 LONG-01…03 for multi-hour observations and classify them against the
accepted budget above. Preserve anomalous runs and explain measurement noise
instead of averaging away data-loss or runaway-growth cases. If the first
controlled baseline proves a platform measurement floor infeasible, obtain a
revised approval before the candidate verdict rather than moving the line after
observing the result.

For network evidence, attribute connections to the candidate/app process and
compare with system baseline traffic. Watch Connectivity transport is expected;
absence of app networking symbols is not proof of complete runtime silence.
Keep payloads, personal notifications, account identifiers and unrelated-device
traffic out of retained artifacts. User-opened support/privacy websites are
separate deliberate navigation, not automatic analytics.

## Closure gates

Remaining: actual runtime reload/wakeup and memory observations, physical
measurements within an accepted budget, paired runtime network capture,
restart-before-first-unlock and backup/restore evidence, signed-candidate
framework/entitlement/privacy-report inspection, and reconciliation of final
App Store/support claims. WAT-24 remains a dependency. No certification or
release sign-off is implied by this physical metadata checkpoint.
