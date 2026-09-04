# WellSpent Apple Watch Testing Guide

Last updated: September 2, 2026

## 1. The short answers

### What is the proper way to install a development build?

Use Xcode's **Run** action with automatic signing. For a dependent companion
app, select the Watch app scheme and a run destination that names both the
Apple Watch and its paired iPhone. Xcode is the source of truth for building,
signing, installing, and launching the pair.

Do not use `devicectl device install app` to install the iPhone and Watch
bundles independently, and do not mix a `devicectl` installation on one device
with an Xcode installation on the other. That can put two runnable apps on the
devices without registering them as counterparts. The resulting
`WCErrorDomain` code 7006 (`watchAppNotInstalled`) is an installation failure,
not a Watch Connectivity transport result.

`devicectl` remains useful after a valid Xcode installation for inspecting
devices, launching an already installed app, and collecting diagnostics.
Likewise, use `simctl` for Simulator pairing, booting, inspection, and launching
an Xcode-installed app—not for independently installing the two companion
bundles. The focused UI-test schemes provide the automated Simulator install.

### Where does WC Probe fit?

WC Probe is a disposable transport harness for WAT-04. It answers whether the
frozen command, acknowledgement, snapshot, persistence, deduplication, and
background-delivery design behaves correctly. It uses synthetic IDs and a
separate store so it cannot modify real WellSpent data.

It is not the product Watch app, and passing it does not validate product UI.
It must still be packaged as a production-shaped iOS companion plus embedded,
dependent watchOS app; otherwise it tests an installation arrangement we will
never ship.

### What can Simulator prove?

Simulator is the default for build, pure protocol, reducer, persistence, and UI
state tests. It is not an acceptance environment for Watch Connectivity's
durable lane. Apple explicitly states that Simulator does not support
`transferUserInfo` and recommends testing Watch Connectivity transfers on
paired devices.

This gives us a strict rule: a Simulator result may pass a local or UI gate,
but it may never be entered as a P1–P12 transport result in WAT-04.

## 2. Required project configuration

| Concern | Required value | Current WC Probe value |
| --- | --- | --- |
| Relationship | Watch app for an existing iOS app | Companion |
| iOS bundle ID | Root identifier | `com.drewreilly.wellspent.connectivityspike` |
| watchOS bundle ID | iOS ID plus `.watchkitapp` | `com.drewreilly.wellspent.connectivityspike.watchkitapp` |
| Companion key | Exact iOS bundle ID | `WKCompanionAppBundleIdentifier` matches |
| Independent install | Disabled for this iPhone-dependent probe | `WKRunsIndependentlyOfCompanionApp = NO` |
| Watch-only distribution | Disabled | `WKWatchOnly` absent |
| Embedding | Watch app embedded in iOS app's `Watch` directory | Xcode 26.6 copy phase uses subfolder 16 plus `RemoveHeadersOnCopy` |
| Signing | Automatic, same development team on both targets | Team `68LEY459MW` |
| Versions | Matching marketing and build versions | `1.0` / `2` on both |
| Deployment | Supported by both test devices | iOS 26.0 / watchOS 26.0 |
| Connectivity capability | No special entitlement | None required |

XcodeGen 2.45.4 generates the same `Watch` embed destination as a native Xcode
26.6 companion project. The dependency also sets `RemoveHeadersOnCopy`. Do not
rewrite that destination to `PlugIns`: the probe remained directly runnable on
both devices in that layout, but iOS reported `isWatchAppInstalled == false`
and Watch Connectivity rejected transfers with error 7006. A tiny native Xcode
26.6 companion project was used to establish the current source of truth.
`scripts/watch-test-preflight.sh` verifies both the generated project and built
package on every run.

At runtime, both apps must configure and activate `WCSession`. Only after the
iOS session reports `Activated`, `Paired Watch: Yes`, and
`Watch app: Installed` may a transfer scenario begin. `Reachable: No` is not an
installation failure; reachability only governs the immediate `sendMessage`
fast path.

## 3. Test ladder

