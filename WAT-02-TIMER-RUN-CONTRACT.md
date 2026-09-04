# WAT-02 — TimerRun, Pause/Resume, Goal, Summary, and Migration Contract

Status: Frozen for implementation  
Applies to: SwiftData schema v3, iPhone timer commands, Watch commands, history,
completion, reports, and Live Activity projection  
Depends on: [WAT-01-WATCH-UX-CONTRACT.md](WAT-01-WATCH-UX-CONTRACT.md)  
Last reviewed: September 1, 2026

## 1. Decision

A user-visible timer becomes a `TimerRunRecord`. Every interval that contributes
to billable totals remains a half-open `TimeSessionRecord` segment. Pause closes
the open segment. Resume opens a new segment. Reports continue to sum segments
and never infer billable time from run wall-clock duration.

Manual sessions remain standalone `TimeSessionRecord` values with no run. This
keeps the current report engine's exact inputs intact while giving timed work a
stable identity across pauses, Watch sync, summary editing, and system
projections.

```text
TimerRunRecord (one user-visible timer)
  id: runID
  state: running | paused | ended
  project, goal, note, tags, revision, origin
       |
       +-- TimeSessionRecord timerRunID=runID  [start, end)
       +-- TimeSessionRecord timerRunID=runID  [start, end)
       +-- TimerRunTagAssignmentRecord runID=runID, tagID=...

Manual TimeSessionRecord timerRunID=nil         [start, end)
```

## 2. Schema v3 shape

All references are scalar identifiers. Schema v3 adds no SwiftData
relationships or uniqueness constraints. Command validation, deterministic
queries, and tests enforce the invariants.

### `TimerRunRecord`

| Field | Type | Contract |
| --- | --- | --- |
| `id` | `UUID` | Stable run identity and the id used by Live Activity and Watch snapshots |
| `workspaceID` | `UUID?` | Copied from the project; never inferred by a transport receiver |
| `projectID` | `UUID` | One project for the entire run and every owned segment |
| `stateRawValue` | `String` | One of `running`, `paused`, `ended`; unknown values classify as review required |
| `startAt` | `Date` | Exact Start/Go boundary and start of the first segment |
| `endAt` | `Date?` | Exact End/Switch boundary; present only for ended runs |
| `startTimeZoneID` | `String` | Zone captured with `startAt`, used for display/audit only |
| `endTimeZoneID` | `String?` | Zone captured with `endAt` |
| `durationGoalSeconds` | `Double?` | Optional positive finite counted-time goal; never a billing cap |
| `note` | `String?` | Trimmed run-level note; empty becomes nil |
| `originDeviceID` | `UUID` | Stable install/device origin; the legacy-import sentinel is reserved |
| `revision` | `Int64` | Starts at zero for migration and one for a new Start; increments once per accepted logical mutation |
| `lastAppliedMutationID` | `UUID?` | Most recent accepted mutation; not the complete dedupe journal |
| `createdAt` | `Date` | Creation timestamp |
| `updatedAt` | `Date` | Timestamp of the last accepted logical mutation |
| `updatedTimeZoneID` | `String` | Zone captured with `updatedAt` |

`durationGoalSeconds` accepts any finite value greater than zero at the domain
boundary. UI presets and input controls may impose a narrower ergonomic range,
but persisted or remote positive values remain valid. Goal progress is counted
segment duration divided by the goal. It freezes while paused and may exceed
100 percent. A goal does not auto-end a run.

### `TimeSessionRecord` addition

`timerRunID: UUID?` is added. A timed segment created by v3 has a run ID. A
manual session has nil. A migrated historical timed session receives the
deterministic ID of its one-segment run. Segment IDs never change during
migration.

For a timed segment, `projectID` and `workspaceID` match its run. Start/end and
their zone identifiers remain the report-authoritative counted boundary. An
open segment has nil `endAt` and `endTimeZoneID`.

### `TimerRunTagAssignmentRecord`

| Field | Type | Contract |
| --- | --- | --- |
| `id` | `UUID` | Stable assignment identity |
| `workspaceID` | `UUID?` | Copied from the run |
| `timerRunID` | `UUID` | Owning run ID |
| `tagID` | `UUID` | Referenced tag ID |
| `nameSnapshot` | `String` | Preserves historical display if the tag is later archived |
| `createdAt` | `Date` | Assignment creation timestamp |

