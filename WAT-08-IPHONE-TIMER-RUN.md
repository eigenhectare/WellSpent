# WAT-08 — SwiftData v3 TimerRun and iPhone Command Boundary

Status: Implemented  
Applies to: iPhone persistence, timer commands, Track, history, completion,
reports, Live Activity, deep links, recovery, and erase-all  
Depends on: [WAT-02-TIMER-RUN-CONTRACT.md](WAT-02-TIMER-RUN-CONTRACT.md),
[WAT-07-SHARED-CONTRACTS.md](WAT-07-SHARED-CONTRACTS.md)  
Last reviewed: September 2, 2026

## Outcome

The iPhone now uses one stable `TimerRunRecord` for each user-visible timed
activity and report-authoritative `TimeSessionRecord` segments for counted
intervals. Pause closes a segment, Resume opens another, and reports continue
to sum exact segments. Manual sessions remain standalone and have no run ID.

All production Start, Pause, Resume, Switch, End, annotation, goal, delete, and
active-state reconciliation paths go through `TimerRunCommandService`. The old
session command boundary rejects run-owned segments so UI, deep links, and
future Watch receivers cannot bypass run invariants.

## Persistence and migration

`WellSpentSchemaV3` adds:

- `TimerRunRecord` with running, paused, and ended state; stable run identity;
  project/workspace; exact boundary zones; optional goal; canonical note;
  origin; revision; and last mutation identity.
- `TimeSessionRecord.timerRunID` for run-owned counted segments.
- `TimerRunTagAssignmentRecord` for canonical timed-work tags.
- `TimerOriginRecord` for the stable local command origin.

The migration remains sequential: v1 -> v2 -> v3. The v2-to-v3 custom stage is
deterministic and does not sample a clock, time zone, or random UUID source.
Each legacy timed session becomes a one-segment run using a namespaced UUID
derived from the unchanged session ID. Notes, tags, sources, project/workspace
IDs, fractional timestamps, zones, active state, archived references, overlaps,
and malformed multiple-active rows are preserved. Manual sessions receive no
run. Reopening an already-migrated store creates no duplicate rows.

## Atomic command behavior

Every logical mutation captures one boundary and zone, validates the complete
observed run shape, updates all affected rows, and calls `ModelContext.save()`
once. A save error rolls back the entire command.

| Command | Persisted effect |
| --- | --- |
| Start | Creates one running run and one open segment at the same instant. |
| Pause | Closes the only open segment and freezes counted duration. |
| Resume | Creates one new open segment without counting the paused gap. |
| Switch | Ends the old run and creates the new run/segment at one shared boundary in one save. |
| End | Closes an open segment if present and ends the run at the first accepted boundary. |
| Annotate | Updates canonical run note/tags and every legacy segment projection together. |
| Goal | Replaces or clears a positive finite counted-duration goal without changing time. |
| Delete | Deletes an ended run, its segments, and both tag projections together. |

Repeated mutation IDs return the already-persisted result without changing
timestamps or revisions. Repeated commands with new IDs return explicit
already-running, already-paused, already-ended, or already-current outcomes as
appropriate. A duplicate Switch resolves both saved runs even after restart.

## Reconciliation and recovery

Startup reconciliation is inspection-only. A healthy store yields no active
run, one running run with exactly one open segment, or one paused run with no
open segment. Unknown states, multiple non-ended runs, missing or extra open
segments, invalid boundaries, project/workspace/source mismatches, overlaps,
annotation divergence, invalid goals, and revision errors yield
`reviewRequired` with every implicated run and segment ID.

Malformed data is never silently ended, merged, or deleted. Timer mutations
remain blocked until explicit iPhone review. This preserves evidence for later
cross-device conflict handling.

## Product integration

- Track presents a paused run as active and offers Pause, Resume, and Stop from
  the stable run identity.
- History groups timed segments into one run row; manual sessions remain one
  row each. Run review exposes segments, counted/paused duration, annotations,
  origin/revision audit data, and deletion.
- Completion accepts an ended run ID while retaining legacy manual-session deep
  links. Old timed-session IDs resolve to their migrated run.
- Reports still consume session segments, so paused gaps are excluded and
  existing totals/source drill-down remain exact.
- Live Activity content uses the run ID, revision, counted seconds, current
  segment boundary, and running/paused/ended phase. A paused projection freezes
  its displayed duration.
- Lock Screen Stop handoff accepts both v3 run IDs and pre-v3 segment IDs.
- Erase-all removes runs, origins, run tags, segments, legacy tag assignments,
  tags, projects, preferences, and pending shared handoffs. An unavailable App
  Group is treated as having no shared container; real persistence failures are
  still surfaced.

## Verification contract

The focused regression suite covers:

- v1 and v2 migration for ended, active, tagged, archived, overlapping,
  long-running, fractional-timestamp, and malformed multiple-active fixtures;
- reopen/determinism and report/source equivalence;
- exact Start/Pause/Resume/Switch/End transitions, repeated delivery, restart,
  save rollback, annotation projection, goals, daylight-saving fallback, and
  active-state blocking;
- Live Activity running and paused projections;
- Track pause/resume, switch/completion, long-running/review states, and full
  local-data reset in iPhone UI automation.

Run the structural boundary independently with:

```sh
scripts/timer-run-check.sh
```

The repository-wide gate remains:

```sh
CI_SIMULATOR_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro Max,OS=latest' scripts/ci.sh
```

The production App Group round-trip requires the signed simulator portion of
that gate; an unsigned focused build intentionally cannot resolve the App Group
container.

Verification on September 2, 2026 completed with:

- the full `scripts/ci.sh` gate passing;
- 118/118 signed iPhone unit tests passing;
- 33/33 Watch XCTest cases and the Watch foundation test passing; and
- 9/9 focused WAT-08 iPhone UI flows passing on iPhone 17 Pro Max, iOS 26.5.

## Follow-on boundary

WAT-10 may adapt cross-device envelopes to this repository and command service.
It must not write SwiftData models directly. WAT-11 owns the durable complete
dedupe/conflict journal beyond the local `lastAppliedMutationID` optimization.
WAT-17 may refine paired-state presentation, and WAT-21 may add Watch-origin
Live Activity policy without changing segment authority or run identity.
