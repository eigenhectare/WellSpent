# REL-02 paired iPhone + Apple Watch beta package

This package defines the uncoached beta round for WellSpent. The beta is
successful only when representative professionals can capture, correct, and
review their time without developer guidance and no release-blocking defects
remain.

## Candidate identity

- Product: WellSpent for iPhone with embedded Apple Watch companion
- Version: `0.1.0`
- Build: select and record the next uploaded build; it must be greater than the
  current engineering build `2` and must never be reused for different bytes
- Supported OS: iOS 26.x and watchOS 26.x
- Distribution: TestFlight build produced from `main`
- Data model: iPhone SwiftData v6 with sequential migration from the oldest v1
  store, plus the separate bounded Watch-local store and command journal
- Network behavior: no developer server; the paired apps exchange local ledger
  state through Apple's Watch Connectivity

Record the TestFlight build number, source commit, archive/export hashes and
processed-build identity in Linear before inviting any testers. Never reuse a
build number for a different binary.

## Tester cohort

Begin with an internal cohort, then use at least two external participants whose
real work resembles the product's target use, including two different professions
when possible. Cover a standard-size Watch and an Ultra-class Watch; record any
missing minimum-device coverage rather than inventing it. The developer may
explain how to install TestFlight, but must not explain where controls are or
coach the scenarios below.

Testers must use fictitious project names and notes during the structured
round. Feedback must not contain client names, matter names, screenshots with
confidential content, or copied work notes.

## Installation paths

### Clean install

1. Confirm that deleting any prior beta and its separate Watch cache is
   explicitly authorized and that losing local data is acceptable.
2. Install the assigned TestFlight build on iPhone, then install its embedded
   Watch companion through the normal automatic or manual Watch flow.
3. Record both displayed versions/builds and confirm the phone recognizes its
   counterpart before classifying any later synchronization result.
4. Launch the phone app and complete onboarding without assistance.
5. Create one fictitious project with a color and optional emoji, then open the
   Watch app and wait for that project to arrive.
6. Confirm no sample work is present on either device.

Expected result: onboarding explains the timestamp model and glanceable-surface
privacy; the first project is immediately usable from both devices.

### Upgrade with existing data

1. On the prior build, create two projects and at least three completed
   sessions. Leave one project archived. Record the visible Day and Week totals.
2. Install the paired candidate over the existing iPhone-only app. Do not delete
   the app first. Install the newly embedded Watch companion afterward.
3. Launch both apps and confirm every project and session remains present,
   the archived project is still archived, and the recorded totals are exact.
4. Add an emoji to one project and tags to one completed session.
5. Force-quit and relaunch; confirm both additions remain and older sessions
   have not acquired fabricated tags.

Expected result: migration preserves all existing timestamps, notes, project
state, and totals while making the Watch companion available without creating
a second active timer or fabricating synchronized history.

## Structured uncoached scenarios

For every scenario, record `Pass`, `Fail`, `Not run`, or `Inconclusive`, the
elapsed time, and whether the tester requested help. A missing installation or
counterpart is a preparation blocker, not a transport failure.

### BETA-01 — Start and recover

1. Start a timer for a project.
2. Put the app in the background and use another app briefly.
3. Return to WellSpent.

Expected: exactly one timer remains active with its original start time. No
duplicate session or restart occurs.

### BETA-02 — Switch projects

1. While timing Project A, tap Project B.
2. Add a note and one or more tags to the completed Project A segment.
3. Return to Track.

Expected: Project B starts at the exact boundary where Project A ends and keeps
running while the previous segment is annotated.

### BETA-03 — Stop and annotate

1. Stop the active timer.
2. Add a note and two tags, then save.
3. Open Session History and select the new session.

Expected: Stop is terminal, the session is already saved before note entry,
and its project, exact timestamps, note, and tags survive relaunch.

### BETA-04 — Correct history

1. Edit a completed session's start, end, project, note, and tags.
2. Save an intentional overlap after reading the warning.
3. Add a separate manual session.
4. Begin deleting a session, cancel once, then confirm deletion.

Expected: invalid ranges are blocked, overlaps are advisory and marked, cancel
preserves the session, and confirmed deletion removes only the selected row.

### BETA-05 — Review Day, Week, and Project totals

1. Open each report scope.
2. Compare totals with the source sessions created above.
3. Open a total and navigate through its contributing segments to a source
   session.

Expected: totals match exact source segments; overlaps remain fully counted and
visibly identified; every aggregate can be explained.

### BETA-06 — Manage projects and tags

1. Create, rename, recolor, and add or change a project emoji.
2. Archive an inactive project and restore it.
3. Add a custom tag and remove one default tag in Settings.
4. Review an older session that used the removed tag.

Expected: active projects cannot be archived, historical work remains visible
after project changes, and removing a tag choice does not rewrite history.

### BETA-07 — Privacy and Lock Screen behavior

1. Start a timer with Lock Screen project names disabled.
2. Inspect the Lock Screen and Dynamic Island.
3. Opt in to project-name visibility in Settings and inspect again.

Expected: the generic `WellSpent timer` label is the default; the project name
appears only after explicit opt-in; Stop remains available.

