# REL-02 beta package

This package defines the uncoached beta round for Billable Hours. The beta is
successful only when representative professionals can capture, correct, and
review their time without developer guidance and no release-blocking defects
remain.

## Candidate identity

- Product: Billable Hours for iPhone
- Version: `0.1.0`
- Build: `1`
- Supported OS: current iOS major (`26.x`)
- Distribution: TestFlight build produced from `main`
- Data model: SwiftData v2 with migration from the oldest v1 store
- Network behavior: none; the candidate stores work data locally

Record the TestFlight build number and source commit in Linear before inviting
external testers. Never reuse a build number for a different binary.

## Tester cohort

Use at least two people whose real work resembles the product's target use,
including two different professions when possible (for example, a consultant
and a lawyer). The developer may explain how to install TestFlight, but must
not explain where controls are or coach the scenarios below.

Testers must use fictitious project names and notes during the structured
round. Feedback must not contain client names, matter names, screenshots with
confidential content, or copied work notes.

## Installation paths

### Clean install

1. Delete any prior Billable Hours beta and confirm that losing its local data
   is acceptable.
2. Install the assigned TestFlight build.
3. Launch the app and complete onboarding without assistance.
4. Create one fictitious project with a color and optional emoji.
5. Confirm the project appears on Track and no sample work is present.

Expected result: onboarding explains the timestamp model and Lock Screen
privacy; the first project is immediately usable.

### Upgrade with existing data

1. On the prior build, create two projects and at least three completed
   sessions. Leave one project archived. Record the visible Day and Week totals.
2. Install the candidate over the existing app. Do not delete the app first.
3. Launch the candidate and confirm every project and session remains present,
   the archived project is still archived, and the recorded totals are exact.
4. Add an emoji to one project and tags to one completed session.
5. Force-quit and relaunch; confirm both additions remain and older sessions
   have not acquired fabricated tags.

Expected result: migration preserves all existing timestamps, notes, project
state, and totals while making emoji and tags available.

## Structured uncoached scenarios

For every scenario, record `Pass`, `Fail`, or `Blocked`, the elapsed time, and
whether the tester requested help.

### BETA-01 — Start and recover

1. Start a timer for a project.
2. Put the app in the background and use another app briefly.
3. Return to Billable Hours.

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

Expected: the generic `Billable timer` label is the default; the project name
appears only after explicit opt-in; Stop remains available.

### BETA-08 — Failure and recovery comprehension

1. Force-quit the app while a timer is active, then reopen it.
2. If a Live Activity recovery message appears, follow its visible action.
3. Open a deliberately empty report range and an empty project/session state.

Expected: persisted time remains authoritative, recovery copy never reports a
false save, and every expected empty or recovery state offers a clear next
action.

## Privacy-safe feedback form

Copy this block for each finding:

```text
Tester code:
Profession category:
Build number:
iPhone model and iOS version:
Scenario ID:
Outcome: Pass / Fail / Blocked
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
- No open P0 or P1 beta finding remains.
- No workflow loses a stopped session, creates two authoritative active timers,
  or produces an unexplained report total.
- All fixes are rechecked against the same scenario on a newer build.
