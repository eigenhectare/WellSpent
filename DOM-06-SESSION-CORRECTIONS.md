# DOM-06 manual sessions and corrections

## Domain contract

`SessionCommandService` is the mutation boundary for historical session
corrections:

- `createManual(...)` requires finite start/end instants at or before the
  injected current time, with `endAt > startAt`. It always persists a completed
  `.manual` record, optional note, and selected tag assignments and cannot
  create another active timer.
- `editCompleted(...)` edits project, start, end, optional note, and selected
  tags for either completed timer or manual sessions. Stable ID, source, and
  `createdAt` remain unchanged.
- `editActive(...)` changes only start and note for the sole active timed
  session. A future start or malformed multiple-active state is rejected.
- `delete(..., confirmed:)` requires explicit confirmation and rejects active
  sessions. Its returned deletion snapshot records the injected mutation time.
- Archived projects remain available for manual historical entry and completed
  session reassignment.
- Optional notes are trimmed; whitespace-only notes become `nil`.
- Tag selection is multi-value. Each assignment stores the selected tag ID and
  name snapshot. Archiving a tag definition removes it from new-session choices
  without changing historical assignments; deleting a session removes only its
  own assignments.

Every real mutation receives one injected `updatedAt` timestamp and saves
before returning. Create, edit, and delete failures roll back their entire
SwiftData context change.

## Overlap warning boundary

Overlaps are informational and never block saving. The service treats
intervals as half-open: touching boundaries are not overlaps, while an active
session has an open-ended interval. Warning session IDs are stable and sorted.

`validateCompletedSession(...)` lets UI-07 show a warning before save. The
mutation command repeats overlap detection to return the authoritative warning
set if records changed after preview. DOM-07's pure `SessionOverlapDetector`
now provides the shared half-open interval behavior used by these commands and
future report/UI markers.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM06-SessionCommands \
  -only-testing:BillableHoursTests/SessionCommandServiceTests \
  test
```

The focused suite covers manual creation metadata, archived-project use,
invalid/future timestamps, overlap preview and persistence, completed and
active editing, confirmation, active-session safeguards, create/edit/delete
rollback, and create/edit/delete across real store recreation.
