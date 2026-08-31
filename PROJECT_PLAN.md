# Billable Hours Tracker — Product and Engineering Plan

## 1. Plan status

This document turns `idea.md` and the follow-up product decisions into an implementation-ready plan. It is intended to be the source for a Linear project, milestones, issues, dependencies, and release gates.

Status: ready for issue creation and implementation sequencing.

## 2. Product goal

Build an individual-first native iPhone app that lets a professional tap a project when work begins, capture exact billable time without reconstructing it later, and finish a day or week with totals that are easy to explain and enter into a timesheet.

The core promise is:

> Tap a project when work starts; finish the week with a timesheet you can trust.

## 3. Confirmed product decisions

### Initial release

- Native iPhone app; no Android, web, iPad-specific, macOS, Watch, or team client.
- Local persistence is authoritative.
- No export in the initial release.
- One active timer at a time.
- Starting or switching projects is one obvious tap.
- A switch ends the old session and starts the new session at the same timestamp.
- Stop is terminal. There is no pause/resume state in the initial release.
- Stop is available inside the app and through an interactive Lock Screen Live Activity.
- A successful stop saves the session before presenting the optional-note completion screen.
- A session spanning midnight or a calendar-week boundary remains one stored session. Reporting divides its duration across the relevant day and week buckets.
- Manual sessions may overlap. Each session counts fully toward totals, so a reported day can exceed 24 hours. Overlaps are clearly flagged.
- Sessions use exact source timestamps. There is no billing-increment rounding.
- Projects may be created, renamed, archived, and restored.
- Sessions may be manually added, edited, and deleted.
- Auditing in the initial release consists of stable identifiers plus creation and update timestamps.

### Later milestones

- Product milestone 2: manual Apple Calendar publication and automatic synchronization of published events after app-side edits or deletions.
- Product milestone 3: private iCloud sync across one person's devices.
- Product milestone 4: complete session revision history.

### Explicitly deferred

- CSV, PDF, and other export formats.
- Automatic Calendar publication.
- Accounts, teams, managers, approvals, billing rates, invoicing, budgets, and profitability.
- Configurable billing increments and rounded totals.
- Notifications or automatic cutoffs for implausibly long timers, pending evidence that users need them.

## 4. Success measures

The initial release is successful when all of the following are true:

1. A user can start or switch to a project with one tap from the main screen.
2. Timer duration remains correct after backgrounding, screen lock, app termination, and device restart.
3. Every supported command path leaves at most one active timed session.
4. Lock Screen Stop records an end timestamp without requiring the app to have remained running.
5. A stopped session is never lost if the user skips or abandons note entry.
6. Day, week, and project totals equal the exact sum of the visible contributing session segments.
7. Cross-midnight, cross-week, daylight-saving, locale, and overlapping-session behavior is explainable and tested.
8. A user can repair a missed or incorrect entry without damaging other sessions.
9. Project names and work notes never appear in application logs, analytics payloads, or crash breadcrumbs.

Suggested post-launch product signals, if privacy-preserving analytics are later approved:

- Percentage of created timers successfully stopped.
- Percentage of sessions with notes.
- Frequency of manual corrections.
- Use of Lock Screen Stop versus in-app Stop.
- Report-view use by day, week, and project.
- Crash-free sessions and persistence failures, without recording client content.

## 5. Release scope

### Product milestone 1 — Trustworthy local tracker

Includes:

- Project management.
- Exact start, switch, and stop behavior.
- Active-timer recovery.
- Lock Screen and Dynamic Island Live Activity with Stop.
- Optional notes after stop and switch.
- Manual session creation, editing, and deletion.
- Day, week, and project reports.
- Cross-boundary allocation and overlap indicators.
- Accessibility, privacy, reliability, and App Store release work.

Does not include export, Calendar, iCloud, or revision history.

### Product milestone 2 — Apple Calendar mirror

Includes:

- Explicit Calendar permission flow.
- A dedicated `Billable Time` calendar.
- Manual publication of completed sessions.
- Stored linkage between a session and its EventKit event.
- Automatic update of a linked event after an app-side session or project edit.
- Automatic deletion of a linked event after an app-side session deletion.
- Visible publication and sync state.
- Recovery behavior for revoked permission, deleted calendars, missing events, and EventKit failures.

### Product milestone 3 — Private iCloud sync

Includes:

- Private CloudKit-backed synchronization through SwiftData.
- Offline-first behavior.
- Conflict policies for projects, sessions, and the active-timer invariant.
- Multi-device migration and reconciliation testing.
- Clear signed-out, unavailable, and error states.

### Product milestone 4 — Complete revision history

Includes:

- Append-only revisions for session creation, editing, project reassignment, note changes, and deletion.
- A session history view showing what changed and when.
- Restore/copy-from-revision behavior, if validated as useful.
- Revision behavior that remains compatible with iCloud sync.

