# WAT-24 — Paired-device resilience matrix

Status: execution plan prepared and the production paired-install prerequisite
passes. **No resilience row below is a physical pass.** Simulator and
injected-transport evidence supplements this matrix; it cannot replace it. The
historical, user-accepted WC Probe result is not product release evidence.

## Candidate and evidence rules

Use WellSpent, not WC Probe. Install the combined candidate through the paired
Xcode destination described in WATCH-TESTING-GUIDE.md. Confirm matching phone,
Watch and extension versions and counterpart registration before transport
testing. An installation/registration failure stops the scenario; it is not an
offline-transport result. Do not independently install the two app bundles.

Use only fictitious projects and annotations in a dedicated test data set.
Never erase, uninstall, unpair or replace a personal-device store unattended.
Those rows require explicit authorization, an inventory of unsynchronized time,
and a verified recovery plan. A device backup is not presumed to contain the
Watch app's outbox. Disable personal notification previews before recording.

For each execution record: case ID, repeat number, candidate version/build and
source checkpoint, hardware class, both OS versions, installation method,
debugger attached/detached, radio conditions, initial state, actions, observed
states, observation duration, outcome and artifact paths. Use device aliases,
not serial numbers/account identifiers. Artifacts must not contain real project
names, notes, personal notifications, raw payloads or account data.

Outcomes are **not run**, **passed**, **failed**, or **inconclusive**. Delayed
opportunistic delivery is not itself corruption. An observation timeout remains
inconclusive; record elapsed wait and the next safe foreground/reconnect step.
Never convert a timeout into a pass. Repeat opportunistic/duplicate scenarios
three times and preserve each result, including failed attempts.

## Invariants checked in every scenario

1. A successful visible action follows a durable local save. Failed actions do
   not change the prior run or report success.
2. Counted time is the sum of the original segment intervals. Paused intervals
   never count; resuming creates one segment. Switching ends/starts at one exact
   boundary. Ending preserves a saved summary before optional annotations.
3. Retries preserve mutation identity. Duplicate messages/acknowledgements never
   duplicate time; only the named applied acknowledgement permits compaction.
4. Same-base divergence is preserved for review, never silently ordered by wall
   clock or overwritten. Both original branches remain inspectable.
5. Reconnection converges when safe. Outstanding work stays visibly pending
   until acknowledged, and cached totals are not presented as newly current.
6. Lock/redaction hides project identities and annotation contents. Error and
   offline states remain understandable without color or haptics.

## Frozen execution cases

| IDs | Procedure | Required observations |
| --- | --- | --- |
| LIFE-01…09 | For each phone/Watch foreground, background and terminated combination, commit a Watch action offline while foregrounded; move both apps to the recorded lifecycle states, then restore connectivity. Repeat with phone-origin changes. Record actual lifecycle transitions rather than assuming suspension. | Local commit survives; background delivery is correctly characterized; later foreground synchronization converges exactly once. |
| RADIO-01 | Start, Pause, Resume, Switch and End with the phone unavailable. Reconnect after the saved summary. | Exact segment boundaries and one ended run; pending indication clears only after acknowledgement. |
| RADIO-02 | Lose reachability after send but before acknowledgement; reconnect and allow retry. | No duplicate run/segment; no premature outbox compaction. |
| RADIO-03 | Repeat connectivity loss/restoration while acknowledgements and snapshots cross in flight. | Out-of-order/duplicate receipt does not roll back newer state or erase pending edits. |
| RADIO-04 | Leave the phone app terminated, perform Watch mutations, then launch phone and Watch in opposite orders on separate repetitions. | Either documented deferred delivery or safe eventual convergence; no install troubleshooting counted as transport evidence. |
| BOOT-01…04 | Reboot Watch while running; reboot Watch while paused; reboot phone while running; reboot both while paused. Resume/end afterward. | Timestamp-derived active elapsed survives; paused billable time stays frozen; no phantom open segment. |
| SAVE-01 | End offline, reopen summary, edit note/tags, interrupt/relaunch before and after local annotation commit. | Ended time remains saved; unsaved draft is not falsely reported as persisted; committed annotation/outbox survives. |
| CONFLICT-01 | Disconnect after a common head. Change the same run on both devices, reconnect. | Both causal branches preserved; review blocks unsafe continuation. |
| CONFLICT-02…04 | Repeat the conflict and execute every currently offered iPhone resolution path, one fresh conflict per path. Inventory exact UI choices before execution. | Displayed resolution matches saved intervals and audit disposition; phone/Watch converge without duplicates. Cancellation preserves both branches. |
| INSTALL-01 | Authorized Watch-app reinstall with previously acknowledged time. | Actual retained/lost local state is documented; phone history stays correct; fresh origin/setup behavior matches implementation. |
| INSTALL-02 | Authorized Watch-app reinstall with deliberately unacknowledged fictitious time. | Capture actual loss/recovery limits. Never promise that reinstall recovers a device-local outbox. |
| INSTALL-03 | Authorized phone-app reinstall, once with a pending Watch change and once after acknowledgement. | No accidental merge into a different ledger; setup/review and retained history reflect actual persistence boundaries. |
| PAIR-01 | Authorized unpair/re-pair using a dedicated test pair and an explicitly selected backup/restore path. | Record backup choice and actual recovered state; no claims inferred from ordinary process-restart tests. |
| PAIR-02 | Dedicated replacement Watch, with and without restoration where hardware is available. | Device identity, pending work, privacy preferences and handoff behavior match the documented retention limits. |
| UPGRADE-01 | Upgrade an actual oldest supported populated store using a retained old build, without reset. Include active, paused, ended, tagged and review-required records where supported. | Migration preserves counted intervals and pending/review state; rollback/error behavior is explicit. Missing old build is an unexecuted prerequisite, not a pass. |
| LONG-01 | At least a three-hour active run, including background, wrist-down/lock and reconnection. Compare start/end instants and counted segments. | Elapsed accuracy, one optional goal alert, privacy, widget freshness, bounded storage and battery observations. |
| LONG-02 | Multi-hour paused run, then resume/end. | Paused billable elapsed remains unchanged; the goal deadline is rescheduled from counted time rather than wall time. |
| LONG-03 | Repeated short runs and offline mutations over a multi-hour session; reconnect and acknowledge. | Pending data is retained until safe compaction; storage growth/recovery and widget reload behavior feed WAT-25. |

