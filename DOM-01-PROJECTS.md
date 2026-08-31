# DOM-01 project queries and commands

## Domain contract

`ProjectCommandService` is the only project mutation boundary. It supports
create, identity updates, archive, and restore while enforcing these rules:

- Names are trimmed and must remain nonempty.
- Emoji are optional; a supplied value must be exactly one extended grapheme
  that contains an emoji scalar. Combined emoji remain one valid character.
- Name, color token, and emoji update atomically while the stable project UUID
  preserves every historical reference.
- Exact case-sensitive duplicate names produce a warning but never block the
  command.
- Creation uses one injected UUID and timestamp; creation time remains
  immutable and every actual mutation updates `updatedAt`.
- Repeating an identity/status command that would make no change is idempotent and
  does not rewrite `updatedAt`.
- A project with completed sessions can be archived without deleting or
  reassigning history.
- A project with an active timed session cannot be archived; the timer must be
  stopped or switched first.

`ProjectQueryService` exposes active, archived, all, and ID-based queries.
Archived projects leave the Track-start set but remain available to reporting
and historical editing consumers.

The services return immutable `ProjectSnapshot` values rather than exposing
SwiftData models to future views. `SwiftDataProjectRepository` owns persistence
and rolls the context back when a save fails.

## Focused verification

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/DOM01-Projects \
  -only-testing:BillableHoursTests/ProjectCommandServiceTests \
  test
```
