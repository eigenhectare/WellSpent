# Core app experience — UI-01 through UI-08

## Implemented issues

This document records the shared implementation for `IDK-304` through
`IDK-311` (`UI-01` through `UI-08`). Views are projections of
`BillableHoursAppModel`; all mutations still cross the existing project,
timer, or session command service. No view mutates SwiftData records directly.

## First launch and privacy

- First launch explains the one-active-timer rule, timestamp-derived elapsed
  time, and the privacy-safe Lock Screen default on one scrollable screen.
- A user may create the first project in onboarding or dismiss to the Track
  empty state and create it there.
- The flow requests no Calendar, notification, or iCloud permission.
- `completedOnboarding` and `showProjectNamesOnLockScreen` are separate
  preferences. Project-name visibility defaults to `false`, requires an
  explicit toggle, and persists after relaunch.

## Track, Start, Switch, and Stop

- Track lists active projects only. Color is supplemented by visible and
  accessible `Active`, `Start`, and `Switch` text.
- Tapping a project invokes `TimerCommandService`. UI state refreshes only
  after the command returns from its persistence save.
- The active card derives elapsed time each refresh from the stored `startAt`.
  It does not maintain an in-memory counter.
- Stop captures and persists the result through the idempotent domain command
  before the completion route is assigned. A failure leaves the timer active.
- A successful switch completes and creates records at one command boundary.
  The previous-session note sheet appears only after the new active session is
  stored, and saving or skipping that note never affects the new timer.

## Completion and correction

- Completion displays the final project, exact timestamps, exact-to-the-second
  duration, a multi-select tag picker, and an optional long-form note editor.
- Skipping, swiping away, terminating the app, or abandoning note entry cannot
  remove the already-saved session.
- `billablehours://completion/<session UUID>` resolves a persisted completed
  session and opens the same completion screen.
- Project management supports create, edit, archive, and restore. A project can
  have an optional emoji plus color identity. The command boundary blocks
  archiving the active project; edits preserve UUID identity and therefore
  historical session references.
- Settings seeds meeting, internal discussion, collaboration, and solo work as
  tag choices. Users may add choices or archive any default/custom choice;
  historical assignments keep their saved name and remain visible.
- The manual editor supports active and archived projects, exact timestamps,
  optional notes, validation, and cancel. It previews overlaps before save,
  offers an explicit nonblocking `Save Anyway` action, and repeats detection in
  the command itself.
- History and session review show active and overlap markers, explain that both
  overlapping records count, and require confirmation before deletion.

## Accessibility and automation

Primary controls use descriptive labels, 44-point minimum targets where custom
controls are used, non-color state cues, monospaced/scalable durations, and
scrollable forms at accessibility Dynamic Type sizes. The UI harness supports
fresh, populated, active, archived, overlap, report, and failure fixtures only
in Debug builds.

The UI suite covers onboarding and dismissal, first-project creation at the
largest accessibility size, empty/populated/active/archived/failure states,
background/foreground, persist-first Stop, app termination, completion deep
linking, long notes, switch save/skip/failure, duplicate warnings, rename
identity, archive safeguards, restore, manual validation/cancel, overlap save,
archived historical selection, confirmed deletion, project emoji, multi-tag
completion, tag customization, and disabled-Live-Activity settings recovery.

## Scope boundary

The screens now project successful timer commands into ActivityKit through the
production lifecycle documented in `LIVE-ACTIVITY-LIFECYCLE.md`. The database
remains authoritative and projection failures stay recoverable. Calendar,
iCloud, export, timer notifications, and billing rounding remain absent.
