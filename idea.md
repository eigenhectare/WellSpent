# Idea Brief: Billable Hours Tracker

## Raw Idea

Create a simple iPhone app for consultants, lawyers, and other professionals who submit billable hours across multiple projects. A user creates project names, taps a project to start a stopwatch, and stops it when the work session ends. The completed session can include notes describing the work. Users can review how they spent their time by day, week, or project, and optionally publish completed sessions to Apple Calendar as retrospective events.

The first version is for individual professionals. Team sharing may follow later, so the underlying data model should not prevent projects and time records from eventually being shared.

## One-Sentence Version

An individual-first iPhone time tracker that turns one tap into an exact, project-specific billable-time record with notes, reports, and an optional Calendar mirror.

## Target User

Independent consultants, lawyers, agency professionals, and other individual knowledge workers who divide their day among multiple billable projects and later submit a timesheet.

The initial user manages their own projects and records. Firms, managers, and shared team workspaces are future users rather than first-version requirements.

## Problem

Professionals often reconstruct billable time after the fact from memory, calendars, messages, and documents. This is slow and produces incomplete or inaccurate timesheets. Traditional time-tracking products can also require too many steps when the most frequent action is simply switching from one project to another.

## Desired Outcome

The user can accurately capture work as it happens, understand where each day and week went, and turn recorded sessions into a project-level breakdown suitable for completing a timesheet.

Success for the first version means:

- Starting or switching projects takes one obvious tap.
- Timing remains correct when the app is backgrounded or the phone is locked.
- A completed session records its exact start time, end time, and duration.
- The user can add enough context to remember and justify the work later.
- The user can review totals and underlying sessions by day, week, and project.
- Forgotten or incorrect entries can be repaired without losing an audit-friendly record of what occurred.

## Smallest Useful Version

An iPhone app with local persistence that supports:

- Creating, renaming, and archiving projects.
- Starting a timer by tapping a project.
- One active timer at a time.
- Switching directly to another project by ending the current session and starting the selected project.
- Accurate elapsed time derived from stored timestamps rather than a continuously running in-memory counter.
- Stopping a timer and optionally adding or editing a work note.
- Manually adding, editing, and deleting a session to correct omissions or mistakes.
- Reviewing sessions and exact totals for a selected day, calendar week, or project.
- Optional publication of a completed session to a dedicated Apple Calendar.
- A clear indication of whether a session has been published to Calendar.

The app remains the authoritative record. Calendar events are a user-controlled retrospective view, not the primary database.

## Core Workflows

1. **Set up projects:** The user creates projects and sees active projects in a simple list.
2. **Start work:** The user taps a project; its timer starts immediately and the active project is visually prominent.
3. **Switch work:** The user taps a different project; the app ends the previous session and starts the new one, avoiding overlapping billable time.
4. **Finish and describe work:** The user stops the active timer and can enter a note describing what was completed.
5. **Publish to Calendar:** If Calendar integration is enabled, the user publishes the completed session—or allows configured automatic publication—as a past event using the session's exact timestamps.
6. **Review a timesheet:** The user selects a day, week, or project to see totals plus the sessions and notes behind them.
7. **Correct history:** The user adds a missed session or edits an incorrect start time, end time, project, or note; any linked Calendar event is updated or clearly marked out of sync.

## Proposed Information Model

### Project

- Stable identifier
- Name
- Optional color
- Active or archived status
- Created and updated timestamps
- Future ownership/workspace identifier, kept local and nullable in v1

### Time Session

- Stable identifier
- Project identifier
- Start timestamp
- End timestamp, empty while active
- Exact duration derived from start and end timestamps
- Optional work note
- Created and updated timestamps
- Optional linked Calendar event identifier
- Calendar publication/sync state
- Future ownership/workspace identifier, kept local and nullable in v1

Store timestamps at full available precision. Reporting should sum the recorded durations without billing-increment rounding in v1.

## Reporting Views