## 6. Experience architecture

Use a three-tab structure:

1. **Track** — active timer, active projects, one-tap switching, project management.
2. **Reports** — Day, Week, and Project views with drill-down.
3. **Settings** — privacy and app behavior; Calendar and iCloud settings appear only in their respective milestones.

### 6.1 First launch

- Explain the one-active-timer model in one short onboarding screen.
- Explain that elapsed time is stored from timestamps and survives leaving the app.
- Explain Lock Screen visibility before the first Live Activity starts.
- Do not request Calendar, notification, or other unrelated permissions.
- Use a privacy-first Lock Screen default: show elapsed time and Stop, but use a generic active-timer label until the user explicitly permits project names on the Lock Screen.

### 6.2 Create and manage projects

- Empty state leads directly to creating the first project.
- Required field: trimmed, nonempty name.
- Optional project color uses an accessible preset palette.
- Project names need not be globally unique; warn about an exact duplicate but do not block it.
- Archived projects disappear from the start list but remain available in reports and historical session editing.
- A project with sessions is archived rather than deleted.
- A project without sessions may be deleted after confirmation, or simply archived if implementation simplicity is preferred.

### 6.3 Start work

On tapping an inactive project:

1. Capture a single `Date` value.
2. Persist a new active session before showing success UI.
3. Start a Live Activity independently; Live Activity failure must not roll back the session.
4. Make the active project visually dominant.
5. Derive displayed elapsed time from the stored start timestamp rather than incrementing an in-memory counter.

### 6.4 Switch projects

On tapping a different project while a timer is active:

1. Capture one boundary timestamp `t`.
2. Set the old session's end to `t`.
3. Create the new session with start `t`.
4. Save both changes as one command so no gap or overlap is introduced by the switch.
5. Update the Live Activity to the new project.
6. Present a dismissible previous-session note sheet while the new timer continues.

If persistence fails, leave the old active session unchanged and show a recoverable error.

### 6.5 Stop in the app

1. Capture the stop timestamp immediately.
2. Persist it and end the Live Activity.
3. Open the completion screen showing project, exact start, exact end, and exact duration.
4. Allow an optional note to be saved or skipped.
5. Leaving the completion screen without a note does not undo or delete the session.

### 6.6 Stop from the Lock Screen

The initial target interaction is:

1. The Live Activity displays elapsed time and a square Stop control, not a pause icon.
2. The user authenticates if the device is locked, as required by iOS.
3. A Live Activity App Intent captures and persists the stop timestamp.
4. The Live Activity ends with the final duration.
5. The app transitions to the foreground and deep-links to the stopped session's completion screen when the OS permits it.
6. If foreground transition is unavailable, the ended Live Activity changes to `Stopped — tap to add notes`; tapping it deep-links to the same completion screen.

FND-02 establishes this flow with automated simulator coverage. Physical
confirmation of authentication, actual process-state transitions, Dynamic
Island behavior, and the ended-card fallback is deferred to `QA-03` and remains
a release gate before the main Lock Screen UI is considered final.

### 6.7 Correct history

- Add a completed manual session by choosing project, start, end, and optional note.
- Validate that end is later than start.
- Allow overlaps but show a nonblocking warning before save and an overlap marker afterward.
- Edit project, start, end, and note for completed sessions.
- Allow the active session's start time and note to be edited, but do not allow a future start.
- Delete a session only after confirmation.
- Every mutation updates `updatedAt`.

### 6.8 Review reports

**Day**

- Selected local date.
- Exact daily total.
- Totals grouped by project.
- Chronological session segments and notes.
- Running time may appear provisionally in the current day and is clearly labeled `Active`.

**Week**

- Uses the user's configured `Calendar`, locale, time zone, first weekday, and minimum-days-in-first-week rules.
- Exact selected-week total.
- Daily and project totals.
- Drill-down to contributing session segments.

**Project**

- Selected project and date range.
- Exact total and contributing sessions.
- Archived projects remain selectable.

For all reports, tapping an aggregate reveals exactly which session segments produced it.

## 7. Technical architecture

### 7.1 Platform and frameworks

- Swift and SwiftUI for the app UI.
- SwiftData for local persistence with a versioned schema from the first release.
- ActivityKit and WidgetKit for the Live Activity.
- App Intents for Lock Screen Stop.
- EventKit in product milestone 2.
- SwiftData's private CloudKit integration in product milestone 3, subject to the schema audit and device tests in that milestone.
- XCTest and XCUITest for automated tests.
- No third-party runtime dependencies unless a concrete need survives review.

The initial release supports the current iOS major only. The development
baseline is iOS 26 with a minimum deployment target of iOS 26.0; iOS 17 and
iOS 18 are not supported targets. Raising the baseline for a future current-iOS
release must be an explicit product and QA decision.

### 7.2 Targets and modules