The lifecycle IDs enumerate the Cartesian order FF, FB, FT, BF, BB, BT, TF, TB,
TT (phone first). A terminated producer is terminated **after** its command was
committed; it is not described as receiving an in-app tap while terminated.
Do debugger-attached transport diagnostics first, then repeat background,
termination and long-duration cases with the debugger detached. Exercise a
minimum-class watchOS 26 device and a current device when available; unsupported
hardware availability stays recorded as a missing gate.

## Physical evidence gate

The frozen manifest `scripts/watch-physical-required-cases.tsv` expands the
31 case IDs into **55 minimum accepted result records**: all nine lifecycle
orders and RADIO-02…04 require three repetitions; the remaining cases require
one. LONG-01 requires at least 10,800 observed seconds and LONG-02/03 at least
7,200 seconds. Install/unpair/replacement/upgrade rows require an explicit
authorization reference; upgrade also requires the actual oldest-build source.

After executing one fixed candidate, validate the candidate and result directory:

```sh
bash scripts/watch-physical-matrix-check.sh \
  candidate.json results/ .derivedData/NEW-WAT24-MATRIX-REPORT
```

The checker requires a clean fixed source/digest, exact version/build and install
channel, physical debugger-detached observations, registered/aligned companion
versions, all six invariants, privacy review and nonempty sanitized artifacts.
Every retained result must be Passed. A failed, inconclusive, not-run, missing,
duplicate, too-short, unknown, mismatched-candidate or identifier-bearing result
keeps the matrix open; extra repetitions cannot hide an earlier failure.

`scripts/watch-physical-matrix-regression-tests.sh` creates a complete synthetic
55-record matrix and then proves rejection of failed outcomes, debugger-attached
substitutes, identifier leakage, missing destructive authorization, candidate
mismatch, short long-run evidence, missing artifacts, duplicate results and a
missing required repetition. It passes locally and is a clean-CI source gate.
The synthetic positive fixture tests the validator only and is never WAT-24
physical evidence.

## Autonomous prerequisites and execution boundary

- Existing WAT-22 suites cover deterministic transport duplicates/reordering,
  causal conflicts, persistence, migrations and real process-restart fixtures.
  Preserve those result bundles; rerun clean CI against the final candidate.
- WAT-23's autonomous app/editor/widget/error-state audit and clean CI are
  complete. Its physical accessibility and actual WidgetKit checks still must
  pass before claiming the dependency closed.
- Inspect current conflict-resolution UI and migration fixtures before executing
  the physical rows; do not invent a resolution option or an oldest-build store.
- WAT-25 consumes the long-run storage/battery observations. WAT-26 records the
  exact signed candidate. WAT-27 support copy must reflect measured retention,
  not assume all reinstall/unpair paths recover time.

Resilience execution is intentionally pending. No personal store was erased,
uninstalled or inspected while preparing this matrix, and no physical result
has been promoted from Simulator evidence.

### Read-only physical preflight — September 3, 2026

`scripts/watch-product-device-preflight.sh` now queries only the exact production
bundle IDs and device readiness, uses raw CoreDevice identifiers only in a
temporary directory, and retains a sanitized JSON result. It changes no device
or app state and fails closed when any prerequisite is missing. Run it as:

