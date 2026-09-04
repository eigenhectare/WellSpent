# WAT-05 — Watch acceptance contract

Frozen for the paired Watch v1 on September 2, 2026. This defines gates; it does
not claim that the gates have passed. WAT-05 is complete when this contract is
reviewed against the plan and existing release documents. Execution belongs to
WAT-18–28 and requires evidence for the exact candidate.

## Product and evidence rules

- iPhone is required for setup, catalog management, reports, and conflict review.
  The Watch can persist Start/Pause/Resume/Switch/End offline after setup.
- Start persists immediately. There is no countdown, countdown screenshot, or
  countdown accessibility case.
- A normal timestamp-based timer must not claim continuous background execution.
- Simulator/fake transport can prove reducers, persistence, views, and injected
  delivery failures. It cannot certify physical Watch Connectivity delivery,
  battery, haptics, wrist-down/lock behavior, or installation from TestFlight.
- Every row below is mandatory for v1 unless explicitly marked conditional.
  Missing hardware or credentials means **Not run / Blocked**, never Pass.
- Existing iPhone-only approvals and manual-audit deferrals do not satisfy or
  waive Watch gates. The user-accepted WAT-04 spike closeout is historical; the
  production candidate still needs WAT-24 paired transport evidence.
- Product code, test fixtures, and test runner are separately identified. Never
  include client names, notes, personal notifications, device/account identifiers,
  or raw transport payloads in committed evidence or Linear comments.
- Do not delete apps, erase personal data, unpair, restore, or replace a user's
  device without explicit approval. Prepare such cases using disposable data.

## Device and display coverage

