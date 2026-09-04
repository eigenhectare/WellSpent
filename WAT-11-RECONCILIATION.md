# WAT-11 — Deterministic reconciliation and conflict resolution

Status: Implemented and verified  
Linear: IDK-372  
Depends on: WAT-10  
Last verified: September 2, 2026

## Outcome

WellSpent now treats divergent phone and Watch histories as durable branches,
not as a last-writer-wins race. Safe causal chains still apply automatically.
Stale bases, identity/sequence collisions, invalid boundaries, recovery
proposals, and concurrent mutations create one stable review-required record.
Both apps freeze timer mutation until an explicit iPhone resolution commits.

## Persistence and audit boundary

SwiftData schema V5 adds four purely additive reconciliation records while
reusing every V4 domain and transport model unchanged:

- bounded canonical snapshot history for observed-base reconstruction;
- stable conflict identity, canonical branch, reason, involved IDs, and
  resolution audit;
- immutable incoming mutation bytes plus the reconstructed Watch branch;
- project, tag, run, and conflict-resolution tombstones.

Conflict creation, retained mutation bytes, terminal inbox outcome,
acknowledgement containing the same `conflictID`, and canonical generation
advance commit together. Diagnostics and tombstones contain no project name,
tag name, note, or raw user content.

## Resolution semantics

`PhoneWatchSyncStore.resolveConflict` accepts the frozen
`ConflictResolutionPayload`. It can retain a canonical branch, preserve both
branches as separate runs, or install explicitly reviewed replacement runs and
exact segments for trim, merge, or end decisions. The whole target ledger is
validated before one save:

- IDs and segment ownership are unique;
- every boundary is finite, increasing, and non-overlapping;
- project/workspace ownership is consistent;
- tags and replacement identities exist or are collision-free;
- at most one non-ended run exists and it matches `chosenActiveRunID`.

Superseded run rows remain physically durable but are excluded from reports and
commands through a run tombstone. They are physically compacted only after the
paired Watch acknowledges a snapshot at or beyond the resolution generation.
The conflict and its raw branch audit remain retained after compaction.
Replaying the same resolution mutation returns its original head; a different
resolution cannot rewrite an already-resolved conflict.

## Watch convergence

Conflict acknowledgements quarantine the exact local envelope and block new
commands. A conflict snapshot carries the same review identity. A newer
resolved snapshot must include its conflict-resolution tombstone; installing
that snapshot replaces the local projection and clears the freeze. Catalog and
run tombstones are applied before exposing the cached projection, so archived
entities cannot be resurrected.

## Verification

Deterministic tests cover concurrent starts, every stale timer action, clock
skew, missing/delayed predecessors, mutation and origin-sequence collisions,
branch reconstruction, keep-both, merge/trim/end replacement payloads,
idempotent resolution, multiple conflict rounds, tombstone crossing, Watch
freeze/unfreeze, exact report boundaries, and V4-to-V5 migration.

Run the focused gate with:

```sh
scripts/watch-reconciliation-check.sh
```

Run all production builds and regressions with:

```sh
scripts/ci.sh
```