Use the lowest tier that can prove the behavior. A higher tier supplements the
lower tiers instead of replacing them.

| Tier | Environment | What it proves | When it runs |
| --- | --- | --- | --- |
| T0 | Static preflight | Bundle relationship, plist values, embedded path, build versions | Every Watch change |
| T1 | iOS Simulator tests | Codable stability, reducers, persistence, idempotency, ordering, snapshot/outbox invariants | Every Watch change and CI |
| T2 | Paired iPhone + Watch Simulators | Both apps install and launch; UI states, accessibility, layouts, and injected/fake transport flows | Every UI change |
| T3 | Paired physical devices, Xcode attached | Activation, counterpart detection, foreground `sendMessage`, and durable duplicate convergence | Each transport change |
| T4 | Paired physical devices, debugger detached | Suspension, termination, opportunistic delivery, radio changes, persistence, and background task completion | WAT-04 and release candidates |
| T5 | Internal TestFlight | Distribution signing, install/update behavior, and release-like packaging | Before external beta/release |

The architecture should keep serialization, persistence, reducers, and UI
presentation independent from `WCSession`. New behavior belongs in deterministic
tests first. A transport adapter or fake may drive T2 UI flows, but it cannot
substitute for T3 or T4.

## 4. Simulator workflow

For the complete product regression gate (including both platforms' clean
Debug/Release builds, device-SDK compilation, unit tests and focused UI tests):

```sh
KEEP_CLEAN_CHECKOUT=1 bash scripts/verify-clean-checkout.sh
```

See [WAT-22-CI-AUTOMATION.md](WAT-22-CI-AUTOMATION.md) for exact coverage and
retained evidence. Runtime tests use normal Simulator signing for App Groups;
`CODE_SIGNING_ALLOWED=NO` is reserved for the separate compile gates. Fixture
transport is injected and cannot publish synthetic catalogs to a paired device.

For the historical WC Probe's packaging preflight only:

```sh
scripts/watch-test-preflight.sh
```

For the production WAT-10 transport boundary, also run:

```sh
scripts/watch-connectivity-check.sh
xcodebuild -project WellSpent.xcodeproj -scheme WellSpent \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:WellSpentTests/PhoneWatchSyncStoreTests test
xcodebuild -project WellSpent.xcodeproj -scheme WellSpentWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest' \
  -only-testing:WellSpentWatchTests/WatchConnectivityCoordinatorTests test
```

These use fake session adapters to force reachability, loss, duplication,
reordering, and restart windows deterministically. They validate production
stores and coordinators, but still do not count as a physical transport result.

List and create a simulator pairing when needed:

```sh
xcrun simctl list pairs
xcrun simctl pair <watch-simulator-udid> <iphone-simulator-udid>
```

Run the paired install/launch smoke after exporting the two device IDs:

```sh
WATCH_PHONE_SIMULATOR_ID=<iphone-simulator-udid> \
WATCH_SIMULATOR_ID=<watch-simulator-udid> \
scripts/watch-simulator-smoke.sh
```

The smoke script runs focused UI tests through both Xcode schemes on their exact
Simulator destinations and verifies both app containers exist. Xcode owns the
test installation; the script intentionally does not install the two bundles
independently with `simctl`. Its success means only that T2 installation,
launch, and preflight UI passed.

Do not require Simulator to report `Watch app: Installed`, counterpart
reachability, or delivery. The current paired Xcode 26.6 simulators install and
launch both app containers but still report the Watch app as not installed to
the iOS `WCSession`. The probe labels Simulator builds as **UI test mode** and
keeps transport controls disabled. This observed limitation reinforces the
physical-device boundary; it is not a product defect or a WAT-04 result.

For UI work, exercise at least the smallest and largest supported Watch sizes,
large text, VoiceOver labels, reduced motion, inactive/paused/running states,
long project names, and privacy-redacted Always On presentation. Prefer model
data and fake transport states so tests are deterministic.

### UI automation evidence rules