Recommended structure:

```text
BillableHoursApp
├── App
│   ├── AppEnvironment
│   ├── Navigation
│   └── DependencySetup
├── Domain
│   ├── Models
│   ├── Commands
│   ├── Reporting
│   └── Validation
├── Data
│   ├── SwiftDataModels
│   ├── Repositories
│   └── Migrations
├── Features
│   ├── Track
│   ├── Projects
│   ├── SessionCompletion
│   ├── SessionEditor
│   ├── Reports
│   └── Settings
├── Integrations
│   ├── LiveActivity
│   ├── Calendar          # Milestone 2
│   └── CloudSync         # Milestone 3
├── BillableHoursWidgets  # Widget extension
├── BillableHoursTests
└── BillableHoursUITests
```

Keep pure reporting and validation code independent of SwiftUI and SwiftData so it can be exhaustively unit tested. Share Live Activity attributes and intent-facing value types between the app and widget extension through a small shared target or local package.

### 7.3 Command and repository boundaries

All mutations go through explicit command services rather than directly from views:

- `ProjectCommandService`
- `SessionCommandService`
- `TimerCommandService`
- `CalendarSyncService` in milestone 2

`TimerCommandService` is the only supported path for start, switch, and stop. It serializes timer mutations, provides idempotent commands, and owns active-session reconciliation. This boundary is also the insertion point for complete revision records in milestone 4.

Views consume query models and invoke commands. They do not encode timer invariants or reporting arithmetic.

### 7.4 Clock and calendar dependencies

Inject these dependencies:

- `Clock`/`NowProvider` for capturing current time.
- `CalendarProvider` for locale-aware reporting boundaries.
- `TimeZoneProvider` for testable time-zone changes.
- `UUIDProvider` for deterministic tests.

Production uses system values; tests use fixed values. A persisted `Date` is the authoritative instant. Duration is `end.timeIntervalSince(start)` and is never based on UI refresh count.

### 7.5 Active-session invariant

- An active timed session has `endAt == nil` and `source == timer`.
- Normal command paths must never produce more than one.
- Start while active routes through Switch.
- Stop is idempotent: retrying a stop for an already-stopped session returns the existing result rather than changing the end time.
- On launch and before every timer command, reconcile unexpected state.
- If corrupt data contains multiple active timed sessions, preserve the most recently started one as active, close or flag older records for review, and never silently discard them.
- Manual sessions are always completed records; they may overlap an active or completed session.

### 7.6 Live Activity independence

The database session is authoritative; the Live Activity is a projection.

- Timer creation succeeds even when Live Activities are disabled or ActivityKit fails.
- Lock Screen Stop must persist the session before ending the projection.
- The app reconciles ActivityKit state with the active database session on foreground launch.
- Dismissing a Live Activity does not stop the timer.
- Apple's current documented active lifetime is eight hours. If the system ends the Live Activity, the underlying timer continues accurately. On the next foreground launch, show a prominent long-running review state and recreate the Live Activity if the session remains active.
- The eight-hour behavior is covered by an accelerated automated test and at least one physical-device soak test before release.

## 8. Data model

Use stable app-generated UUIDs. Avoid relying on datastore-enforced uniqueness so the model remains compatible with later CloudKit sync.

### 8.1 Project

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Stable identity |
| `workspaceID` | UUID? | Null locally in v1; reserved for future ownership |
| `name` | String | Trimmed, nonempty |
| `colorToken` | String? | Semantic palette token, not a raw UI object |
| `status` | enum/string | `active` or `archived` |
| `createdAt` | Date | Immutable |
| `updatedAt` | Date | Updated for every mutation |

### 8.2 TimeSession

| Field | Type | Notes |
| --- | --- | --- |
| `id` | UUID | Stable identity |
| `workspaceID` | UUID? | Null locally in v1 |
| `projectID` | UUID | Scalar reference keeps ownership explicit |
| `source` | enum/string | `timer` or `manual` |
| `startAt` | Date | Full available precision |
| `endAt` | Date? | Null only for the active timed session |
| `startTimeZoneID` | String | Context at capture time; instant remains authoritative |
| `endTimeZoneID` | String? | Context at stop/edit time |
| `note` | String? | Confidential user-entered text |
| `createdAt` | Date | Immutable |
| `updatedAt` | Date | Updated for every mutation |
| `calendarEventID` | String? | Added/activated in milestone 2 |
| `calendarSyncState` | enum/string | Added/activated in milestone 2 |
| `calendarLastSyncedAt` | Date? | Added/activated in milestone 2 |

Do not persist a duration field as a second source of truth. Expose derived duration from start/end timestamps. If a cached aggregate is ever added for performance, it must be disposable and fully rebuildable.

### 8.3 Future SessionRevision

Milestone 4 can add:

- Stable revision ID.
- Session ID.
- Revision number.
- Action: create, update, delete, restore.
- Full before/after snapshot or a canonical field delta.
- Changed timestamp.
- Change origin: app UI, Lock Screen intent, Calendar reconciliation, iCloud merge.

The centralized command layer ensures this can be introduced without finding mutation logic scattered through views.

### 8.4 Schema evolution rules

- Declare a versioned SwiftData schema from v1.
- Add explicit migrations for every released schema change.
- Prefer additive, optional/defaulted fields.
- Do not use SwiftData unique constraints for IDs if the same schema will later sync through CloudKit.
- Keep relationships optional or use scalar identifiers where CloudKit's relationship restrictions would otherwise be a problem.
- Test migration from every shipped schema version before release.

## 9. Reporting specification

### 9.1 Interval rules

- Treat every completed interval as half-open: `[startAt, endAt)`.
- Adjacent sessions ending and starting at the same instant do not overlap.
- Reject a session whose end is equal to or earlier than its start.
- Active-session reports use `[startAt, now)` provisionally.

### 9.2 Boundary allocation

For a selected report range:

1. Intersect every session interval with the report interval.
2. Split the intersection at each local calendar day boundary.
3. Sum exact segment durations.
4. Group those same segments by day and project.
5. Preserve a link from every segment to its source session.

Never assume a day is exactly 24 hours. Ask `Calendar` for the next boundary so daylight-saving transitions are handled correctly.

Example: one stored session from Monday 11:30 PM to Tuesday 12:30 AM contributes 30 minutes to Monday and 30 minutes to Tuesday. The note and session identity remain singular.

### 9.3 Week rules

- Use the user's configured calendar and time zone.
- Use that calendar's `firstWeekday` and `minimumDaysInFirstWeek` behavior.
- Calculate week intervals from calendar date intervals, not hardcoded Sunday/Monday assumptions.
- Recompute presentation buckets when locale or time zone changes; do not mutate source timestamps.

### 9.4 Overlap rules

- Overlapping manual sessions are valid.
- Sum every session independently.
- Detect overlaps with interval comparisons and mark each affected segment/session.
- Explain in the UI that totals include both records.
- Never clamp a daily total to 24 hours or silently deduplicate overlap.

### 9.5 Display precision

- Active timer: `H:MM:SS` or `MM:SS` as appropriate.
- Session and aggregate totals: exact to the second in the initial release.
- Source timestamps remain at full stored precision.
- Do not display rounded billing increments or imply decimal-hour submission accuracy that the app has not explicitly implemented.

## 10. Calendar milestone specification

Calendar is a user-controlled mirror, never the database.

### 10.1 Publication

- Request EventKit access only when the user enables or invokes publication.
- Obtain explicit consent to create a dedicated `Billable Time` calendar.
- Default publication is manual per completed session.
- Event title is the current project name.
- Event start/end exactly match the session.
- Event notes contain the work note plus a non-user-facing marker with the app/session ID.
- Save the EventKit event identifier only after successful publication.
- Calendar failure never prevents saving or editing the session.

### 10.2 Synchronization

- When a published session is edited, update its event automatically under the user's enabled sync preference.
- When a project is renamed, mark its published sessions for title updates.
- When a published session is deleted, confirm that its Calendar event will also be deleted, then attempt both operations.
- If permission is revoked or deletion fails, retain a lightweight cleanup task containing the event ID and error state but no client note.
- If the linked event has been deleted directly in Calendar, mark the session `Missing in Calendar`; do not silently create a duplicate.
- If the dedicated calendar is deleted, mark affected sessions out of sync and guide the user through recreating/relinking it.

### 10.3 Sync states

Recommended states:

- `notPublished`
- `publishing`
- `synced`
- `pendingUpdate`
- `missingEvent`
- `permissionRequired`
- `failed`

## 11. Privacy, security, and accessibility

### Privacy

- Treat project names and notes as confidential client data.
- Keep all v1 data in the app's protected container.
- Never include project names, notes, or exact session content in logs or diagnostics.
- Use opaque IDs and error categories for telemetry if telemetry is later added.
- Do not request Calendar permission until milestone 2 and explicit user action.
- Do not request iCloud capability until milestone 3.
- Provide a Lock Screen privacy setting; default to hiding project names while still showing elapsed time and Stop.
- Document what deleting a project/session does and what remains in Calendar or iCloud in later milestones.

### Accessibility

- Support Dynamic Type without truncating time totals or controls.
- Give every color a non-color status cue.
- Provide VoiceOver labels such as `Stop Acme timer, 1 hour 23 minutes elapsed` when project-name visibility is enabled, or a privacy-safe equivalent when disabled.
- Ensure Stop cannot be confused with Pause.
- Meet contrast requirements in Light Mode, Dark Mode, Always-On display, and reduced luminance.
- Use at least 44-by-44-point interaction targets.
- Respect Reduce Motion.