```sh
bash scripts/watch-product-device-preflight.sh \
  <iphone-xcode-id> <watch-xcode-id> .derivedData/NEW-PREFLIGHT-DIRECTORY
```

The finalized checker produced
`.derivedData/WAT24-DevicePreflight3/summary.json`. Its non-mutating inventory
found one usable current pair:

- iPhone 17 Pro Max on iOS 26.6.1, Developer Mode enabled, connected by a wired
  route; production WellSpent 0.1.0 (2) is installed.
- Apple Watch Ultra 2 on watchOS 26.6, Developer Mode enabled, available through
  its paired route; Xcode lists it as a valid `WellSpentWatch` destination.
- The exact production Watch bundle `com.drewreilly.wellspent.watchkitapp` is
  **not installed** on the Watch.

No app was installed, launched, terminated or updated, and no container or user
data was read. The checker returned nonzero with only
`watch_bundle_not_installed`; its retained-file leak scan found no names, serials,
device IDs, hostnames or tunnel addresses. This fails the installation
prerequisite only; it is not a failed Watch Connectivity, lifecycle or
product-flow row. The next physical action is a unified Xcode companion install
after confirming that updating/launching the existing phone app is safe for its
current local data.

The report transformation lives in
`scripts/watch-product-device-preflight-summary.jq`. Synthetic regression cases
prove a ready pair, missing Watch bundle, version mismatch, non-wired phone and
missing Xcode destination are classified distinctly, while raw identifiers,
owner names, serials, install paths and tunnel data never reach the summary.
`scripts/watch-product-device-preflight-regression-tests.sh` passes and is now a
clean-CI source gate.

### Authorized paired installation — September 3, 2026

The owner explicitly authorized an in-place unified Xcode install/launch that
could update or migrate the existing phone app's local store. Xcode ran the
production `WellSpentWatch` scheme against the paired physical Watch
destination; no independent bundle install, uninstall, erase, unpair, radio
change or replacement operation was used. An initially still-selected WC Probe
scheme was stopped immediately and was not used as product evidence.

The post-install run reached `Running WellSpentWatch` in Xcode. The fresh,
privacy-sanitized report
`.derivedData/WAT24-DevicePreflight4/summary.json` then passed every
installation prerequisite:

- iPhone 17 Pro Max on iOS 26.6.1 was booted, paired, in Developer Mode and
  connected by the wired route.
- Apple Watch Ultra 2 on watchOS 26.6 was booted, paired, in Developer Mode,
  reachable over its paired route and available as an Xcode run destination.
- Exact production phone and Watch bundles were both installed as version
  0.1.0 build 2, aligned with the configured candidate.
- The report returned `ready`, retained no raw identifiers and reported no
  reason codes.

This closes only the paired installation/registration prerequisite. It does
not pass a lifecycle, offline, restart, reinstall, upgrade, conflict, long-run,
accessibility, energy or release row. Proceed only with fictitious test data;
destructive rows still require their own explicit authorization and recovery
plan.

After the isolated physical UI smoke, a second fresh sanitized preflight at
`.derivedData/WAT24-DevicePreflight5/summary.json` also returned `ready` with
the same aligned candidate and no reason codes. The UI run therefore did not
disturb the production bundle-registration prerequisite.

### Authorized live foreground diagnostic — September 3, 2026

The owner authorized the existing WellSpent phone and Watch data to be treated
as disposable test data. A temporary UI-test harness launched both production
apps without `UITEST_` fixture arguments, so their real persistent stores and
live `WCSession` implementations remained active. The harness source was removed
after the diagnostic and is not part of the product test suite.

The first iPhone erase exposed a real product defect: the empty legacy
Live Activity spike namespace still required `UserDefaults.synchronize()` to
return true. That call returned false on physical iOS, aborting the reset before
SwiftData erasure. `WellSpentSpikeStorage.clearSpikeData` now treats an already
empty namespace as successfully erased while retaining the existing persistence
check whenever legacy keys actually need removal. Two focused regression tests
plus the existing end-to-end model reset test pass in
`.derivedData/WAT24-ResetRegressionFinal/`; the corrected build completed the
physical erase, returned to onboarding, and created the fictitious `WAT Alpha`
and `WAT Beta` projects.

Live transport then completed one end-to-end foreground diagnostic. The Watch
received the new `WAT Alpha` project and started it; the foreground iPhone
displayed the same active timer with Watch-origin attribution. A later physical
Watch run navigated to Controls, paused, resumed and ended that same timer, then
reached the saved end summary. Finally, the physical iPhone showed no active
timer and Session History contained `WAT Alpha` with Apple Watch attribution.
This proves that this production pair exchanged the initial project snapshot,
Watch Start/Pause/Resume/End mutations, and converged phone history in the
foreground. The test did not assert final acknowledgement receipt on the Watch.