- Run only one UI test job per Simulator. Before a retest, confirm the previous
  process is terminal and use a new result-bundle path. Different DerivedData
  directories do not make overlapping jobs on one Simulator safe.
- Keep screenshots and accessibility trees together. A successful accessibility
  audit alone does not prove that a wheel, scrolling editor, or retry action is
  usable; perform the action and verify the resulting persisted state.
- For long explanations, bring the whole message into view and inspect the
  screenshot. Watch text-only List rows can ellipsize while accessibility still
  exposes the full string; forcing text height can instead draw outside the row.
  WAT-23's goal form uses a scrolling stack so its text and controls share actual
  layout bounds. The custom wheel remains outside that scrolling branch.
- Treat app content and native navigation chrome separately when checking the
  viewport. A content inset must not incorrectly exclude a legitimate native
  Close button or bottom alert action.
- Inspect native dialog structure before measuring its controls. On watchOS
  26.5, an alert can expose duplicate message nodes and an OK text-sized Button
  inside a much larger tappable table row. Select that exact row, verify its
  size, tap it, and verify dismissal. Do not expand audit exclusions or shrink
  app-owned targets to accommodate a test query mistake.
- Permission and persistence failure fixtures must be disconnected from real
  Watch Connectivity and system notifications. Label one-shot failures
  explicitly, verify retries and unchanged timer state, and prove fixture flags
  and implementations are absent from Release binaries.
- Retain failed runs and identify harness failures, app failures, and platform
  exceptions separately. Only the corrected, completed retest is pass evidence.

## 5. Clean physical installation baseline

Use this sequence for the next WAT-04 attempt. Do not begin P1 until every
preflight check passes.

For the production WellSpent pair, capture a read-only prerequisite report
before any install or launch:

```sh
bash scripts/watch-product-device-preflight.sh \
  <iphone-xcode-id> <watch-xcode-id> .derivedData/NEW-PREFLIGHT-DIRECTORY
```

The report retains model/OS, route, Developer Mode, exact bundle versions and
readiness booleans, but no device identifiers, serials, hostnames or app data.
A nonzero result means preparation is blocked; it is not a failed transport row.
The WC Probe steps below remain historical WAT-04 instructions and do not replace
this product preflight for WAT-24/26.

1. Connect the paired iPhone directly to the Mac with a data-capable USB cable.
   Charging is not proof of a data connection. Confirm the iPhone appears in
   macOS's USB device tree and that Xcode does not report a network-only route.
   Unlock both devices, trust the Mac, and confirm Developer Mode is enabled.
   Keep the Watch on-wrist and unlocked, or wake and unlock it immediately
   before every physical run; an off-wrist Watch can relock while Xcode prepares
   the destination. In Xcode's Device Hub, wait until the iPhone and its paired
   Watch are available with no preparation message.
2. Delete the old **WC Probe** from both devices once after any package-layout
   or signing correction. Do not routinely delete apps between lifecycle
   scenarios; their persisted outbox is part of what we are testing.
3. Run `scripts/watch-test-preflight.sh`, then open `WellSpent.xcodeproj`.
4. Select `WellSpentConnectivitySpikeWatch`. Choose the physical Watch
   destination that also displays the paired iPhone name. Press Run. Because
   this is a dependent Watch app, Xcode owns installation of the Watch app and
   its iOS companion.
5. Verify WC Probe launches on Watch and is present on iPhone. Launch the iPhone
   probe from its Home Screen if Xcode did not foreground it. Do not repair a
   missing side with `devicectl`; stop and fix the Xcode target relationship.
6. On iPhone wait for all three values: `Session: Activated`,
   `Paired Watch: Yes`, and `Watch app: Installed`. On Watch confirm
   `Activated`. Apple documents the Watch-side `isCompanionAppInstalled`
   property for independent apps, so it is not a readiness gate for this
   dependent probe. Capture a screenshot of this preflight.
7. Press **Advance Synthetic Catalog Snapshot** to create a new generation and
   publish it. Wait for the Watch generation to match and the phone snapshot
   receipt count to increase before P1. Republishing unchanged bytes is allowed
   to be classified as stale and need not create a second receipt.