## 12. Error and recovery behavior

| Condition | Required behavior |
| --- | --- |
| Persistence save fails on Start | Show error; do not present an active timer |
| Persistence save fails on Switch | Keep old session active; do not create partial new session |
| Persistence save fails on Stop | Keep timer active and show retry; never pretend it stopped |
| Live Activity fails to start | Continue timer in app; show a quiet actionable status |
| Live Activity is dismissed | Continue timer; reconcile on next foreground |
| Live Activity reaches eight hours | Timer continues; flag for review on app return |
| App is killed or phone restarts | Reconstruct active state from persisted timestamps |
| System clock makes end <= start | Block completion and require review/edit |
| Multiple active records found | Reconcile deterministically and surface affected records for review |
| Project is archived while active | Require stop or switch before archive |
| Note screen is abandoned | Keep the already-saved stopped session |
| Calendar permission is denied/revoked | Keep app data; show publication/sync state and recovery action |
| Calendar event is missing | Mark out of sync; never create silent duplicates |
| iCloud is unavailable later | Continue local operation and explain sync state |

## 13. Product milestone 1 execution plan

Issue keys below are planning keys; Linear will assign canonical issue IDs later.

### Phase A — Foundation and risk retirement

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `FND-01` | Create Xcode project, app/widget/test targets, folder structure, and build configurations | M | — | App, widget extension, unit tests, and UI tests build locally |
| `FND-02` | Current-iOS interactive Live Activity Stop and completion deep-link spike | L | FND-01 | Persist-first/idempotent Stop and completion routing pass automated simulator coverage; residual physical-device risk is documented and assigned to QA-03 |
| `FND-03` | Define versioned SwiftData v1 schema and migration harness | M | FND-01 | Project/session persist across relaunch; in-memory test store works; schema is CloudKit-compatible by design |
| `FND-04` | Add dependency container, injected clock/calendar/UUID providers, and test fixtures | M | FND-01 | Deterministic unit tests can control time, locale, time zone, and IDs |
| `FND-05` | Establish CI build, test, lint/format, and secrets-free configuration | M | FND-01 | Pull-request build and unit suite run without production credentials |

Exit gate: Live Activity interaction risk is understood, persistence foundations exist, and no major architecture decision remains untested.

### Phase B — Domain behavior and persistence

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `DOM-01` | Implement project queries and commands | M | FND-03, FND-04 | Create, rename, archive, restore, duplicate warning, timestamps |
| `DOM-02` | Implement timer Start command | M | FND-03, FND-04 | Persist-before-UI, exact timestamp, one-active invariant |
| `DOM-03` | Implement atomic Switch command | M | DOM-02 | Old end equals new start; failure produces no partial switch |
| `DOM-04` | Implement idempotent Stop command | M | DOM-02 | First stop wins; retry returns same completed session |
| `DOM-05` | Implement active-state startup reconciliation | L | DOM-02, DOM-04 | Background, kill, reboot, and malformed-multiple-active cases are recoverable |
| `DOM-06` | Implement manual session add/edit/delete and validation | L | FND-03, FND-04 | Completed sessions editable; overlaps allowed with warning; timestamps maintained |
| `DOM-07` | Implement overlap detection | S | DOM-06 | Adjacent intervals are not overlaps; all actual overlaps identified |

Exit gate: all timer and correction behaviors pass domain tests without UI or ActivityKit.

### Phase C — Core app experience

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `UI-01` | Build first-launch and empty-state experience | M | DOM-01 | User can understand model and create first project |
| `UI-02` | Build Track screen and project list | L | DOM-01, DOM-02 | One-tap Start; active project visually prominent; archived projects hidden |
| `UI-03` | Build in-app active timer and Stop | M | DOM-04, UI-02 | Elapsed display derives from timestamp; Stop opens completion |
| `UI-04` | Build Switch flow and previous-session note sheet | M | DOM-03, UI-02 | New timer starts immediately; previous note can be saved/skipped |
| `UI-05` | Build completion screen and note editing | M | DOM-04 | Final duration visible; leaving cannot lose session |
| `UI-06` | Build project management screens | M | DOM-01 | Rename/archive/restore and active-project safeguards work |
| `UI-07` | Build manual session editor and overlap warning | L | DOM-06, DOM-07 | Add/edit/delete workflows meet validation rules |
| `UI-08` | Add privacy and Lock Screen detail setting | S | UI-01 | Generic label is default; explicit opt-in shows project names |

Exit gate: the complete local capture/correction loop works without the Live Activity or reports.