Run note and tag assignments are canonical for timed work. During v3, note and
tag values are also projected to every owned segment in the same atomic save so
existing report/source and session-detail consumers remain correct while they
are migrated. A discrepancy between the run annotation and a segment projection
is a repair/review condition; readers do not silently choose by `updatedAt`.

## 3. Healthy-state invariants

1. At most one run is non-ended.
2. A running run owns exactly one open timed segment.
3. A paused run owns no open segment and at least one completed segment.
4. An ended run owns no open segment, has `endAt`, and has at least one completed
   segment.
5. A non-ended run has nil `endAt` and nil `endTimeZoneID`.
6. A run's first segment begins at `run.startAt`.
7. Every segment is positive duration once closed. Ordered segments do not
   overlap; the next start is greater than or equal to the previous end.
8. Every owned segment has source `timer` and the run's workspace/project IDs.
9. Manual sessions have no run ID. Timed v3 sessions have one.
10. Reports sum the intersection of segment half-open intervals with the report
    period. Paused gaps and run wall-clock duration are never report inputs.
11. Each accepted logical mutation increments `revision` exactly once. Duplicate
    delivery of the same mutation ID changes nothing.
12. An invalid persisted shape is preserved and classified `reviewRequired`;
    reconciliation never invents a boundary or deletes time to make it valid.

Invariant 1 is a healthy-state constraint, not permission to rewrite malformed
legacy or divergent data. Multiple non-ended runs remain stored, all timer
mutation is blocked, and the reconciliation result identifies every conflicting
run/segment for iPhone review.

## 4. Exact derived values

At a presentation instant `t`:

```text
counted(run, t) = sum(max(0, (segment.endAt ?? t) - segment.startAt))
wall(run, t)    = (run.endAt ?? t) - run.startAt
paused(run, t)  = max(0, wall(run, t) - counted(run, t))
goalProgress    = counted(run, t) / durationGoalSeconds
```

The formulas operate on absolute `Date` instants; daylight-saving changes and
time-zone changes affect labels, not durations. A non-finite timestamp, negative
wall interval, non-positive closed segment, overlapping owned segments, or an
open segment whose start is after `t` classifies the run for review rather than
being clamped in persisted data. Presentation may clamp a negative display to
zero while showing the review state.

## 5. Command transition contract

Every command validates the observed state, captures one boundary and zone when
needed, mutates all affected records in one model-context save, and returns
success only after that save. A save failure rolls the entire command back.
WAT-03 adds the durable mutation envelope and acknowledgement around this same
boundary.

| Command | Valid source | Atomic record changes | Result / idempotency |
| --- | --- | --- | --- |
| Start | No non-ended run; active project; valid optional goal | Create running run and one open segment at the same boundary | New run revision 1; duplicate mutation returns the same run |
| Start current | Same project already running or paused | No mutation | `alreadyCurrent`; UI routes paused state to Resume rather than creating a run |
| Pause | One healthy running run | Close its open segment at boundary; set state paused; increment revision | Repeated mutation ID returns saved paused run; a new Pause while paused is `alreadyPaused` |
| Resume | One healthy paused run | Create one open segment at boundary; set state running; increment revision | Repeated mutation ID returns saved segment; a new Resume while running is `alreadyRunning` |
| Switch | One healthy running or paused run; different active project | End old run and any open segment at boundary; create new running run/open segment at the identical boundary | One transaction; duplicate returns both persisted runs without a second boundary |
| End | One healthy running or paused run | If running, close open segment; set run ended and end fields at the same boundary; increment revision | Duplicate/new retry for ended run preserves the first End boundary and returns `alreadyEnded` |
| Annotate | Existing run; normalized note; existing tag IDs | Update run note/tags and every segment annotation projection; increment revision if changed | Empty diff is a no-op; duplicate mutation is a no-op |
| Change goal | Non-ended run; nil or positive finite goal | Replace goal; increment revision if changed | Reaching or clearing a goal never alters segments |
| Correct run project | Ended run | Update run plus all owned segments and assignment workspace IDs | One transaction; report overlap warnings are returned, not auto-fixed |
| Correct segment | Ended run and existing owned segment | Change only that segment's counted boundaries/zones if all run invariants still hold | Report totals immediately reflect the segment; run End remains the user's recorded End |
| Delete run | Ended run; explicit confirmation | Delete run, owned segments, run tag assignments, and their segment assignment projections | One transaction; non-ended run deletion is rejected |