For P1, keeping Xcode attached is acceptable because both apps are foreground.
For P2–P12, press Stop in Xcode, then launch the apps from their Home Screens
and put them into the scenario's stated lifecycle state. Running under Xcode
can prevent normal Watch suspension, so attached runs are invalid background
evidence.

### Automated foreground baseline and P1

The physical UI tests are intentionally separate so each test runner owns the
device it drives. Start the Watch sender first; while it waits for foreground
reachability, start the iPhone receiver in a second terminal. This shortens the
Watch destination-preparation window and avoids an off-wrist device relocking
before Xcode starts its runner. Use distinct derived-data and result-bundle
paths for the two concurrent processes.

The baseline test is:

```sh
xcodebuild -project WellSpent.xcodeproj \
  -scheme WellSpentConnectivitySpikePhone \
  -destination 'platform=iOS,id=<iphone-xcode-id>' \
  -only-testing:WellSpentConnectivitySpikePhoneUITests/ConnectivitySpikePhoneUITests/testPhysicalCompanionRoundTrip \
  test
```

The paired P1 tests are:

```text
Phone: ConnectivitySpikePhoneUITests/testPhysicalP1Receiver
Watch: ConnectivitySpikeWatchUITests/testPhysicalP1StartPauseResumeEnd
```

The receiver resets only the disposable phone probe state, then asserts four
unique terminal inbox rows, four canonical generations, at least four duplicate
deliveries, and no block. The Watch test resets its disposable state after
activation, drives Start/Pause/Resume/End, and asserts four acknowledgements,
no error, and an empty outbox. A P1 row is accepted only when both result
bundles pass in the same run, three times. If Xcode reports that the Watch may
need to be unlocked, the paired run is preparation-blocked and is not counted.

### Detached P2 automation

P2 must not run under an Xcode debugger or UI-test runner. After installing the
current Debug build through the unified companion schemes, run:

```sh
scripts/watch-physical-p2.sh \
  <iphone-xcode-id> \
  <watch-xcode-id> \
  .derivedData/WAT04-P2-Run1
```

The harness first force-stops the disposable Watch process and verifies its PID
is gone. It performs a sanitizer launch that resets probe state and cancels
transfers left by earlier attempts, waits for activation, then force-stops and
verifies termination again. Only after that does it reset and launch the phone,
foreground Settings to create a normal background transition, and launch a
fresh Watch process without a debugger. Debug-only launch flags disable the
reachable message fast path on both sides and queue one Start eight seconds
after the Watch session activates. This guarantees the required order: phone
background first, fresh Watch mutation second. Acceptance requires the exported
phone state to show one terminal user-info mutation received while reachability
was false, one canonical generation, and a durable acknowledgement queued. The
detached Watch state export must independently show that the same named
acknowledgement was saved and the outbox became empty. Neither a UI-test
assertion nor foreground message delivery is accepted as P2 evidence.

Do not rely on `devicectl --terminate-existing` or a graceful termination alone
for run isolation. A Watch process can remain alive after the command returns,
causing the next launch to reuse the old environment and persisted state. The
harness uses a kill plus process-disappearance check because WC Probe is a
disposable test target. It also matches the mutation UUID across phone and
Watch exports so a delayed transfer from an earlier attempt cannot be accepted.

### Detached P3 automation

P3 reuses the same sanitation and UUID-matching core:

```sh
scripts/watch-physical-p3.sh \
  <iphone-xcode-id> \
  <watch-xcode-id> \
  .derivedData/WAT04-P3-Run1
```

The wrapper launches and resets the iPhone probe, force-terminates its process,
and verifies the exact installed executable PID is gone before creating the
Watch mutation. A no-process result is evidence only after the harness first
identified and printed that exact PID; a stale or partial bundle-path match is
not accepted. It observes
the phone container without launching the app for up to 600 seconds. If iOS
does not wake the app, it then relaunches the phone without resetting state and
continues waiting. `classification.json` records `system_wake` or
`manual_relaunch`, the matched mutation UUID, commit/persist timestamps, and
the observed delay. A run passes only after the matching durable ack is saved
on Watch and its outbox is empty.