### Phase D — Live Activity integration

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `ACT-01` | Build Lock Screen and Dynamic Island presentations | L | FND-02, UI-03 | Project/privacy label, elapsed timer, Stop, accessibility, all presentation families |
| `ACT-02` | Connect Start/Switch/Stop to ActivityKit lifecycle | L | ACT-01, DOM-03, DOM-04 | Projection matches authoritative timer; failures do not change session data |
| `ACT-03` | Implement Lock Screen Stop App Intent and deep link | L | FND-02, ACT-02, UI-05 | Stop persists first; app opens completion or shows tap-to-open fallback |
| `ACT-04` | Implement foreground reconciliation and eight-hour behavior | M | ACT-02, DOM-05 | Dismissed/expired/stale activity never corrupts timer; long session flagged |

Exit gate: device tests confirm the desired stop flow and all fallbacks.

### Phase E — Reporting

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `RPT-01` | Implement pure interval intersection and calendar-boundary splitting engine | L | FND-04, DOM-06 | Exact results for midnight, week, DST, locale, active sessions, overlaps |
| `RPT-02` | Build Day report | L | RPT-01 | Total, project groups, timeline, notes, overlap and active markers |
| `RPT-03` | Build Week report | L | RPT-01 | Week total, daily/project groups, drill-down, locale-correct boundaries |
| `RPT-04` | Build Project report and date-range selector | L | RPT-01 | Active/archived projects, exact range intersection, contributing sessions |
| `RPT-05` | Add aggregate explainability and session navigation | M | RPT-02, RPT-03, RPT-04 | Every total opens its exact contributing segments and source sessions |

Exit gate: all aggregate invariants pass and a user can derive a timesheet from the screens.

### Phase F — Hardening and initial release

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `QA-01` | Complete timer/persistence failure and recovery suite | L | DOM-05, ACT-04 | Kill, background, restart, race, failure rollback, idempotency covered |
| `QA-02` | Complete reporting edge-case suite | L | RPT-05 | Boundary, DST, locale, overlap, active and >24-hour totals covered |
| `QA-03` | Run current-iOS physical-device Live Activity matrix and soak tests | L | ACT-04 | Current-iOS device classes, lock/auth, disabled setting, and eight-hour path verified |
| `QA-04` | Accessibility audit and fixes (post-launch, non-blocking) | M | UI/RPT complete | VoiceOver, Dynamic Type, contrast, Reduce Motion, target sizes pass |
| `QA-05` | Privacy, logging, data-retention, and crash-report audit | M | App complete | No confidential content leaves store; privacy disclosures are accurate |
| `REL-01` | Add polished empty/error/recovery states and app settings | M | Feature complete | All expected errors have actionable user-facing behavior |
| `REL-02` | Beta feedback round and prioritized fixes | L | QA-01..03, QA-05, REL-01 | Target professionals complete core workflows; critical feedback resolved |
| `REL-03` | App Store assets, privacy manifest, metadata, and release checklist | M | REL-02 | Release candidate satisfies gate below |

`QA-04` remains in the post-launch backlog and does not gate `REL-02`, `REL-03`, or the initial release.

## 14. Product milestone 2 execution plan — Calendar

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `CAL-01` | Design permission, consent, and dedicated-calendar flow | M | Product milestone 1 | No permission request before explicit action; denial is recoverable |
| `CAL-02` | Create/reuse dedicated `Billable Time` calendar | M | CAL-01 | Calendar identity persists and missing-calendar state is detected |
| `CAL-03` | Publish a completed session manually | L | CAL-02 | Exact timestamps/title/note marker; event ID stored only on success |
| `CAL-04` | Update linked events after session/note/project edits | L | CAL-03 | Existing event updated without duplicate; failures produce visible state |
| `CAL-05` | Delete linked event with app-side session deletion | L | CAL-03 | Confirmed deletion attempts both; cleanup task handles revoked access/failure |
| `CAL-06` | Detect missing events, calendar deletion, and permission revocation | L | CAL-04, CAL-05 | Clear sync states and recovery actions; no silent recreation |
| `CAL-07` | Calendar integration and device test suite | L | CAL-06 | Permission matrix, external edits/deletes, timezone, retries, app restarts covered |
| `CAL-08` | Calendar beta and release gate | M | CAL-07 | No session loss; no duplicate generation in supported flows |

## 15. Product milestone 3 execution plan — iCloud

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `SYN-01` | Audit released schema for CloudKit compatibility | L | Product milestone 2 | No unsupported unique constraints/required relationships; migration path proven |
| `SYN-02` | Configure private CloudKit container and environments | M | SYN-01 | Development/production schemas controlled; credentials absent from repository |
| `SYN-03` | Enable opt-in SwiftData sync and expose sync state | L | SYN-02 | Local-first operation continues offline/signed out; state is understandable |
| `SYN-04` | Define and implement conflict policies | XL | SYN-03 | Deterministic project/session merges; one-active invariant restored safely |
| `SYN-05` | Reconcile Live Activities with changes from another device | L | SYN-04 | No stale device projection silently stops or replaces newer timer state |
| `SYN-06` | Multi-device, offline, migration, and failure testing | XL | SYN-05 | Create/edit/delete/conflict/sign-out/reinstall scenarios verified |
| `SYN-07` | iCloud beta and release gate | L | SYN-06 | No data loss or duplicate active timers across supported scenarios |

