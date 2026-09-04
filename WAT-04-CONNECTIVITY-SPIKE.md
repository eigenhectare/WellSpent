# WAT-04 — Watch Connectivity Physical-Device Spike

Status: In progress; code-complete probe and automated checks pass, paired
physical-device evidence is required before completion  
Protocol: [WAT-03-WATCH-SYNC-CONTRACT.md](WAT-03-WATCH-SYNC-CONTRACT.md)  
Testing: [WATCH-TESTING-GUIDE.md](WATCH-TESTING-GUIDE.md)  
Last updated: September 1, 2026

## 1. Purpose and acceptance boundary

This disposable probe tests the Watch Connectivity assumptions that the product
foundation will depend on. It is intentionally separate from the WellSpent
production store and carries only synthetic project and opaque entity IDs. It
must not be promoted into production; WAT-07 through WAT-10 will implement the
validated behavior at production quality.

Simulator compilation and deterministic reducers can prove Codable stability,
idempotency, crash-state persistence, and snapshot/outbox rules. They cannot
prove Watch Connectivity delivery. Apple explicitly requires a physical iPhone
and Apple Watch for its [Watch Connectivity sample](https://developer.apple.com/documentation/WatchConnectivity/transferring-data-with-watch-connectivity),
and documents that `transferUserInfo` is not supported by Simulator. WAT-04
therefore remains In Progress until the physical matrix in section 6 is
recorded.

## 2. Probe targets and behavior

`project.yml` generates five disposable targets:

- `WellSpentConnectivitySpikePhone` — canonical inbox, dedupe reducer,
  acknowledgement sender, latest-snapshot publisher, and evidence exporter.
- `WellSpentConnectivitySpikeWatch` — durable local command/outbox, immediate
  plus queued transport, acknowledgement compaction, snapshot installation, and
  Watch connectivity background-task completion.
- `WellSpentConnectivitySpikeTests` — pure Codable, persistence, duplicate,
  reordering, and snapshot/outbox tests.
- `WellSpentConnectivitySpikePhoneUITests` and
  `WellSpentConnectivitySpikeWatchUITests` — focused Xcode-driven Simulator
  installation, launch, and preflight-UI smoke tests.

The paired bundle IDs are:

- `com.drewreilly.wellspent.connectivityspike`
- `com.drewreilly.wellspent.connectivityspike.watchkitapp`

The Watch target declares the phone ID with
`WKCompanionAppBundleIdentifier` and explicitly declares itself dependent with
`WKRunsIndependentlyOfCompanionApp = NO`. The iOS spike target embeds the Watch
app under `Watch`, matching a native Xcode 26.6 companion project. Its copy
phase uses destination 16 and `RemoveHeadersOnCopy`.
The separate schemes choose which app Xcode launches; they do not authorize
installing the two bundles independently.

### Frozen protocol coverage

- Codable versioned mutation payload plus SHA-256 digest.
- Mutation UUID, origin UUID/sequence, captured timestamp/zone, canonical base,
  predecessor, observed run/revision, and preallocated run/segment IDs.
- Synthetic Start, Pause, Resume, and End state chain.
- Atomic file-backed Watch local state and outbox before dispatch.
- Immediate `sendMessage` fast path and durable `transferUserInfo` for the same
  immutable bytes.
- Two-phase phone inbox: durable `received`, then apply/outcome/ack.
- Exact mutation dedupe and predecessor-aware out-of-order holding.
- Durable acknowledgement before Watch outbox compaction.
- Complete `updateApplicationContext` snapshot that never removes a pending
  outbox entry.
- Snapshot receipt sent back with `transferUserInfo`.
- Content-free evidence codes with opaque IDs, sequence, generation,
  reachability, transport, and timestamp.
- `WKWatchConnectivityRefreshBackgroundTask` retention/completion after pending
  content drains.

The phone's **Hold Inbox Before Apply** and **Hold Acknowledgements** toggles are
fault-injection controls. **Advance Synthetic Catalog Snapshot** advances the
canonical generation without user content so application-context replacement
can be observed. **Reset Synthetic Probe** is destructive only to disposable
probe state; export evidence first.

## 3. Automated evidence recorded

On September 1, 2026 with Xcode 26.6 (17F113):

| Gate | Result |
| --- | --- |
| Swift format/lint | Pass |
| iOS Simulator generic Debug compile | Pass |
| watchOS Simulator generic Debug compile | Pass |
| Unsigned iOS device-SDK Debug compile | Pass |
| Unsigned watchOS device-SDK Debug compile | Pass |
| iPhone 17 Pro / iOS 26.5 protocol tests | 5 passed, 0 failed, 0 skipped |
| Paired iPhone 17 Pro + Watch Ultra 3 Simulator UI smoke | 2 passed, 0 failed, 0 skipped |

The five protocol tests cover deterministic digest/round-trip encoding, atomic state
reopen with pending outbox, phone two-phase application plus duplicate receipt,
out-of-order predecessor holding/application, and the rule that a newer
snapshot cannot compact an unacknowledged command.

The two focused UI tests use Xcode's test installation path and verify that the
iPhone and Watch probe apps launch with their installation-preflight controls.
The paired Simulator still reports the Watch app as not installed through
`WCSession`, so no Simulator connection or delivery state is accepted as
transport evidence.

These results are compile/domain evidence only. They are not reported as
foreground, background, suspended, terminated, radio-change, or paired-device
transport evidence.

## 4. Build and install on paired hardware

The complete install and test runbook is in the
[Watch testing guide](WATCH-TESTING-GUIDE.md). Run the automated preflight
before connecting hardware:

```sh
scripts/watch-test-preflight.sh
```

For physical development testing, Xcode Run is the authoritative installer:

1. After deleting the invalid mixed-install baseline from both devices, select
   `WellSpentConnectivitySpikeWatch` and the destination that names the paired
   physical Watch and iPhone, then Run.
2. Do not install either side independently with `devicectl`. If Xcode does not
   install the dependent companion pair, stop and repair packaging/signing.
3. On iPhone require `Activated`, `Paired Watch: Yes`, and
   `Watch app: Installed`; on Watch require `Activated` before publishing the
   first snapshot.
4. For background/suspension cases, stop debugging and launch both apps from
   their Home Screens. Apple's sample warns that running under Xcode can prevent
   normal Watch suspension and produce different background behavior.

Do not move the embedded companion to the iOS `PlugIns` directory. That layout
can produce two directly runnable apps while preventing iOS from registering
the Watch app as its companion; `WCSession.isWatchAppInstalled` is the readiness
oracle, not the device app inventory.

The spike uses no App Group, HealthKit, notifications, server, or third-party
dependency. Watch Connectivity itself requires no networking entitlement.

## 5. Evidence handling

The phone's **Prepare Evidence Export** then **Share Evidence JSON** actions
produce an ordered content-free event file. Before each scenario:

1. export any prior evidence that must be retained;
2. reset both Watch and phone probe state;
3. open the phone, publish its latest snapshot, and wait until the Watch shows
   the same generation;
4. record device models, OS builds, scenario start/end, radio state, app process
   state, result, and evidence filename.

Never add project names, notes, tags, client data, or user-entered text to the
probe. Use the generated opaque IDs and fixed evidence codes. Screenshots may
show only the probe UI.

## 6. Required physical matrix

Each row must be run at least three times. Opportunistic delay is recorded as an
observation, not automatically a failure. A missing command, duplicate domain
application, replaced boundary, premature outbox removal, or uncompleted Watch
background task is a failure.

| ID | Setup and action | Required evidence | Status |
| --- | --- | --- | --- |
| P1 | Both apps foreground/reachable; queue Start, Pause, Resume, End | Message and user-info duplicates produce one terminal inbox row and one generation per mutation; Watch outbox returns to zero | Passed — 3/3 |
| P2 | Phone Home-screen launched, then backgrounded/suspended; queue Start on Watch | Phone receives queued user info without being foreground first; later durable ack removes named Watch outbox row | Passed — 3/3 |
| P3 | Terminate phone process after a Home-screen launch; queue Start on Watch; wait, then relaunch only if the system does not wake it | Exact receive/wake behavior and delay recorded; command remains in Watch outbox until durable phone ack | Passed — 2 corrected runs; third repeat waived by user |
| P4 | Enable **Hold Inbox Before Apply**; queue Start; confirm `phone_inbox_persisted`; terminate phone; relaunch | Received row resumes to one applied mutation/generation; no second run or segment | Pending |
| P5 | Enable **Hold Acknowledgements**; queue Start; confirm phone applied and Watch still has one outbox row; terminate/relaunch phone; disable hold and retry acks | Retry returns the original named ack/generation; Watch compacts only after saving it | Pending |
| P6 | Make devices unreachable; queue Start then Pause; suspend Watch; restore connectivity | Both immutable commands arrive in causal order or are held until predecessor; one running-to-paused chain, two acks | Pending |
| P7 | Foreground/reachable; queue a command and use **Retry Pending** before its ack | Repeated user-info/message delivery yields one application and the stored acknowledgement | Pending |
| P8 | While unreachable and with no Watch mutation, advance three synthetic catalog snapshots; reconnect | Watch installs only the latest complete generation; no intermediate context is required | Pending |
| P9 | While a Watch command is pending, republish/replace application context, then reconnect | Snapshot installation never removes the outbox mutation; only the named ack compacts it | Pending |
| P10 | Alternate Bluetooth, Wi-Fi, and available cellular paths during a Start/Pause/Resume/End chain | Reachability changes affect fast path only; durable commands and acks eventually converge | Pending |
| P11 | Terminate Watch sender after local commit and before ack; relaunch from Home Screen | Persisted outbox and origin sequence survive; retry uses identical mutation/boundary bytes | Pending |
| P12 | Generate multiple queued deliveries, lower wrist, and wait for background processing | `watch_background_wake` occurs when applicable and no background-budget crash occurs; task completes after content drains | Pending |

For P3, distinguish an OS-terminated process from a user force-quit and record
both if behavior differs. Do not rewrite the protocol to promise background
launch in a state where the operating system intentionally suppresses it.

## 7. Acceptance interpretation

WAT-03 is validated when the physical results demonstrate:

- at least one Watch-origin command reaches a suspended/terminated iPhone and
  later returns a durable named acknowledgement;
- sender and receiver termination retries never apply a mutation twice;
- application-context replacement cannot erase or acknowledge a queued
  mutation;
- `sendMessage` improves latency only and all correctness survives without it;
- background-task handling completes without a Watch budget crash;
- no observed ordering, duplication, or reachability behavior contradicts the
  frozen causal/dedupe rules.

If a row contradicts WAT-03, keep WAT-04 In Progress, attach the content-free
evidence to Linear issue `IDK-366`, update the WAT-03 contract through an
explicit decision, adjust the spike, and repeat the affected rows. WAT-05 and
the cross-device foundation must not begin until this issue is Done.

## 8. Current result log

| Date | Hardware / OS | Rows | Result | Evidence |
| --- | --- | --- | --- | --- |
| 2026-09-01 | Simulator compile + iPhone 17 Pro iOS 26.5 reducer tests | Automated only | Pass; physical transport not exercised | Local xcresult under `.derivedData/WAT04-Tests` |
| 2026-09-01 | iPhone 17 Pro Max / iOS 26.6.1 + Apple Watch Ultra 2 / watchOS 26.6 | Hardware preparation only | Device pairing, Developer Mode, registration, and signing passed; independently launched apps did not establish a valid companion installation | Xcode/CoreDevice preparation output; this is not transport evidence |
| 2026-09-01 | Same physical pair | P1 setup attempt | Blocked before P1: mixed `devicectl`/Xcode installation returned `WCErrorDomain` 7006 (`watchAppNotInstalled`), so no protocol result was recorded | Device console and content-free `snapshot_publish_failed_7006` event |
| 2026-09-01 | iPhone 17 Pro + Watch Ultra 3 Simulators / iOS and watchOS 26.5 | Revised T0–T2 baseline | Pass: configuration/package preflight, both builds, 5 protocol tests, and 2 focused UI launch tests; Simulator `WCSession` install state excluded from acceptance | Local xcresults under `.derivedData/WatchPreflight` and `.derivedData/WatchSimulatorSmoke`; physical companion reinstall pending |
| 2026-09-01 | iPhone 17 Pro Max / iOS 26.6.1 + Apple Watch Ultra 2 / watchOS 26.6 | Physical installation preflight | Pass: native `Watch/` embed layout installed through the unified Watch scheme; iPhone reported Activated, Paired Watch Yes, and Watch app Installed | `.derivedData/WatchNativeLayoutRoundTrip.xcresult`; foreground reachability attempt failed because the Watch process was no longer running, so no P1 transport result recorded |
| 2026-09-01 | Same physical pair, both apps foreground, Xcode test runners attached | Snapshot baseline | Pass in 14.4 seconds: new canonical generation installed on Watch and durable snapshot receipt returned to iPhone | `.derivedData/WatchNativeLayoutRoundTrip5.xcresult` |
| 2026-09-01 | Same physical pair, both apps foreground, Xcode test runners attached | P1 run 1 of 3 | Pass: Start/Pause/Resume/End produced exactly four inbox rows, four terminal results, four canonical generations, at least four duplicate deliveries, four Watch acks, no block/error, and zero Watch outbox rows | `.derivedData/WAT04-P1-Run2-Phone.xcresult` and `.derivedData/WAT04-P1-Run2-Watch.xcresult` |
| 2026-09-01 | Same physical pair | P1 repeat setup | Not counted: Xcode refused the Watch destination because the Watch had locked; the paired phone receiver timed out at reachability and no mutation was sent | `.derivedData/WAT04-P1-Pass2-Phone.xcresult` and `.derivedData/WAT04-P1-Pass2-Watch.xcresult` |
| 2026-09-01 | Same physical pair, both apps foreground, Xcode test runners attached | P1 run 2 of 3 | Pass: all phone receiver assertions and Watch Start/Pause/Resume/End sender assertions passed; four Watch acks, no block/error, and zero Watch outbox rows | `.derivedData/WAT04-P1-Run3-Phone.xcresult` and `.derivedData/WAT04-P1-Run3-Watch.xcresult` |
| 2026-09-01 | Same physical pair | P1 final-repeat setup attempts | Not counted: the Watch relocked during Xcode destination preparation; the Watch runner sent no mutation and the phone receiver either timed out or was interrupted | `.derivedData/WAT04-P1-Run4-Phone.xcresult`, `.derivedData/WAT04-P1-Run4-Watch.xcresult`, `.derivedData/WAT04-P1-Run5-Phone.xcresult`, and `.derivedData/WAT04-P1-Run5-Watch.xcresult` |
| 2026-09-01 | Same physical pair, both apps foreground, Xcode test runners attached | P1 run 3 of 3 | Pass: Watch-first launch avoided the destination-preparation race; all four mutations, phone reducer assertions, four durable acknowledgements, and zero-outbox assertion passed | `.derivedData/WAT04-P1-Run6-Phone.xcresult` and `.derivedData/WAT04-P1-Run6-Watch.xcresult` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 run 1 setup | Not accepted: the phone remained backgrounded and the Watch committed one durable Start while unreachable, but the eventual phone receipt used the reachable `message` fast path after a Watch relaunch instead of the required queued `userInfo` path | `.derivedData/WAT04-P2-Run1/phone-state.json` and `.derivedData/WAT04-P2-Run1/watch-state.json`; matching mutation `0BD39AE8-EE85-4F22-9E68-8EC167C5DBD7` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 durable-only setup retries | Not counted: durable-only builds and state-export harness passed local validation, but the Watch lost its CoreDevice control channel before launch (`device unavailable`, service-socket unsupported, L2CAP, and network-tunnel failures); `xctrace` ultimately reported both paired devices offline and no Watch mutation was committed | `.derivedData/WAT04-P2-Run2` through `.derivedData/WAT04-P2-Run6` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 run 7 setup | Not counted: the Watch launch command timed out and the later process/state inspection showed only the stale pre-run process and evidence; no new mutation was committed | `.derivedData/WAT04-P2-Run7/watch-state-post-timeout.json` and `.derivedData/WAT04-P2-Run7/phone-state-post-timeout.json` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 run 8 | Unverified and not counted: the revised harness reset/backgrounded the iPhone before a successful fresh Watch launch, but the phone remained at inbox 0/generation 0 for the full 600-second window. The Watch developer tunnel then remained offline, preventing the required outbox/ack export. macOS USB inspection showed no physically enumerated iPhone, while CoreDevice used an unstable `localNetwork` route | `.derivedData/WAT04-P2-Run8/phone-state.json`; Watch post-run state unavailable |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 run 9 | Not counted: the phone received delayed Run 8 mutation `E5BCC6F3-073B-4D9C-8671-B8F50641DB5B` before fresh Run 9 mutation `0ABAA513-6F8C-46AC-A21F-68AA1A48596C` was committed, proving the row was contaminated by an earlier queued transfer | `.derivedData/WAT04-P2-Run9/phone-state.json` and `.derivedData/WAT04-P2-Run9/watch-state.json` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 run 10 | Not counted: sanitation delivered the Run 9 mutation, then graceful Watch termination returned before the process exited; the supposed fresh launch reused the old process/environment and committed no new mutation | `.derivedData/WAT04-P2-Run10/phone-state.json` and `.derivedData/WAT04-P2-Run10/watch-state.json` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P2 runs 11–13 | Pass — 3/3: each backgrounded phone received exactly one fresh Start through `userInfo` while unreachable, applied one canonical generation, and queued a durable ack. Each Watch export contained the matching mutation UUID, one saved `userInfo` ack, and zero outbox rows | `.derivedData/WAT04-P2-Run11`, `.derivedData/WAT04-P2-Run12`, and `.derivedData/WAT04-P2-Run13`; mutations `0AF7167A-D9B9-4A61-BCA8-8442A2BE12D1`, `7813D593-8772-457A-A33D-1F7CB625E998`, and `9D014542-B42F-4A51-B2E0-46360CDA519D` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P3 run 1 setup | Not counted: the phone process had already exited when the verifier checked it, and a strict-shell no-process branch returned failure before any Watch mutation was created | `.derivedData/WAT04-P3-Run1` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P3 runs 2–4 | Superseded and not accepted: the phone-process matcher targeted the probe's old executable path, so those runs did not prove process termination. Their transport results remain diagnostic only | `.derivedData/WAT04-P3-Run2`, `.derivedData/WAT04-P3-Run3`, and `.derivedData/WAT04-P3-Run4` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P3 corrected runs 5–6 | Pass — 2/2 completed: the exact iPhone executable PID was killed and verified absent, iOS did not system-wake it during either 600-second observation, a state-preserving manual relaunch applied the named `userInfo` mutation once, and each durable acknowledgement returned with the Watch outbox at zero | `.derivedData/WAT04-P3-Run5` and `.derivedData/WAT04-P3-Run6`; mutations `D5B7A6F2-4860-41ED-92F1-3C4458ECBC3E` and `706C6596-D828-49FD-A5E1-528066069D30` |
| 2026-09-01 | Same physical pair, detached CoreDevice launches | P3 corrected run 7 | Stopped at the user's request after verified phone termination and about 55 seconds of observation. Not counted; the user explicitly waived the third completed repetition and accepted P3 as passed on runs 5–6 | `.derivedData/WAT04-P3-Run7` |

P1 and P2 have all three required passes. P3 is accepted as passed on two
corrected completed runs with an explicit user waiver for the third. The
package/association blocker is resolved; P4–P12 remain. A physical UI run requires the
Watch to be unlocked and near the Mac for the entire destination-preparation
window. Hardware preparation also enabled Developer Mode on the Watch and
registered it with the configured development team for device provisioning.
