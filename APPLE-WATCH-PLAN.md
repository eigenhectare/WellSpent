# WellSpent for Apple Watch — Product, Engineering, and Release Plan

## 1. Outcome

Build a companion Apple Watch app that makes starting, monitoring, pausing,
switching, and ending billable work feel as immediate and familiar as Apple's
Workout app while preserving WellSpent's exact timestamp, local-first, and
privacy guarantees.

This is behavioral parity, not a visual clone. We will reuse the Workout app's
interaction grammar—recent-first choices, one-tap start, live
metrics, a dedicated control surface, optional goals, haptics, and an end
summary—while using WellSpent's own identity, copy, project colors, and data.
Apple's App Review guideline 4.1 prohibits simply copying another app's name or
UI, so Apple artwork, Activity rings, health language, and Workout branding are
out of scope.

## 2. Decisions made by this plan

- Ship a watchOS companion inside the existing WellSpent iOS product, not a
  separate watch-only App Store product.
- Target watchOS 26.0 to match the app's iOS 26.0 baseline. This covers Apple
  Watch Series 6 and later, Apple Watch SE 2 and later, and every Apple Watch
  Ultra model supported by watchOS 26.
- Make the watch useful when the paired iPhone is temporarily unreachable. A
  cached project list and a durable watch-local command outbox make Start,
  Pause, Resume, Switch, and End available offline.
- Keep the iPhone store as the canonical merged record. The watch confirms a
  command only after writing it locally, then transfers the idempotent command
  to the phone. Neither device silently discards time when histories diverge.
- Preserve the current no-account/no-server posture. Watch Connectivity is the
  direct device-to-device transport; private CloudKit remains a separate later
  milestone and is not required for the Watch release.
- Do not start an `HKWorkoutSession`, write HealthKit data, request health
  permissions, or claim the Workout Processing background mode. Billable work
  is not a fitness activity, and those APIs must not be used to keep a timer
  alive.
- Do not use `WKExtendedRuntimeSession`; its allowed session categories and
  time limits do not fit an hours-long work timer. Elapsed time remains derived
  from persisted boundaries, not a continuously running process.
- Add an optional duration goal. Goal alerts request notification permission
  only when a user first enables an alert, never on launch. The timer still
  works fully if permission is denied.
- Add real Pause and Resume semantics. Paused time does not count toward
  reports, and a paused activity survives process or device restart.
- Offer a WidgetKit complication, Smart Stack widget, App Intents, and watchOS
  26 Control Widget after the core app and sync path are reliable.
- Keep project names hidden by default on always-visible Watch surfaces, just
  as they are on the iPhone Lock Screen. In-app project names remain visible
  after the watch is unlocked.

## 3. Current app constraints

The repository already has strong foundations worth preserving:

- SwiftUI app architecture with explicit project, timer, and session command
  boundaries.
- Versioned SwiftData v2 store with deterministic migration tests.
- One-active-timed-session reconciliation that preserves conflicting records
  for explicit review.
- Persist-first, idempotent Stop keyed by the session UUID.
- Timestamp-derived elapsed displays and exact atomic Switch boundaries.
- Local-only storage, no runtime networking or third-party dependencies, and
  explicit backup exclusion.
- ActivityKit/WidgetKit projections that never become the source of truth.
- Existing release, privacy, accessibility, physical-device, and App Store
  checklists.

The main incompatibility is Pause. A single `TimeSessionRecord` represents one
continuous interval; Workout-style Pause/Resume needs a user-facing activity
that can contain multiple counted segments. Watch independence also introduces
a second durable writer and therefore requires an explicit synchronization and
conflict contract before UI implementation.

## 4. Workout workflow research and WellSpent mapping

| Workout behavior | WellSpent Watch behavior | Release scope |
| --- | --- | --- |
| Scroll or turn the Digital Crown through workout types | Scroll through active projects, ordered by recent use | Required |
| Tap Play or the center of a workout tile | Tap a project tile to start an open timer | Required |
| Immediate start feedback | Capture and persist `startAt` on selection; confirm the durable save with one haptic | Required |
| Configure an open, time, distance, or calorie goal | Open timer or duration goal; distance/calorie have no honest billable-time mapping | Required |
| Raise wrist to see live metrics | Show project, exact elapsed billable time, goal progress, and sync state | Required |
| Turn Digital Crown through workout views | Move through a small set of vertical metric pages | Required |
| Swipe right to the large-button control page | Show End, Pause/Resume, and New/Switch controls | Required |
| Pause and resume | Close/open counted segments inside the same timer run | Required |
| New workout | Atomically end the current project run and start the selected project | Required |
| End, confirm, review summary, then Done | Persist End first, then show duration, paused time, timestamps, note, and tags | Required |
| Workout history lives in Fitness on iPhone | Full session history, corrections, and reports remain on iPhone | Required |
| Smart Stack shows recent workout types | Smart Stack offers recent projects and active state | Phase 4 |
| Siri and Action button can start a favorite workout | App Intents and a watchOS control start a chosen/favorite project | Phase 4 |
| Sensor-based reminders, health metrics, Activity rings, music | No equivalent; these would misrepresent a billable timer or require unrelated APIs | Excluded |