- **Day:** Chronological timeline of sessions, daily total, and totals grouped by project.
- **Week:** Total for the selected calendar week, daily totals, project totals, and drill-down to sessions.
- **Project:** Total over a selected date range and the contributing sessions with notes.

The reporting model should make every aggregate explainable: tapping a total reveals the sessions included in it.

## Calendar Integration Notes

- Use Apple's EventKit APIs and request Calendar access only when the user enables the feature.
- Prefer a dedicated calendar, such as `Billable Time`, so generated events can be distinguished from meetings and personal appointments.
- Suggested event title: the project name.
- Suggested event notes: the session's work note plus a marker identifying the originating app/session.
- Use the exact session start and end times, including for events created after the work occurred.
- Save the generated event identifier so later edits can update the corresponding event instead of creating a duplicate.
- Calendar access or publication failure must never prevent the underlying time session from being saved.
- Automatic publication, if included, should be opt-in. Manual publication is the safer first-version default until edit and deletion behavior is settled.

## Non-Goals

- Shared team workspaces or real-time collaboration in v1.
- Manager approval workflows.
- Firm-wide reporting or utilization analytics.
- Invoice generation, payment collection, or accounting.
- Client portals.
- Billing rates, budgets, retainers, or profitability calculations.
- Automatic activity surveillance or inferring projects from other apps.
- Android, web, iPad, Apple Watch, or macOS versions in v1.
- Rounding to six-minute, fifteen-minute, or other billing increments in v1.

## Constraints

- iPhone-first native experience.
- Exact tracking requires persistent start and end timestamps and must survive app termination, phone locking, and device restarts.
- Only one active session may exist at a time.
- Calendar access is optional and permission-dependent.
- Calendar and app data can diverge if users edit or delete generated events directly in Calendar.
- Sessions and notes may contain confidential client information and require an explicit privacy and storage approach before team sharing or cloud sync.
- A calendar week depends on locale and user settings; the app should use the user's configured calendar and time zone while preserving original timestamps.

## Questions To Resolve

- What submission/export format is required for the first useful release: on-screen review only, CSV, PDF, share sheet, or integration with an existing timesheet system?
- Should Calendar publication be manual per session, automatically performed after every stopped session when enabled, or selectable at stop time?
- If an app session is edited or deleted after publication, should the linked Calendar event update/delete automatically or require confirmation?
- Should stopping a timer open a note screen every time, show a lightweight optional prompt, or stop immediately and let the user add notes later?
- What should happen when a timer is accidentally left running for an implausibly long time: notification only, a review flag, or a configurable cutoff?
- Is iCloud sync across one person's iPhone devices valuable before team sharing, or should v1 be entirely local to one device?
- For future team sharing, is the goal shared visibility, a manager-ready submission and approval flow, or collaborative management of the project list?

## Risks And Tradeoffs

- Requiring notes at stop time improves record quality but adds friction to the most frequent action.
- Automatic Calendar publication feels seamless but increases complexity around permissions, duplicate events, edits, deletions, and user-created changes in Calendar.
- Local-only storage keeps the first version simpler and more private, but creates backup and multi-device limitations.
- Designing for future team ownership now can reduce migration work, but implementing authentication or cloud infrastructure before validating personal tracking would expand the MVP substantially.
- Exact duration is faithful to captured time, but many firms ultimately require rounded billing increments; reporting/export may need configurable rounding later while retaining exact source records.

## Recommended Product Sequence

1. Validate the core loop with local projects, one active timer, notes, corrections, and day/week/project reporting.
2. Add a submission-friendly export after choosing the required format.
3. Add manual Calendar publication with reliable linkage and update behavior.
4. Evaluate opt-in automatic Calendar publication after the manual flow is stable.
5. Add private cross-device sync if users need it.
6. Shape team sharing around a specific workflow—visibility, submission/approval, or project administration—rather than adding generic collaboration.

## Notes

Working product description: "Tap a project when work starts; finish the week with a timesheet you can trust."