### Boundary rules

- Start requires a finite boundary.
- Pause and End while running require a boundary strictly later than the open
  segment start.
- Resume requires a boundary greater than or equal to the latest completed
  segment end and not earlier than the run start.
- End while paused requires a boundary greater than or equal to the latest
  segment end.
- Switch applies the corresponding old-run rule, then uses that exact boundary
  for the new run and its first segment.
- A backward device-clock capture is not corrected by moving a boundary. The
  command fails into review/clock-change handling so the user can preserve the
  intended time explicitly.

### Notes, tags, and summaries

The run summary is available immediately after local End. Dismissing it cannot
delete the run. Billable duration and paused duration are derived; start/end,
goal result, segment count, sync state, note, and tags are read from the run and
its segments. Annotation edits are a later transaction and can be retried
without changing End.

## 6. Reconciliation outcomes

Reconciliation is a pure inspection over runs, segments, and mutation metadata.
It has these outcomes:

- `noActiveRun`
- `running(run, openSegment)`
- `paused(run)`
- `reviewRequired(candidateRunIDs, segmentIDs, reasons)`

Within a healthy run, records are ordered by `(startAt, id.uuidString)`. Ordering
is for deterministic presentation only. It never authorizes deletion or a
fabricated end. Review reasons include multiple non-ended runs, missing or
extra open segment, state/end mismatch, missing run, mixed project/workspace,
invalid/overlapping boundaries, annotation divergence, unknown raw state, and
unsupported mutation/protocol metadata.

All Start, Pause, Resume, Switch, End, goal, and active-run correction commands
call reconciliation first and refuse mutation when it returns review required.
An ended run remains correctable through an explicit iPhone repair flow that
validates the resulting whole-run state.

## 7. Schema v3 migration

The migration path remains sequential: v1 -> v2 -> v3. The existing lightweight
v1-to-v2 stage is unchanged. The v2-to-v3 stage is a deterministic custom
migration because it must create run and run-tag records.

### Deterministic identity

`legacyRunID(sessionID)` and `legacyRunTagAssignmentID(sessionAssignmentID)` use
a fixed, documented UUID namespace and an implementation shared by migration
fixtures. A migration retry therefore derives the same IDs. Pre-protocol rows
use a fixed reserved `legacyImportOriginDeviceID`, revision zero, and nil
`lastAppliedMutationID`.

### Per-record mapping

| v1/v2 record | v3 result |
| --- | --- |
| Manual session | Same session ID/content; `timerRunID = nil`; no run created |
| Ended timed session | Same segment ID/content plus deterministic one-segment ended run; run start/end/zones/project/workspace/note copied |
| Active timed session | Same open segment plus deterministic running run; run start/zone/project/workspace/note copied; end remains nil |
| Timed session tags | Existing session assignments remain; deterministic equivalent run assignments are added with the same tag/name snapshot |
| Archived/missing project | IDs are preserved; migration does not resurrect or synthesize a project |
| Overlapping sessions | Every exact interval is preserved; existing overlap behavior remains visible in reports |
| Multiple active timed sessions | Every record receives a running run; first reconciliation returns review required and blocks mutation |
| Invalid legacy interval/raw value | Original values are preserved where SwiftData can decode them; the resulting run is review required |

`createdAt` and `updatedAt` copy from the legacy segment. `updatedTimeZoneID` uses
the legacy end zone when present, otherwise the start zone. A missing optional
end zone stays nil. Goal is nil. No migration stage samples the wall clock,
current time zone, random UUID provider, or current project/tag name.

### Required migration fixture expectations

Implementation is not accepted until fixtures assert all of the following:

| Fixture | Required assertions |
| --- | --- |
| Empty v1 and v2 | Zero runs/segments/assignments; schema opens twice |
| v1 manual ended | Exact original row; no run |
| v1 timed ended | Stable session ID and interval; one stable ended run; note retained |
| v1 timed active | Stable session ID/start; one stable running run/open segment |
| v2 timed tagged | Note and every assignment retained on segment and projected to run |
| v2 archived project/tag | IDs and name snapshots retained without reactivation |
| v2 overlapping timed/manual | All intervals retained and report totals/overlap flags unchanged |
| v2 multiple active | No row ended/deleted; reconciliation blocks mutation with every ID |
| Fractional timestamps | Sub-second start/end values and duration are bit-for-bit equivalent |
| DST/time-zone change | Absolute durations unchanged; both zone identifiers retained |
| Long running session | Original start retained; elapsed remains derived after reopen |
| Reopen migrated store | Counts and deterministic IDs remain unchanged; no duplicate run tags |

