# WAT-09 — Protected Watch-local cache, inbox, and durable outbox

Status: Complete  
Linear: IDK-371  
Depends on: WAT-07  
Last updated: September 1, 2026

## Outcome

The production Watch app now owns a minimal SwiftData database in the
Watch-local `group.com.drewreilly.wellspent.watch` App Group. Opening the app
initializes a random installation origin and validates or recovers the store.
The widget opens the same database with saving disabled and receives only a
small status projection; it cannot access command methods or a model context.

This App Group is local to the Watch. It is not cross-device synchronization.
WAT-10 will move the durable bytes in this store through Watch Connectivity.

## Transaction boundary

`WellSpentWatchStore` is a watchOS static module layered on
`WellSpentWatchContracts`. Its private SwiftData schema has five record types:

- one metadata/projection record containing the random origin, next sequence,
  supported protocol/schema, installed canonical head, current local run,
  current/recent segments, active catalog, tombstones, totals, and blocking
  state;
- one independent outbox record per immutable encoded mutation, including its
  digest and retry metadata;
- acknowledgement inbox records retained for deduplication;
- byte-preserving quarantine records for terminal conflict/invalid outcomes or
  corrupt mutations;
- independent durable snapshot-receipt records.

A local Start, Pause, Resume, Switch, End, Annotate, or Set Goal validates the
current run invariants, allocates the mutation identity and monotonic origin
sequence, updates the projection, and inserts the immutable outbox record in
one `ModelContext.save()`. The command returns success only after that save.
An injected or real save failure rolls back both changes.

The reducer preserves the WAT-02 rules: one open segment while running, none
while paused/ended, positive closed durations, ordered non-overlapping
segments, a shared Switch boundary, and one revision increment per accepted
logical mutation. Exact boundaries and captured time-zone identifiers are
stored; presentation does not infer or repair them from wall-clock guesses.

## Inbox, compaction, and restart

- Delivery attempts update separate retry fields and never rewrite immutable
  envelope bytes or causal identity.
- An acknowledgement is saved in the same transaction that compacts its exact
  named outbox record.
- Only `applied` and `duplicate` compact normally. Conflict, invalid, and
  unsupported outcomes first move the exact envelope and acknowledgement into
  quarantine and save a blocking reason.
- An acknowledgement identity mismatch is retained as a blocking receipt while
  the original outbox item remains intact.
- Unacknowledged mutation and snapshot-receipt records are never age- or
  capacity-evicted. A full bounded queue rejects new work atomically.
- Restart reconstructs running, paused, pending-sync, quarantine, conflict, and
  retry state from persisted timestamps and records.

## Snapshot and corruption behavior

Complete compatible snapshots replace the cached canonical projection and
queue a durable named receipt. Stale snapshots are ignored. Generation ties or
newer snapshots identified as contradicting pending work are saved as blocking
review states without overwriting the local run. Pending local mutation state
is retained when a newer non-contradictory catalog snapshot is installed.

On startup, the store validates the singleton identity, protocol/schema,
projection invariants, mutation digests, origin sequences, and record limits.
If the projection bytes are corrupt, it reconstructs them from the last valid
canonical snapshot and then replays the valid outbox chain. A corrupt outbox
entry is quarantined byte-for-byte, later mutations remain untouched, and new
timer mutation is blocked. An unsupported future major version is left intact
and rejected rather than rewritten.

## Privacy and limits

The App Group directory and all current store files use complete protection
until the first unlock after boot and are excluded from device backup. The
database has no CloudKit configuration, account, network, logging, analytics,
or tracking dependency. Cache limits are enforced for projects, tags,
tombstones, acknowledgements, mutations, quarantine entries, and receipts. It
mirrors only the active/recent Watch working set, not full notes or history.

## Verification

Run:

```sh
xcodegen generate --spec project.yml
scripts/watch-store-check.sh
xcodebuild -project WellSpent.xcodeproj -scheme WellSpentWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=latest' \
  -only-testing:WellSpentWatchTests test
```

The WAT-09 suite covers atomic save failure/disk-full injection, complete timer
transitions and causal predecessors, crash-before-transfer restart, retry
metadata, named acknowledgement compaction, conflict quarantine, identity
collision, projection reconstruction, corrupt-envelope quarantine, stale and
contradictory snapshots, capacity rejection, protocol upgrade refusal, erase,
read-only widget status, and backup exclusion.