### Workflow details

#### Project picker

- Launch directly into active projects; no dashboard before the primary task.
- Order projects by watch-local recent use, with the last active project first.
- A project tile shows emoji, name, color, a Play affordance, and a secondary
  goal/configuration affordance.
- Tapping the tile or its center starts an open timer. Tapping the secondary
  affordance offers Open and Time Goal.
- If the watch has never received a project catalog, show **Finish setup on
  iPhone**. Project creation, archive, and destructive editing remain on iPhone.
- If the iPhone is unreachable but a catalog is cached, the list remains fully
  usable and shows a small, nonblocking offline indicator.

#### Immediate start

- Selecting a project is the billing boundary; there is no pre-start delay.
- Capture one timestamp and time-zone identifier on selection, persist the run,
  first segment, and outbox command atomically, then present success and one
  confirmation haptic.
- A failed local save never shows a running timer.
- Starting when another run is active routes to Switch; it never creates a
  hidden second run.

#### Active experience

- The default page makes elapsed time the largest element, followed by project
  identity and goal progress when present.
- Additional Digital Crown pages show useful billable context: run elapsed and
  paused time, today's total, and this week's total. All values come from
  persisted boundaries and cached report inputs.
- A visible pending-sync marker appears only when there is unacknowledged work.
  It must not look like an error while normal background delivery is pending.
- Paused state freezes billable elapsed, changes color and label, and makes
  Resume the primary action.
- Always On and reduced-luminance rendering remove decorative detail, preserve
  status, and redact project identity according to the privacy preference.

#### Controls

- A right swipe reveals large End, Pause/Resume, and New controls in the same
  conceptual arrangement as Workout, with WellSpent styling and labels.
- End defaults to a confirmation because billable records are material. A
  setting may disable confirmation after device validation.
- New opens the recent-first project picker and performs one atomic boundary:
  the old run and segment end exactly when the new run and segment begin.
- watchOS reserves Digital Crown presses, so the Workout app's side-button plus
  Digital Crown Pause chord cannot be reproduced by a third-party app. Software
  controls and a user-configurable watchOS Control Widget are the supported
  equivalents.

#### End summary

- End persists locally before the summary appears.
- Summary shows project, total billable duration, paused duration, start/end,
  goal result, sync state, and segment count.
- Dictation, Scribble, and the system keyboard can add one optional note.
- Existing active tags are selectable. Saving note/tags updates the run and its
  counted segments atomically; dismissing the summary cannot lose the run.
- The iPhone groups paused segments as one run in history while reports continue
  to sum the exact underlying half-open segments.

## 5. Technical architecture

### 5.1 Targets

Add these generated targets and schemes to `project.yml`:

- `WellSpentWatch`: watchOS 26 SwiftUI companion app.
- `WellSpentWatchWidgets`: watchOS WidgetKit extension for complications, Smart
  Stack, and controls.
- `WellSpentWatchTests`: watchOS unit/integration tests.
- `WellSpentWatchUITests`: focused watchOS UI automation where supported.
- A cross-platform contract module containing Codable snapshots, timer command
  envelopes, identifiers, pure reconciliation rules, and presentation helpers.

Use bundle identifiers derived from the iOS app as Apple requires, for example:

- `com.drewreilly.wellspent.watchkitapp`
- `com.drewreilly.wellspent.watchkitapp.widgets`

The watch app and watch widget use a watch-local App Group. An App Group does
not synchronize data between devices; Watch Connectivity does that work.

### 5.2 Timer run model

Introduce SwiftData schema v3 with a `TimerRunRecord` and an optional
`timerRunID` on `TimeSessionRecord`.

`TimerRunRecord` contains:

- stable run UUID and optional workspace UUID;
- project UUID;
- `running`, `paused`, or `ended` state;
- start, end, and last-updated timestamps plus time-zone identifiers;
- optional duration goal;
- optional run note and tag assignments, using scalar IDs compatible with the
  repository's future CloudKit constraints;
- origin device identifier and last applied mutation identifier;
- created and updated timestamps.

Each counted `TimeSessionRecord` remains a half-open segment. A running run has
exactly one open segment; a paused run has none; an ended run has none.

The new invariant is:

1. At most one non-ended timer run exists after reconciliation.
2. A running run owns exactly one open timed segment.
3. A paused run owns no open segment.
4. Pause closes a segment at one boundary; Resume creates a segment at one
   boundary; Switch ends one run and starts another at the same boundary.
5. Reports count segments, never the run's wall-clock duration.
6. Duplicate command delivery is idempotent by mutation UUID.

Migration creates a one-segment ended run for each historical timed session and
a running run for the current active timed session. Manual sessions remain
standalone. Migration tests must cover every shipped schema fixture, notes,
tags, overlaps, and the active-session case.

### 5.3 Cross-device command journal

Every Watch mutation is a Codable envelope with:

- mutation UUID;
- stable origin-device UUID and monotonic origin sequence;
- captured timestamp and time-zone identifier;
- observed run/revision base;
- action and affected run/segment/project UUIDs;
- optional goal, note, and tag payload;
- schema/protocol version.

Transport strategy:

- `sendMessage` is only a fast path while the counterpart is reachable.
- `transferUserInfo` is the durable queued path for every mutation and ack.
- `updateApplicationContext` carries the replaceable latest project/timer
  snapshot, never the only copy of a command.
- The watch persists an outbox before transport and removes only entries the
  iPhone has acknowledged by mutation UUID.
- The iPhone persists an inbox/deduplication record before applying a mutation.
- The iPhone sends active projects, tags, timer state, relevant totals,
  tombstones, protocol version, and acknowledgement watermarks back to watch.
- Both sides tolerate duplicate, delayed, reordered, and background delivery.

### 5.4 Conflict policy

Automatically merge only causally safe cases:

- repeated delivery of the same mutation;
- Stop/End retries for the same run;
- phone acknowledgements or snapshots older than watch-local acknowledged
  state;
- one-sided offline sequences whose observed base still matches.

When phone and watch both mutate the same base while disconnected:

- preserve every counted segment and mutation;
- never invent or replace an exact boundary silently;
- select no destructive winner solely by wall-clock timestamp;
- place the merged state into review-required status;
- block further timer mutations on both devices;
- show **Review on iPhone** on watch;
- let the iPhone user keep, trim, merge, or end the conflicting runs using the
  existing overlap/reconciliation language;
- distribute the resolved snapshot and acknowledgement back to watch.

Clock skew is recorded for diagnosis but is never used to delete time. The
physical-device test matrix includes deliberate phone/watch clock and delivery
ordering variation.

### 5.5 Runtime and system surfaces

- Derive elapsed values from stored segment boundaries with SwiftUI timer/date
  formatting while visible. Do not maintain a background counter.
- Accept that a normal watchOS app eventually suspends after the wrist drops.
  The user controls Return to Clock behavior.
- Use the existing mirrored iPhone Live Activity when available, plus a
  watch-local WidgetKit complication/Smart Stack entry for offline watch-started
  runs.
- Reload WidgetKit timelines on state changes and build date-based entries so
  elapsed displays do not require per-second extension execution.
- Use App Intents for Start Favorite, Pause, Resume, Switch, and End. Intents
  must cross the same local command boundary as the app.
- Expose a watchOS 26 Control Widget that users may place in Control Center,
  Smart Stack, or on the Apple Watch Ultra Action button.

### 5.6 Privacy and security

- Store the minimum watch cache: active projects, active tags, timer run,
  recent totals, pending mutations, and acknowledgement data. Do not mirror
  full notes or report history unless a workflow needs them.
- Apply the strongest watchOS-compatible file protection and verify whether
  watch backups include the store before repeating the iPhone no-backup claim.
- Keep project names hidden by default in complications, widgets, controls,
  notification content, and reduced-luminance/Always On views.
- Include privacy manifests in the watch app and widget bundles and audit every
  required-reason API from the signed archive.
- Update source and binary privacy audits to recognize Watch Connectivity,
  UserNotifications, and watch bundles without weakening the no-server/no-
  analytics assertions.