Before committing the migration implementation, capture the current v1/v2
fixture report output and compare it to v3 output by source session ID, project,
slice boundaries, duration, note, tag names, active flag, and overlap flag.

## 8. iPhone presentation after migration

- History shows one row per TimerRun plus one row per manual session. A run row
  displays its aggregate counted duration and Running/Paused/Ended state.
- Opening a run shows its ordered counted segments and paused gaps. A segment
  remains the source identity used by report drill-down.
- The completion screen edits the run-level note and tags and projects them to
  all counted segments atomically.
- Project correction is run-level. Segment correction changes counted
  boundaries only and cannot create a mixed-project run or overlapping owned
  segments.
- Existing external/UI routes containing a timed session ID resolve its
  `timerRunID` and open the containing run. Manual session routes are unchanged.
- Delete is run-level for timed work and session-level for manual work.

Reports still consume `TimeSessionSnapshot` segments. A future presentation
model may attach `timerRunID` for grouping, but `ReportSegmentID.sessionID` and
source drill-down remain stable.

## 9. Live Activity identity transition

New v3 Live Activities use `TimerRunRecord.id` as the stable identity and carry
the current run revision. Pause updates the same activity to a frozen elapsed
projection; Resume updates it; Switch ends the old run activity and requests a
new one at the shared boundary; End ends the matching run activity.

For one compatibility release, a pending pre-v3 `WellSpentStopRequest` that
contains a timed session ID resolves that session's `timerRunID` and invokes End
on the run using the request's original captured timestamp and zone. The handoff
file is acknowledged only after the v3 transaction succeeds. Foreground repair
removes old session-identity projections only after their source request has
been applied or safely classified.

## 10. Worked transition examples

### Start, pause, resume, end

```text
09:00 Start      run R running; S1 [09:00, nil)
10:15 Pause      run R paused;  S1 [09:00, 10:15)
10:30 Resume     run R running; S2 [10:30, nil)
12:00 End        run R ended;   S2 [10:30, 12:00)

counted = 2:45:00, paused = 0:15:00, wall = 3:00:00
```

### Switch while paused

```text
09:00 Start A    run A running; A1 [09:00, nil)
10:00 Pause      run A paused;  A1 [09:00, 10:00)
10:20 Switch B   run A ended at 10:20; run B/B1 start at 10:20

run A counted = 1:00:00, paused = 0:20:00
```

### Repeated End

```text
mutation M ends R at 12:00 and closes S2 at 12:00
retry M           returns revision and boundaries already persisted
new End request   returns alreadyEnded; it does not sample or replace 12:00
```

### Malformed multiple active migration

```text
legacy S1 [09:00, nil) -> running run R1 (preserved)
legacy S2 [09:30, nil) -> running run R2 (preserved)
reconcile                 -> reviewRequired([R1, R2]); no mutation permitted
```

## 11. Implementation and change control

- WAT-03 defines the mutation envelope, complete dedupe journal, observed base,
  acknowledgement, tombstone, and cross-device conflict policy.
- WAT-07 owns cross-platform Codable snapshots and pure reconciliation helpers.
- WAT-08 implements schema v3, migration, repositories, iPhone commands, and
  the compatibility presentation/Live Activity paths those commands require.
- WAT-17 refines grouped iPhone presentation with paired sync state.
- WAT-21 adds Watch-origin Live Activity reconciliation policy.

Changing segment authority, run identity, migration identity, revision rules,
annotation ownership, exact boundary rules, or report inputs requires an update
to this contract before implementation.

## 12. Acceptance checklist

- [x] Running, paused, and ended run/segment invariants are explicit.
- [x] Pause/Resume exclusion and exact Switch boundaries are specified.
- [x] Goal, summary, annotation, correction, deletion, and reconciliation
  semantics are specified.
- [x] v1/v2 migration mappings and fixture expectations are written before
  implementation.
- [x] Legacy IDs, intervals, notes, tags, projects, sources, and overlap/report
  behavior are retained.
- [x] The model uses scalar IDs and deterministic behavior compatible with
  future CloudKit constraints.
- [x] iPhone history, completion, report drill-down, routing, and Live Activity
  identity behavior are frozen.