This diagnostic does **not** pass a frozen matrix row: both apps were launched
under XCTest/debugger control, lifecycle and radio conditions were not frozen,
and the run did not exercise a recorded offline or recovery case. The first
Watch control attempt also established that a single synthesized hardware swipe
is not a reliable physical-test navigation primitive; the successful cleanup
used a bounded retry and explicit edge drag before asserting the Controls page.
The fictitious run is now ended and visible in phone history.

The failed/partial and successful physical Xcode result bundles, build
directories, exported UI trees, screen recordings and automatically generated
`devicectl` diagnostic ZIPs were permanently deleted because they contained
device/account-identifying metadata. Only the sanitized findings above and
preflight summaries are retained. Zero of the required 55 physical matrix
records was promoted to Passed from this diagnostic.

A final read-only preflight at
`.derivedData/WAT24-DevicePreflight6/summary.json` returned `ready` after one
transient device-query timeout. It confirms that both production bundle IDs
remain installed at candidate 0.1.0 (2), the versions are aligned, and the
Watch remains available as an Xcode destination after the diagnostic.

After the later isolated WAT-25 physical resource run, preflight 7 retained a
sanitized `blocked` result at
`.derivedData/WAT24-DevicePreflight7/summary.json`. Both production apps remain
installed and version-aligned at 0.1.0 (2), and Xcode still lists the Watch
destination, but CoreDevice reported the Watch as not booted with no active
tunnel. The check changed no state. This is the current runtime prerequisite:
bring the Watch back online, nearby and unlocked before another paired row.

A later read-only recheck at
`.derivedData/WAT24-DevicePreflight8/summary.json` returned `ready`. The iPhone
is available over its wired route, the paired Apple Watch Ultra 2 is booted and
tunnel-connected, Xcode lists the Watch destination, and both production bundle
IDs remain installed and version-aligned at 0.1.0 (2). The retained summary has
no raw identifiers and the check changed no device state. This restores the
execution prerequisite only; it does not promote any of the 55 required matrix
records or prove transport, accessibility, energy or release behavior.

A fresh read-only continuation check at
`.derivedData/WAT24-DevicePreflight9/summary.json` returned `ready` on September
3 local time (September 4 UTC). It independently reconfirmed the same wired
iPhone, tunnel-connected paired Watch, valid Xcode destination, exact production
bundle installations and aligned 0.1.0 (2) versions. It retained no raw
identifiers and changed no device state. This is current prerequisite evidence,
not a promoted matrix result.

After the owner approved the nondestructive physical session, a new read-only
continuation check at `.derivedData/WAT24-DevicePreflight10/summary.json`
returned `ready` on September 4. It again found the wired iPhone and paired
tunnel-connected Watch booted, in Developer Mode and available as an Xcode
destination, with both exact production bundle IDs installed and aligned at
0.1.0 (2). The report retains no raw identifiers and changed no device or app
state. It refreshes the execution prerequisite only; zero frozen matrix records
are promoted by this inventory.

### Nondestructive build-3 iPhone update — September 4

The verified archive's embedded iPhone app was installed over the existing
0.1.0 (2) app without uninstalling it or resetting its store. A read-only
post-install query confirmed `com.drewreilly.wellspent` at 0.1.0 (3). The
identifier-free partial record is retained at
`.derivedData/WAT24-Build3Install1/summary.json` and binds the install to source
commit `8ead2308259fa030abdd0d81ef3ba9ab0199c7b9` and archive product manifest
`41871fef8b96022660696c0f8a51f9045a48d9c21b5565ef3df1d2e20eb51322`.

This is not a paired-install or smoke-test pass. At the verification point the
Watch remained paired but its developer tunnel was disconnected, so its version
could not be checked. A later attempt to open the updated iPhone app was denied
by the operating system because the iPhone had locked. Restore the unlocked
iPhone/Watch prerequisites, verify the embedded Watch companion at 0.1.0 (3),
and execute candidate-bound actions before promoting any row.

## Additional autonomous recovery evidence — September 3

WAT-25's `WatchResourceTests` exercises the actual persistent store across
container recreation at offline capacity and between 12 offline/acknowledgement
cycles. It verifies byte-exact outbox/quarantine retention, causal sequences,
duplicate acknowledgement handling, bounded acknowledgement history and counted
intervals. Four stress cases and the full Watch suite passed in
`.derivedData/WAT25-FullUnitsAndHelp.xcresult` (122 units plus one UI case).
See WAT-25-RESOURCE-PRIVACY-AUDIT.md for reproducible commands and measurements.

This supplements the existing real process-termination fixtures. It does not
simulate OS reboot, true radio/Watch Connectivity delivery, app reinstall,
backup/restore or a replaced device. None of the physical matrix rows above is
marked passed by this additional software evidence.
