# FND-03 SwiftData Persistence Foundation

## Versioned schema

`BillableHoursSchemaV1` is version `1.0.0` and remains the immutable oldest
shipped schema. `BillableHoursSchemaV2` is the current `2.0.0` schema.
`BillableHoursMigrationPlan` lists both and declares an explicit lightweight
v1-to-v2 migration. Every later released schema must be appended to the plan
with an explicit lightweight or custom migration stage; historical schema
types must not be edited in place.

The current store contains four SwiftData record types:

- `ProjectRecord`: stable UUID, nullable future workspace UUID, name, optional
  color token and emoji, raw status value, and creation/update timestamps.
- `TimeSessionRecord`: stable UUID, nullable future workspace UUID, scalar
  project UUID, raw source value, exact start/optional end timestamps, capture
  time-zone identifiers, optional confidential note, and creation/update
  timestamps. Duration is derived and is not persisted.
- `SessionTagRecord`: stable UUID, normalized and display names, active/archive
  status, built-in marker, and creation/update timestamps.
- `SessionTagAssignmentRecord`: stable UUID, scalar session/tag UUIDs, a name
  snapshot that preserves historical meaning, and a creation timestamp.

The four default tag definitions are seeded only when no tag record of either
status exists. Removing a tag archives its definition. Assignments remain
queryable, and entering an archived name restores that definition instead of
creating a duplicate.

Calendar linkage is intentionally deferred until the Calendar milestone.
Timer commands and the one-active-session invariant are intentionally deferred
to their DOM issues.

## CloudKit compatibility assumptions

The local store explicitly disables CloudKit. FND-03 only keeps the schema
eligible for the later private CloudKit milestone:

- No `@Attribute(.unique)` constraints are used, including for UUIDs.
- Project-to-session ownership uses a scalar `projectID`; the schema has no
  required SwiftData relationships. Tag assignments likewise use scalar
  `sessionID` and `tagID` values.
- Optional future `workspaceID` fields are present and nullable.
- Persisted enum-like values use stable strings so unknown future values can be
  handled without changing the datastore representation.
- Required persisted properties have declaration defaults. Additive optional
  or defaulted fields are preferred for later versions.

The iCloud milestone must still perform its planned schema audit and device
testing before CloudKit is enabled.

## Store construction

`BillableHoursPersistence.makePersistentContainer()` creates the production
local store in Application Support and opens it through the migration plan.
The app injects that container at its root.

Tests can use either:

- `makeInMemoryContainer()` for an isolated store that never writes to disk.
- `makePersistentContainer(storeURL:)` for deterministic fixture and
  container-recreation tests.

## Verification

Regenerate the project after source or project-spec changes:

```sh
cd '/Users/dev/Documents/Billable Hours App'
xcodegen generate --spec project.yml
```

Run the focused persistence suite and existing unit tests:

```sh
cd '/Users/dev/Documents/Billable Hours App'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project BillableHours.xcodeproj \
  -scheme BillableHours \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 30 \
  -maximum-test-execution-time-allowance 60 \
  -derivedDataPath .derivedData/FND03-Tests \
  -only-testing:BillableHoursTests \
  test
```

The automated coverage initializes v2, exercises the in-memory store, checks
the CloudKit-safe absence of uniqueness constraints and relationships,
recreates a disk container to prove persistence, and reopens an oldest-version
v1 fixture through the migration harness while verifying the additive emoji,
tag-definition, and tag-assignment state.