## 16. Product milestone 4 execution plan — Revision history

| Key | Issue | Size | Depends on | Acceptance summary |
| --- | --- | --- | --- | --- |
| `AUD-01` | Finalize revision semantics and retention policy | M | Product milestone 3 | Create/update/delete/merge origins and privacy behavior defined |
| `AUD-02` | Add versioned `SessionRevision` schema and migration | L | AUD-01 | Existing sessions migrate without fabricated history |
| `AUD-03` | Append revisions from every command path | L | AUD-02 | UI, Lock Screen, Calendar, and iCloud mutations are covered |
| `AUD-04` | Build session history view | L | AUD-03 | User can understand values and timestamps for every revision |
| `AUD-05` | Add restore/copy behavior if validated | M | AUD-04 | Restore creates a new revision and never rewrites prior history |
| `AUD-06` | Sync, migration, retention, and privacy testing | L | AUD-05 | History remains ordered and complete across devices and deletes |

## 17. Critical path and blocking graph

```text
FND-01 Project scaffold
├── FND-02 Live Activity feasibility spike ── ACT-01 ── ACT-02 ── ACT-03 ── ACT-04
├── FND-03 Persistence/schema ── DOM-01..07 ── UI-01..08
└── FND-04 Testable dependencies ─┬─ DOM-01..07
                                 └─ RPT-01 ── RPT-02..04 ── RPT-05

UI + ActivityKit + Reports
        └── QA-01..03 + QA-05 ── REL-01 ── REL-02 ── REL-03 ── Initial release

Initial release ── CAL-01..08 ── Calendar release
Calendar release ── SYN-01..07 ── iCloud release
iCloud release ── AUD-01..06 ── Revision-history release
```

`FND-02` retires the simulator-testable portion of the highest-risk interaction.
Its accepted residual physical-device risk is tracked by `QA-03`; avoid treating
the final Lock Screen behavior as proven until that device matrix passes.
Reporting can proceed in parallel after `FND-04` because it is a pure domain
problem.

## 18. Test strategy

### Unit tests

- Start, switch, stop, retry, and save-failure rollback.
- Concurrent or repeated command handling.
- App-start active-state reconciliation.
- Project archive/restore and session reassignment rules.
- Manual validation and overlap detection.
- Interval intersection and segmentation.
- Midnight, year, week, DST-forward, DST-back, locale, and time-zone changes.
- Active provisional totals and sessions longer than 24 hours.
- Aggregate invariant: report total equals sum of displayed segments.
- Schema migration and corrupted-state fixtures.

### Integration tests

- SwiftData persistence across container recreation.
- App Intent invoking the same command service as app UI.
- ActivityKit lifecycle reconciliation.
- Deep-link routing to the correct completion/session screen.
- EventKit permission and event lifecycle in milestone 2.
- CloudKit device and conflict scenarios in milestone 3.

### UI tests

- First project to first completed session.
- One-tap switch and previous-session note entry.
- In-app stop and completion.
- Manual missed-session correction.
- Day/week/project report drill-down.
- Archive/restore project.
- Error and empty states.
- Large Dynamic Type and VoiceOver smoke flows.

### Physical-device tests

- Lock and unlock with Face ID/Touch ID/passcode behavior.
- Stop when the app is foregrounded, backgrounded, suspended, and terminated.
- Device restart with active timer.
- Dynamic Island and non-Dynamic-Island supported devices.
- Live Activities disabled in Settings.
- Always-On and reduced-luminance presentation.
- System removal/dismissal and eight-hour expiration.
- Time zone and daylight-saving transitions where practical, supported by injected-clock tests.

## 19. Initial-release gate

Do not ship until:

- All P0/P1 defects are resolved.
- No supported workflow can create two active timed sessions.
- Stop never loses a completed session when note entry is abandoned.
- Persistence failure paths do not show false success.
- Report aggregate invariants pass the full edge-case suite.
- Lock Screen Stop has been verified on physical hardware running the current
  supported iOS major.
- Eight-hour Live Activity expiration leaves the source session intact and recoverable.
- Project names and notes are absent from logs and diagnostics.
- Migration from the oldest shipped schema succeeds.
- App Store privacy labels and privacy manifest match actual behavior.
- Beta users representing at least two target professions can complete a day and week review without explanation from the development team.

## 20. Linear operating model

No Linear objects should be created until the workspace, team, owner, priority conventions, estimate scale, and desired target dates are confirmed.

### Recommended Linear structure

- One Linear project: **Billable Hours iPhone App**.
- Product milestones:
  1. **Trustworthy Local Tracker**
  2. **Apple Calendar Mirror**
  3. **Private iCloud Sync**
  4. **Complete Revision History**