- Reconfirm App Store Connect's data-collection answers from the final archive.

## 6. Delivery phases and Linear backlog

The frozen v1 evidence owners and mandatory gates are in
[WAT-05-ACCEPTANCE-MATRIX.md](WAT-05-ACCEPTANCE-MATRIX.md). Ongoing delivery is
tracked in [WAT-EXECUTION-STATUS.md](WAT-EXECUTION-STATUS.md).

Sizes use the team's existing scale: S = 2, M = 3, L = 5, XL = 8 points.

### Milestone A — Product contract and risk retirement

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-01` | Freeze the Workout-derived Watch UX contract and WellSpent differentiation | M | — |
| `WAT-02` | Define TimerRun, Pause/Resume, goal, summary, and migration semantics | L | WAT-01 |
| `WAT-03` | Define offline command, acknowledgement, and conflict semantics | L | WAT-02 |
| `WAT-04` | Prove Watch Connectivity foreground/background delivery on paired physical devices | L | WAT-03 |
| `WAT-05` | Freeze device, privacy, accessibility, and release acceptance matrices | M | WAT-01, WAT-04 |

Exit gate: accepted ADRs, a physical Watch Connectivity spike, and no unresolved
question that can change schema or command identity.

### Milestone B — Cross-device foundation

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-06` | Add generated watchOS app, widget, test targets, signing, and CI | L | WAT-05 |
| `WAT-07` | Extract cross-platform snapshots, command envelopes, and reconciliation helpers | L | WAT-03, WAT-06 |
| `WAT-08` | Add SwiftData v3 TimerRun migration and iPhone commands | XL | WAT-02, WAT-07 |
| `WAT-09` | Build the protected watch-local cache, inbox, and durable outbox | L | WAT-07 |
| `WAT-10` | Implement two-way Watch Connectivity snapshots, commands, and acknowledgements | XL | WAT-08, WAT-09 |
| `WAT-11` | Implement duplicate, stale, offline, and divergent-history reconciliation | XL | WAT-10 |

Exit gate: Start/Pause/Resume/Switch/End round-trip across paired devices,
survive app termination and offline delivery, and never duplicate or lose a
counted segment.

### Milestone C — Workout-style core Watch experience

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-12` | Build recent-first project picker and setup/offline/conflict states | L | WAT-10 |
| `WAT-13` | Build immediate persisted Watch timer Start and feedback | M | WAT-08, WAT-09, WAT-12 |
| `WAT-14` | Build live metric pages, Digital Crown navigation, and goal progress | L | WAT-13 |
| `WAT-15` | Build End, Pause/Resume, and New/Switch control surface | L | WAT-11, WAT-14 |
| `WAT-16` | Build persisted end summary with note, tags, and dictation | L | WAT-15 |
| `WAT-17` | Integrate paused, watch-origin, pending-sync, and conflict state on iPhone | L | WAT-11, WAT-16 |

Exit gate: the complete project-picker-to-summary journey works from watch
alone and produces the same exact report totals as the equivalent iPhone
commands.

### Milestone D — Complications, Smart Stack, controls, and alerts

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-18` | Add privacy-aware complication and Smart Stack recent/active widgets | L | WAT-14 |
| `WAT-19` | Add App Intents, watchOS Control Widget, Siri, and Action button setup | L | WAT-11, WAT-18 |
| `WAT-20` | Add optional duration-goal local alerts and permission flow | M | WAT-14 |
| `WAT-21` | Reconcile iPhone Live Activity and watch-origin timer projections | L | WAT-10, WAT-17, WAT-18 |

Exit gate: every system surface displays the same run, uses the same command
boundary, honors privacy settings, and recovers when delivery is delayed.