## 6. Failure triage

| Observation | Classification | Next action |
| --- | --- | --- |
| Session not Activated | Session lifecycle/setup | Do not transfer; inspect activation error and delegate callbacks |
| iPhone says Paired Watch: No | Pairing/device selection | Select the destination containing the intended phone/watch pair |
| iPhone says Watch app: Not installed | Packaging/install/signing | Confirm the phone bundle contains `Watch/WellSpentConnectivitySpikeWatch.app`, delete both stale probes, and rerun the unified Watch scheme through Xcode |
| `snapshot_publish_failed_7006` | Invalid install baseline | Record no transport result; return to the clean installation baseline |
| Activated + installed, Reachable: No | Normal fast-path state | Foreground both apps for `sendMessage`; durable physical transfer may still proceed |
| Xcode says Watch may need to be unlocked | Hardware preparation | Wake/unlock the Watch, keep it near the Mac, confirm the destination clears, and restart both halves of the paired row; do not count the interrupted run |
| CoreDevice reports L2CAP, control-channel, or service-socket failure before Watch launch | Hardware preparation | Put the Watch on-wrist, unlock and wake it, verify it appears without an error in Xcode destinations, and retry; no mutation is counted when launch never completed |
| `xctrace list devices` places both phone and Watch under Devices Offline | Paired route unavailable | Unlock the iPhone, leave it on the Home Screen, verify/reseat USB and trust, keep the Watch on-wrist and unlocked, and wait until both move to Devices before retrying |
| The iPhone charges but macOS's USB device tree contains no iPhone, and CoreDevice reports `transportType: localNetwork` | No wired data route | Move the phone to a direct Mac port and use a known data-capable cable; do not begin detached evidence collection on the opportunistic network tunnel |
| Watch launches, then moves to `Devices Offline` when its screen sleeps | Evidence route lost | Let Watch Connectivity continue, but wake/unlock the Watch before the required post-run state export; classify the row as unverified if the named Watch outbox/ack state cannot be exported |
| Simulator transfer is absent/delayed | Unsupported evidence | Use reducer/fake tests there; rerun transport scenario on physical devices |
| Foreground works, detached/background fails | Transport/lifecycle defect | Export content-free evidence and keep WAT-04 In Progress |

Never change several plist, signing, installation, and transport variables in a
single retry. Establish the three-value iPhone preflight first, then change one
scenario condition at a time.

## 7. WAT-04 session checklist

For each physical row:

1. Record device models, OS versions, Xcode version, app build number, and
   whether the debugger is attached.
2. Confirm the install preflight; export old evidence before resetting state.
3. Reset both probes only at the boundary between scenarios.
4. Run one matrix row exactly as written and wait for its terminal condition.
5. Export the content-free evidence JSON and name it with row, run number, and
   timestamp.
6. Record pass/fail and observed delivery delay. Three passing runs are needed
   per row.
7. Update Linear issue `IDK-366` after each completed row or blocker. Keep it
   In Progress until every WAT-04 acceptance condition is satisfied. Keep
   `IDK-368` in Backlog until then.

## 8. Authoritative references

- [Apple: Run an app on a device](https://help.apple.com/xcode/mac/current/en.lproj/dev5a825a1ca.html)
- [Apple: Running on simulated or physical devices](https://developer.apple.com/documentation/xcode/running-your-app-on-simulated-or-physical-devices)
- [Apple: Setting up a watchOS project](https://developer.apple.com/documentation/watchos-apps/setting-up-a-watchos-project)
- [Apple TN3157: Updating a watchOS project](https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit)
- [Apple: WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)
- [Apple: transferUserInfo](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:))
- [XcodeGen issue 1613: Xcode 26 Watch embed destination](https://github.com/yonaskolb/XcodeGen/issues/1613)