- Use the phase headings in this document as issue groups/epics within each milestone.
- Create the issue rows above as individual Linear issues; allow Linear to assign canonical identifiers.

### Recommended labels

Use a small, orthogonal label set:

- Type: `Feature`, `Bug`, `Spike`, `Chore`.
- Area: `Timer`, `Projects`, `Sessions`, `Reports`, `Live Activity`, `Calendar`, `Sync`, `Data`, `UI`, `QA`, `Release`.
- Risk: `High Risk` only when it changes sequencing or needs early validation.

Avoid using labels to duplicate status, priority, or milestone.

### Recommended workflow

- `Backlog` — accepted but not yet ready.
- `Ready` — scoped, acceptance criteria present, blockers cleared.
- `In Progress` — actively owned.
- `In Review` — code/design review or QA verification.
- `Blocked` — cannot progress; issue must state the blocker and owner.
- `Done` — acceptance criteria and required tests pass.

### Issue template

Every implementation issue should contain:

```text
Outcome
Why this issue exists and what user/system result it produces.

Scope
Concrete behavior included and explicitly excluded.

Acceptance criteria
- Observable, testable statements.

Dependencies
- Blocking issue keys and external prerequisites.

Test notes
- Unit, integration, UI, and physical-device coverage required.

Risks / decisions
- Unresolved judgment calls or rollout concerns.
```

### Blocker discipline

- Use explicit issue relationships where Linear supports them.
- A blocked issue must name the blocking issue or external decision.
- `FND-02` is the first high-risk issue and blocks final Lock Screen implementation.
- Calendar and iCloud permissions/capabilities are not prerequisites for milestone 1.
- Do not place all work in one cycle; pull only issues whose dependencies are complete.
- Review blocked issues at least once per working day during active development.

## 21. Risks and mitigations

| Risk | Impact | Mitigation |
| --- | --- | --- |
| Lock Screen Stop cannot always both act and foreground exactly like Apple's Workout UI | Core interaction differs from aspiration | Persist Stop before foreground attempt; provide ended-card deep-link fallback; carry the accepted FND-02 physical-device uncertainty into QA-03 and do not remove the release gate |
| Live Activity expires after eight active hours | Lock Screen Stop disappears while source timer continues | Keep database authoritative; surface long-running review; reconcile/recreate on foreground; evaluate notification later |
| App termination or race creates malformed active state | Untrustworthy totals | Serialized idempotent command service, persist-first UI, startup reconciliation, failure injection tests |
| Calendar user edits/deletes generated events | App and Calendar diverge | Stored event ID, explicit sync states, missing-event detection, no silent duplicate recreation |
| Manual overlaps inflate totals | User enters unexpected timesheet values | Permit by decision, flag visually, explain totals, never hide or clamp |
| Locale/time-zone/DST errors | Day/week totals are wrong | Calendar-based boundary engine and exhaustive fixed-clock tests |
| SwiftData schema blocks later CloudKit adoption | Expensive migration | Version schema now; stable UUIDs; avoid unique constraints and required relationships; milestone-3 audit |
| Notes/project names leak on Lock Screen or diagnostics | Confidentiality breach | Privacy-first Lock Screen default; content-free logs; privacy audit release gate |
| iCloud conflicts violate one-active invariant | Duplicate concurrent timers | Defer sync; define explicit conflict/reconciliation policy before enabling it |
| Revision history increases retained sensitive data | Privacy and storage expectations change | Define retention/deletion policy before milestone 4 and reflect it in disclosures |

## 22. Nonblocking decisions to revisit

These do not block milestone-1 foundation work:

- Final app name and visual identity.
- Minimum supported iOS version, after the Live Activity spike and device-coverage decision.
- Whether duplicate project names merely warn or require an additional visual distinction.
- Whether a project with no sessions can be permanently deleted or is always archived.
- Whether long-running timers should trigger an optional local notification in a later release.
- Whether report totals should offer an additional decimal-hours display while preserving exact seconds.
- Calendar marker wording and out-of-sync recovery copy.
- iCloud opt-in versus default-on behavior.
- Revision retention and purge policy.
- Export format and milestone after user research.

## 23. Platform references

- [ActivityKit](https://developer.apple.com/documentation/ActivityKit)
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)
- [Linking to app scenes from a widget or Live Activity](https://developer.apple.com/documentation/widgetkit/linking-to-specific-app-scenes-from-your-widget-or-live-activity)
- [App Intent execution modes](https://developer.apple.com/documentation/appintents/appintent/supportedmodes)
- [SwiftData schema and migration](https://developer.apple.com/documentation/swiftdata/schema)
- [SwiftData iCloud synchronization](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
- [EventKit event creation and deletion](https://developer.apple.com/documentation/eventkit/creating-events-and-reminders)