### BETA-08 — Failure and recovery comprehension

1. Force-quit the app while a timer is active, then reopen it.
2. If a Live Activity recovery message appears, follow its visible action.
3. Open a deliberately empty report range and an empty project/session state.

Expected: persisted time remains authoritative, recovery copy never reports a
false save, and every expected empty or recovery state offers a clear next
action.

### BETA-W01 — Immediate Watch start and paired history

1. With both apps available, start a fictitious project from the Watch play
   button and verify Running appears immediately with no countdown.
2. Pause, wait, resume, choose New to switch projects, then End with confirmation.
3. Add a fictitious note and tag on the saved summary.
4. On iPhone, inspect the resulting run and its source segments.

Expected: each Watch action is locally saved before success, the pending state
clears only after acknowledgement, paused time is excluded, switching shares one
boundary, and exactly one ended run reaches iPhone history.

### BETA-W02 — Offline Watch work and delayed acknowledgement

1. Establish a synchronized baseline, then make the iPhone unavailable without
   deleting either app.
2. Start, Pause, Resume, Switch and End from cached Watch projects.
3. Reconnect the pair and open the apps in the assigned order.

Expected: offline work stays visibly pending and usable, then converges exactly
once without losing or duplicating a counted interval. Record observed delivery
time; do not claim a guaranteed background deadline.

### BETA-W03 — Divergent edits and conflict review

1. Disconnect after a common synchronized state.
2. Change the same timer independently on iPhone and Watch.
3. Reconnect, open conflict review on iPhone, cancel once, then exercise the
   assigned resolution on a fresh conflict.

Expected: both branches remain inspectable, cancellation preserves them, unsafe
continuation is blocked, and the explicit resolution matches the resulting
history and totals on both devices.

### BETA-W04 — Goals and system surfaces

1. Start one open timer and one duration goal from Watch Options.
2. Test Goal alerts disabled, denied and enabled as assigned; include a pause.
3. Inspect the complication/Smart Stack, Watch control, Live Activity and goal
   notification with project names private, then after explicit opt-in.

Expected: alerts use counted time and never end a run; timer identity/revision is
consistent across surfaces; hidden names do not appear in the private state.

### BETA-W05 — Accessibility and interruption recovery

Use the assigned VoiceOver, large-text, contrast, motion, haptic-off, Always On
or dictation condition. Traverse or perform the complete assigned flow, including
cancellation and wrist-down/wake where applicable.

Expected: every essential state/action is understandable without color,
animation or haptic; focus and content remain reachable; private drafts do not
leak or disappear because the display dimmed.

### BETA-W06 — Authorized retention and long-run case

Execute only the assigned, explicitly authorized WAT-24 long-duration,
restart, reinstall, unpair/repair, replacement or oldest-store upgrade row. Use
the dedicated fictitious dataset and recovery inventory; do not improvise a
destructive variant.

Expected: observed retention matches support copy, no counted interval is lost
or duplicated, and the accepted battery/storage budget is met. Missing hardware,
old builds or approval remains Not run.

## Privacy-safe feedback form

Copy this block for each finding:

```text
Tester code:
Profession category:
Build number:
iPhone model and iOS version:
Watch model and watchOS version:
Phone and Watch install method/version match:
Scenario ID:
Outcome: Pass / Fail / Not run / Inconclusive
Expected:
Observed (use fictitious project names only):
Reproduction steps:
Reproduces after relaunch: Yes / No / Not tried
Data missing, duplicated, or incorrect: Yes / No
Screenshot attached and checked for confidential content: Yes / No / None
Assistance requested: Yes / No
Additional friction or suggestion:
```

## Triage rules

- `P0 — Stop beta`: data loss, confidential content exposure, an unrecoverable
  store, or a workflow that creates multiple authoritative active timers.
- `P1 — Fix before release`: a core Start/Switch/Stop/correction/reporting path
  is blocked, timestamps or totals are wrong, or an ordinary restart loses work.
- `P2 — Prioritize from evidence`: the workflow completes but causes material
  confusion, repeated failed attempts, or a misleading state.
- `P3 — Follow-up`: cosmetic defects and ideas that do not prevent trustworthy
  time capture or review.

Every P0 and P1 finding gets its own Linear issue with the beta build, scenario
ID, sanitized reproduction steps, and an explicit verification result. Avoid
copying raw tester notes into Linear.

## REL-02 exit gate

- At least two representative professionals complete BETA-01 through BETA-06
  without coaching.
- BETA-07 and BETA-08 pass on at least one current-iOS physical device.
- Internal and then external paired-device testers complete BETA-W01 through
  BETA-W05 on the assigned standard/Ultra coverage; every authorized BETA-W06
  prerequisite row has an explicit result.
- WAT-24's physical matrix has no unresolved data-loss/privacy result and WAT-25
  meets its accepted resource budget for this exact processed build.
- No open P0 or P1 beta finding remains.
- No workflow loses a stopped session, duplicates an interval, leaks a private
  identity, creates two authoritative active timers, or produces an unexplained
  report total.
- All fixes are rechecked against the same scenario on a newer build, and the
  accepted evidence identifies the exact archive/processed TestFlight build.