### Milestone E — Quality, privacy, and physical-device hardening

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-22` | Add watch domain, migration, transport, and UI automation to CI | XL | WAT-17, WAT-21 |
| `WAT-23` | Complete Watch accessibility, Always On, localization, and layout audit | L | WAT-16, WAT-18, WAT-20 |
| `WAT-24` | Run paired-device offline, restart, reinstall, upgrade, and conflict matrix | XL | WAT-22, WAT-23 |
| `WAT-25` | Audit battery, storage, diagnostics, privacy manifests, and network silence | L | WAT-24 |

Exit gate: automated gates pass, the physical-device matrix has no data-loss or
unresolved privacy failures, and battery behavior is acceptable for an
hours-long timestamp-based timer.

### Milestone F — TestFlight and App Store release

| Key | Issue | Size | Depends on |
| --- | --- | --- | --- |
| `WAT-26` | Validate the signed iOS-plus-watch archive, embedding, signing, and privacy report | L | WAT-25 |
| `WAT-27` | Produce Watch screenshots, icon, metadata, support copy, and review notes | L | WAT-23 |
| `WAT-28` | Run Watch TestFlight, submit the joint build, release manually, and smoke production | XL | WAT-26, WAT-27 |

Exit gate: Apple approves the iOS update with its embedded Watch app; the
App Store build passes Start/Pause/Resume/Switch/End and delayed-sync smoke on
a paired production device.

## 7. Test strategy

The operational authority for installation, environment boundaries, Simulator
automation, physical preflight, and evidence handling is
[WATCH-TESTING-GUIDE.md](WATCH-TESTING-GUIDE.md). In particular, independently
installing companion bundles is not a valid test baseline, and Simulator
results never satisfy a Watch Connectivity transport acceptance row.

### Deterministic unit tests

- TimerRun state transitions and one-non-ended-run invariant.
- Exact Pause/Resume/Switch boundaries and report exclusion of paused time.
- Duplicate, reordered, delayed, stale-base, and unsupported-protocol commands.
- Outbox persistence, acknowledgement, retry, and compaction.
- Migration from every v1/v2 fixture, including active, tagged, overlapping,
  long-running, and malformed multiple-active records.
- Goal elapsed/remaining calculations across time zones, DST, reboot, and long
  suspension.
- Privacy redaction and fixed, content-free diagnostic messages.

### Simulator and UI automation

- Empty setup, cached/offline, populated, active, paused, pending-sync,
  conflict, denied-notification, and failure fixtures.
- Immediate open/goal Start, rapid-tap, relaunch, offline, and save-failure behavior.
- Dynamic Type, VoiceOver labels/order, Reduce Motion, Increase Contrast, Bold
  Text, color independence, and 44-point primary controls.
- Small and large watch layouts: Series 6/SE-class 368 × 448, Series 11/10
  416 × 496, and Ultra-class 422 × 514 captures where available.
- iPhone regressions for Track, Live Activity, completion, history, reports,
  erase-all-data, upgrade, and privacy copy.

### Required paired physical-device matrix

Apple's Watch Connectivity sample explicitly requires physical iPhone and
Apple Watch testing. At minimum, verify:

1. Both apps foregrounded and reachable.
2. Watch foregrounded, iPhone app suspended and terminated.
3. iPhone foregrounded, watch app suspended.
4. Bluetooth/Wi-Fi/cellular changes and temporary unreachability.
5. Watch Start offline, phone launch later, and delayed acknowledgement.
6. Phone Start offline, watch launch later.
7. Independent conflicting starts, pauses, switches, and ends from the same
   base followed by explicit review.
8. Repeated delivery and receiver termination between persistence and ack.
9. Phone and watch reboot during running and paused states.
10. Watch app reinstall, phone app reinstall, unpair/repair, and a replacement
    watch; verify documented retention behavior before release.
11. Upgrade from the oldest supported App Store data store.
12. Multi-hour run for battery, elapsed accuracy, widget freshness, and goal
    alert behavior.

## 8. App Store release plan

### Packaging and signing

- Add watch bundle IDs, App Groups, capabilities, icons, and provisioning under
  the existing development team.
- Ensure the watch app and watch widget are embedded in the iOS archive and
  inherit the same marketing/build version.
- Build with the watchOS 26 SDK or later. Apple has required watchOS uploads to
  use the watchOS 26 SDK or later since April 28, 2026; the repository's current
  Xcode 26.6 toolchain meets that baseline.
- Inspect the signed archive for the iOS app, iOS widget, watch app, watch
  widget, privacy manifests, entitlements, frameworks, and code signatures.

### Metadata and assets

- Add Apple Watch functionality to the main description and App Review notes.
- Provide a distinct, compliant Watch app icon derived from WellSpent branding.
- Produce four fictitious-data Watch screenshots: recent projects, running
  metrics, controls, and summary.
- Use one accepted screenshot size consistently across localizations. The
  recommended primary set is 416 × 496 for Series 11/10; App Store Connect also
  accepts 422 × 514 for Ultra 3 and the documented legacy sizes.
- Update support, privacy, accessibility, and beta instructions for Watch,
  offline commands, optional goal alerts, and conflict review on iPhone.
- Re-evaluate the App Privacy answer. The intended answer remains no collected
  data because there is no server or third-party receipt, but the signed binary
  and current App Store definitions are authoritative.

### TestFlight and review

- Distribute the combined iOS/watchOS build to internal testers first, then a
  small external Watch cohort.
- Test installation, automatic Watch install, manual Watch install, update,
  and removal.
- Give App Review a no-login path: create projects on iPhone, open the Watch
  app, start a timer, pause/resume, switch, end, and inspect summary/history.
- Explain that HealthKit is intentionally absent, notification permission is
  optional and goal-triggered, and project names are hidden on glanceable
  surfaces by default.
- Submit the iOS version with its embedded Watch app using **Add for Review**,
  then **Submit for Review**. Use manual release.
- After approval, install from the public App Store and repeat the paired-device
  core and delayed-sync smoke tests.

Do not block the already-prepared iPhone release solely on Watch development.
If iPhone 0.1.0 is still unsubmitted when Watch reaches its archive gate, the
products may ship together; otherwise ship Watch in the next versioned iOS
update.

## 9. Primary risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Literal Workout imitation triggers copycat concerns | App Review rejection and weak identity | Reuse platform patterns, not Apple artwork/copy; use WellSpent brand and billable-time-specific value |
| Misusing workout/background APIs | Review rejection, health permission burden, battery waste | No HealthKit, Workout Processing, or extended runtime; use persisted timestamps, widgets, and local notifications |
| Two devices mutate offline | Duplicate or lost billable time | Durable command journal, explicit bases/acks, idempotency, preserve conflicts for review |
| Clock skew changes ordering | Incorrect boundaries | Record origin sequence and observed base; never delete based only on wall clock |
| Pause migration breaks reports | Incorrect invoices | TimerRun container plus exact counted segments; old fixtures and invariant tests gate release |
| Widget and Live Activity disagree | User stops the wrong run | All surfaces carry run UUID/revision and use the same command boundary |
| Project names leak on the wrist | Confidentiality breach | Default redaction on glanceable surfaces, Always On audit, minimal watch cache |
| Watch transport tests pass only in simulator | Production data loss | Physical Watch Connectivity spike before implementation and full paired-device gate before beta |
| Goals imply guaranteed background alerts | Missed expectation | Optional local notifications, clear denied-permission state, no guarantee based on process runtime |
| Watch scope delays iPhone launch | Lost release momentum | Release Watch as the next bundled update unless already at joint archive gate |

## 10. Definition of done

The Apple Watch release is complete only when:

- a user with cached projects can complete the full journey without a reachable
  iPhone;
- all watch commands persist before success and eventually reconcile exactly
  once on iPhone;
- paused time is excluded and Switch shares one exact boundary;
- divergent offline histories preserve all time and lead to an understandable
  iPhone review flow;
- complication, Smart Stack, controls, Live Activity, watch app, and iPhone app
  agree on run identity and state;
- privacy defaults and erase-all-data behavior cover both devices;
- automated, accessibility, migration, release, and paired physical-device
  gates pass;
- the signed archive and App Store metadata match actual capabilities;
- TestFlight acceptance is recorded and the App Store version is approved,
  manually released, and production-smoke-tested.

## 11. Apple references checked on September 1, 2026

- [Start a workout on Apple Watch](https://support.apple.com/guide/watch/start-a-workout-apdd16e8761a/watchos)
- [Adjust Apple Watch during a workout](https://support.apple.com/en-ie/guide/watch/apd72879df4d/watchos)
- [End and view a workout summary](https://support.apple.com/en-mide/guide/watch/apd95450de2a/watchos)
- [Create a Custom Workout](https://support.apple.com/en-euro/guide/watch/apd66fcd5c5c/watchos)
- [Workout Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/workouts)
- [Designing for watchOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos)
- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity)
- [Apple Watch Connectivity sample](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)
- [Watch frontmost app behavior](https://developer.apple.com/documentation/watchkit/taking-advantage-of-frontmost-app-state)
- [Extended runtime session limits](https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions)
- [WidgetKit and Watch complications](https://developer.apple.com/documentation/widgetkit/)
- [App Review guideline 4.1](https://developer.apple.com/app-store/review/guidelines/)
- [watchOS 26 compatibility](https://support.apple.com/en-ie/guide/watch/apd2054d0d5b/watchos)
- [Current App Store SDK requirements](https://developer.apple.com/app-store/submitting/)
- [Add watchOS app information](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-watchos-app-information)
- [Apple Watch screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app)