Deployment remains iOS 26 / watchOS 26. Apple lists Series 6 and later, SE 2 and
later, and Ultra models for watchOS 26; a compatible iPhone running iOS 26 is
required. Use iPhone 11 or later as the baseline paired-phone requirement;
record the actual supported phone/OS pairing for each test. See
[Apple watchOS compatibility](https://www.apple.com/de/os/watchos/) and
[Apple pairing compatibility](https://support.apple.com/en-us/118490).

| Class | Required coverage | Evidence owner |
| --- | --- | --- |
| Small / minimum | Series 6 40 mm and SE 2 40 mm equivalent display; oldest supported watchOS store upgrade | WAT-23 simulator; WAT-24 minimum-class physical device when available (otherwise explicit coverage gap) |
| Standard | Series 10/11 42 and 46 mm; default and largest text | WAT-23 simulator; WAT-24 current physical pair |
| Ultra | Ultra 49 mm display, long labels, all control layouts | WAT-23 simulator; WAT-19/24 Action button on capable physical hardware or explicitly unverified capability |
| iPhone | Small iOS 26 layout plus Dynamic Island current iPhone | WAT-21/22 simulator; WAT-24 physical pair |
| OS | Minimum deployment SDK/runtime where installed, current supported stable runtime, upgrade from oldest supported store | WAT-22 build/fixtures; WAT-24 actual OS versions |

Require at least one real current pair before joint release. Minimum-class and
Ultra hardware gaps must remain visible in the release decision; do not claim
coverage of unavailable devices. Simulator display coverage remains mandatory.

## Acceptance matrix

All rows initially **Not run for joint release candidate**. Per-issue earlier
tests are useful development evidence, not an automatic release-candidate pass.

| Gate | Required result | Evidence / responsible WAT |
| --- | --- | --- |
| CORE-01 | Picker → immediate Start → Pause → Resume → Switch → End → saved summary; paused time excluded, no gaps/duplicates from switching | Deterministic tests + simulator WAT-22; physical WAT-24 |
| CORE-02 | Exact source segments explain all iPhone Day/Week/Project totals; Watch-origin/grouped history and annotations survive relaunch | WAT-22 tests; WAT-24 pair |
| CORE-03 | Failed saves do not report success; retry is idempotent; cancellation of note/dictation/keyboard preserves saved time | WAT-22 fault tests; WAT-23/24 UI and system input |
| SYNC-01 | Foreground/background/suspended/terminated transport eventually converges; no fake reachability success | WAT-24 physical, debugger detached as well as attached |
| SYNC-02 | Lost/duplicate/reordered commands, acks, receipts, and older snapshots neither lose time nor overwrite newer local work | WAT-22 injected tests; WAT-24 repeated delivery trials |
| SYNC-03 | Offline Start/Pause/Resume/Switch/End and note/tag saves persist across process death and later converge exactly once | WAT-22 persistence tests; WAT-24 offline pair |
| SYNC-04 | Same-base divergent histories freeze safely; each explicit iPhone resolution preserves selected source intervals | WAT-22 fixtures; WAT-24 pair |
| SYNC-05 | Clock skew, DST, time-zone changes, and delivery reordering never silently discard intervals | WAT-22 clock/time-zone fixtures; WAT-24 device clock scenarios |
| LIFE-01 | Correct dependent-companion install via Xcode unified scheme and automatic/manual TestFlight Watch installation | WAT-24/26/28 signed pair; follow WATCH-TESTING-GUIDE.md |
| LIFE-02 | Restart/reboot while running and paused preserves original boundaries and pending mutations | WAT-22 process harness; WAT-24 pair |
| LIFE-03 | Upgrade oldest iPhone and Watch stores without deletion preserves IDs, notes, tags, exact timestamps and totals | WAT-22 migration fixtures; WAT-26 signed upgrade |
| LIFE-04 | Reinstall, remove/re-add companion, unpair/re-pair, and replacement Watch retention are recorded accurately; no resurrection after erase | WAT-24/25 approved disposable-device cases |
| SURF-01 | Supported complications and Smart Stack families show correct idle/recent/running/paused/pending/conflict state; taps resolve current identity | WAT-18/22 model and render tests; WAT-24 device |
| SURF-02 | App, Siri, shortcuts, controls and user-assigned Action button share one durable command boundary; stale/duplicate invocations are safe | WAT-19/22 fixtures; WAT-24 supported hardware/context |
| SURF-03 | iPhone Live Activity reflects canonical run/revision, disabled/failure states recover, stale End cannot affect a newer run | WAT-21/22 tests; WAT-24 Lock Screen and Dynamic Island |
| ALERT-01 | Grant/deny/not-determined handled without repeated prompts; permission denial does not block tracking | WAT-20/22 injected permission tests; WAT-24 actual permission dialogs |
| ALERT-02 | Alert deadline counts only worked segments; pause/end/switch/erase cancel obsolete alerts; restart/overtime/offline handled | WAT-20/22 scheduler tests; WAT-24 foreground/background long goal |
| ACCESS-01 | Explicit VoiceOver labels/value/order/hints; every core/error action operable without color or animation; focus returns correctly | WAT-23 automated properties and manual VoiceOver |
| ACCESS-02 | Default and maximum supported text, Bold Text, contrast, Reduce Motion: no clipping/overlap/unreachable controls | WAT-23 small/standard/Ultra captures; WAT-22 regressions |
| ACCESS-03 | Primary targets 44 pt; any system-constrained exception is documented; haptic feedback has visible equivalent | WAT-23 layout checks; WAT-24 physical haptics |
| ACCESS-04 | English-US launch, localization-ready strings and pseudo/expanded labels; canceled dictation does not corrupt summary | WAT-23 tests/captures and system-input check |
| PRIV-01 | Names hidden by default in gallery/placeholders, complications, widgets, Siri/control dialogs, alerts and Live Activities; opt-in consistent | WAT-18–23 tests/captures; WAT-24 locked device |
| PRIV-02 | Always On/reduced luminance/lock and notification-preview settings suppress sensitive project identity even after opt-in | WAT-23 simulated redaction; WAT-24 actual wrist-down/lock |
| PRIV-03 | Device-appropriate file protection, backup/restore behavior, erase, stale-receipt fencing and no resurrection are verified | WAT-22 store tests; WAT-25 physical and archive |
| PRIV-04 | No HealthKit, workout/extended runtime, CloudKit, server, telemetry, analytics or advertising runtime; fixed content-free diagnostics only | WAT-25 source, compiled dependency and runtime network audits |
| PRIV-05 | Every embedded manifest, required-reason API, entitlement and App Store privacy answer matches signed candidate | WAT-25/26 archive report; WAT-28 Connect review |
| ENERGY-01 | Multi-hour running/paused/offline timer has no per-second background task, bounded store/outbox and state-driven widget reloads | WAT-22 deterministic growth/reload checks; WAT-25 Instruments/energy and actual device battery |
| DIST-01 | Correct embedded iPhone/Watch apps and extensions, matching versions/builds, signing/architectures/deployment targets, no fixtures/spikes | WAT-26 exact signed archive inspection and validation |
| DIST-02 | Release candidate screenshots/icons/copy are accurate, fictitious, consistent size; install/review instructions work uncoached | WAT-27 artifact proof; WAT-28 reviewer/beta |
| DIST-03 | Internal then external TestFlight covers install/update/core/offline cases; no unresolved high-risk defect | WAT-28 actual beta evidence, not scripted substitutes |
| DIST-04 | Approved exact build released manually after authorization; App Store-installed pair passes core + delayed-sync smoke | WAT-28 Apple approval, release authorization and production evidence |

For ENERGY-01 measure a matched 4-hour baseline and app run on the same device,
OS, battery health, brightness/AOD and radio settings; record charge percentages,
thermal conditions, CPU/wakeups, reload count and store sizes. Repeat anomalous
runs. Proposed engineering acceptance budget: <=5 additional battery percentage
points over baseline in 4 hours, no sustained background execution, no unbounded
growth after acknowledged work is compacted. This is a project budget, not an
Apple guarantee; any exception needs an explicit recorded release decision.

## Claims ledger

| Claim | State until evidence | Required proof |
| --- | --- | --- |
| No app data collected | Provisional for combined Watch release | PRIV-04/05 signed binary, runtime audit, Connect answers |
| Activity data excluded from backups | Provisional on Watch; source flags alone are insufficient | PRIV-03 physical backup/restore and archive |
| Erase all data | Scoped to local device plus acknowledged sync behavior, not remote-wipe guarantee | LIFE-04 / PRIV-03; accurate per-device support copy |
| Offline tracking | Durable local operation, not guaranteed immediate delivery | SYNC-01–05 |
| Goal reminder | Optional, permission-dependent, best-effort local notification | ALERT-01/02; no continuous-runtime promise |
| Action button | User-configured on supported hardware, never exclusively owned by app | SURF-02 |
| Accessibility | Claim only audited capabilities; no blanket inherited iPhone certification | ACCESS-01–04 |

## Store and release inputs rechecked September 2, 2026

Apple currently requires Xcode 26 or later and the relevant 26 SDK for uploads
(effective April 28, 2026). Recheck on upload day:
[Apple SDK requirements](https://developer.apple.com/news/upcoming-requirements/).

Use five actual candidate screenshots: projects, goal setup, active metrics,
controls, summary. The chosen Watch size is 416 × 496 (Series 10/11); Apple also
accepts 422 × 514, 410 × 502, 396 × 484, 368 × 448, and 312 × 390. Use one size
consistently across all localizations. These are upload sizes, not all supported
layout sizes. Recheck [Apple screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/).

Signed archive, privacy report, TestFlight, review, and release gates apply to
the joint candidate. Do not reopen or block an independent iPhone-only release
on Watch work that is not embedded in that candidate.

## Evidence record and closeout

For each execution record gate/scenario, Pass/Fail/Not run/Blocked, exact source
revision plus dirty-diff fingerprint if applicable, app version/build, Xcode/SDK,
device class/OS (not serial number), setup, steps, expected/observed result,
timestamp, sanitized artifact paths and unresolved defect. Store automated logs
under ignored `.derivedData/` and durable conclusions in issue-specific docs.

WAT issues move to In Progress during implementation, In Review when awaiting a
required hardware or external gate, and Done only when their full acceptance
criteria are supported. A script, checklist, unsigned build, or screenshot is
not evidence that its physical/distribution test ran.

Cross-checked against `ACCESSIBILITY.md`, `PRIVACY.md`, `BETA-TESTING.md`,
`RELEASE-CANDIDATE-VALIDATION.md`, `APP-STORE-RELEASE.md`, `APPLE-WATCH-PLAN.md`,
and `WATCH-TESTING-GUIDE.md`. Historical iPhone records remain unchanged. Their
no-notifications/no-device-sync/no-backup wording is not Watch release copy.

Later enhancements, not v1 gates: additional languages, app preview video,
independent/family-setup Watch support, and additional nonessential widget
families. Missing evidence for a shipped v1 capability is not an enhancement.
