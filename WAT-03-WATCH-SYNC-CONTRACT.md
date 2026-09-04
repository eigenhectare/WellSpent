# WAT-03 — Offline Command, Acknowledgement, and Conflict Contract

Status: Frozen for transport spike and implementation  
Applies to: Watch-origin timer commands, iPhone canonical application, project
and timer snapshots, durable acknowledgements, conflict review, and future
CloudKit-compatible mutation identity  
Depends on: [WAT-02-TIMER-RUN-CONTRACT.md](WAT-02-TIMER-RUN-CONTRACT.md)  
Last reviewed: September 1, 2026

## 1. Authority and delivery guarantee

The Watch is an independent durable writer while the iPhone is unreachable.
The iPhone store is the canonical merged record after synchronization. Delivery
is at least once: duplicate, delayed, reordered, and background delivery is
normal and must be safe.

A Watch command is successful for the user after one transaction persists the
local TimerRun/segments and its immutable outbox envelope. Reachability and an
iPhone reply are not part of local success. The Watch removes no outbox entry
until it has durably saved an acknowledgement that names that mutation UUID.

The iPhone persists an inbox/deduplication record before it attempts to apply a
mutation. Application, resulting canonical generation, outcome, and outgoing
acknowledgement are then persisted atomically. A crash at any point resumes from
the durable inbox or returns the prior outcome; it does not apply twice.

```text
WATCH                                      IPHONE
local command + outbox (one save)
      |
      +-- sendMessage (fast duplicate) ------> persist inbox receipt
      +-- transferUserInfo (durable) --------> validate causal base
                                                   |
                                                   +-- apply + receipt outcome
                                                   +-- ack outbox (one save)
      <------- transferUserInfo ack ---------------+
      <------- latest application context snapshot+
save ack + compact named outbox entry
```

## 2. Stable identities and causal base

### Device origin

Each installation owns a random, stable `originDeviceID` stored with its local
database and protected cache. It never derives from a user name, device name,
serial number, advertising identifier, or hardware identifier. Reinstall or a
replacement Watch creates a new origin. An origin allocates a strictly
increasing `originSequence` in the same transaction that inserts its outbox
record; gaps are tolerated, reuse is not.

The tuple `(originDeviceID, originSequence)` must map to exactly one mutation
UUID and payload digest. Reuse with different content is quarantined as a
protocol conflict.

### Canonical timer head

Every iPhone-authored snapshot carries a `TimerLedgerHead`:

| Field | Meaning |
| --- | --- |
| `snapshotID` | UUID of the complete replaceable snapshot |
| `canonicalGeneration` | Monotonic iPhone counter incremented once per accepted logical timer/catalog mutation or conflict resolution |
| `activeRunID` | Nil or the canonical non-ended run |
| `activeRunRevision` | Nil or that run's revision |
| `headMutationID` | Mutation that produced this head, when applicable |

A Watch mutation records the last received `snapshotID` and generation. The
first offline mutation has no predecessor. Each later offline mutation names
the immediately preceding local mutation UUID. This produces a causal chain
that the phone can apply in order even though every member began from the same
last-known canonical generation.

```text
canonical snapshot S generation 40
  M1 Start  (base S/40, predecessor nil, sequence 12)
  M2 Pause  (base S/40, predecessor M1,  sequence 13)
  M3 Resume (base S/40, predecessor M2,  sequence 14)
```

The iPhone may apply M1 only when S/40 is still its head. It may then apply M2
and M3 because their predecessors were accepted in that chain. It never guesses
causality from timestamps or arrival order.

## 3. Mutation envelope

`TimerMutationEnvelope` is Codable and immutable after its outbox transaction.
The payload is encoded with sorted keys for test fixtures and stored with its
SHA-256 digest. The digest detects storage/transport corruption; it is not an
authentication claim.

| Field | Type | Contract |
| --- | --- | --- |
| `protocolMajor` / `protocolMinor` | `UInt16` | Transport contract version |
| `schemaVersion` | `UInt16` | Sender's domain snapshot schema |
| `mutationID` | `UUID` | Global idempotency identity |
| `originDeviceID` | `UUID` | Stable installation origin |
| `originSequence` | `UInt64` | Monotonic sequence allocated with outbox insert |
| `capturedAt` | `Date` | One exact action boundary or annotation capture time |
| `capturedTimeZoneID` | `String` | IANA zone identifier captured with the action |
| `baseSnapshotID` | `UUID?` | Last complete canonical snapshot observed by origin |
| `baseCanonicalGeneration` | `UInt64` | Generation of that snapshot; zero only before first setup snapshot |
| `predecessorMutationID` | `UUID?` | Previous local unacknowledged mutation in this origin chain |
| `observedRunID` | `UUID?` | Run the sender believed non-ended before the action |
| `observedRunRevision` | `Int64?` | Revision of that run before the action |
| `action` | tagged payload | Exact command and every preallocated affected entity ID |
| `payloadDigest` | 32 bytes | Digest over the versioned envelope content excluding this field |

The action cases are:

- `start(runID, segmentID, projectID, durationGoalSeconds?)`
- `pause(runID, openSegmentID)`
- `resume(runID, newSegmentID)`
- `switch(fromRunID, openSegmentID?, toRunID, toSegmentID, projectID,
  durationGoalSeconds?)`
- `end(runID, openSegmentID?)`
- `annotate(runID, normalizedNote?, tagIDs)`
- `setGoal(runID, durationGoalSeconds?)`
- `resolveConflict(conflictID, resolutionPayload)` — iPhone-origin only
- `recoveryProposal(runSnapshot, segmentSnapshots, priorMutationDigests)` —
  never auto-applied; opens iPhone review

Every ID required to apply Start, Resume, or Switch is generated before the
Watch transaction. A retry therefore cannot create a second run or segment.
Timestamp-free actions still carry `capturedAt` for audit and revision metadata;
only boundary actions use it to count or end time.

The envelope contains project and tag IDs, not their names. The iPhone validates
all referenced entities against its canonical catalog. Notes are present only
for explicit annotation commands and are never logged.

## 4. Acknowledgement and receipt models

### `MutationAcknowledgement`

Every terminal inbox outcome creates a durable acknowledgement:

| Field | Meaning |
| --- | --- |
| `acknowledgementID` | Stable UUID for acknowledgement retry/deduplication |
| `mutationID`, `originDeviceID`, `originSequence` | Exact command being acknowledged |
| `outcome` | `applied`, `duplicate`, `conflict`, `invalid`, or `unsupported` |
| `canonicalSnapshotID`, `canonicalGeneration` | Head after the outcome was persisted |
| `conflictID` | Present only for a review-required branch |
| `reasonCode` | Fixed content-free code; no project/note/tag text |
| `acknowledgedAt` | iPhone persistence time; not a timer boundary |

`applied` and `duplicate` allow the Watch to compact the named outbox entry.
`conflict`, `invalid`, and `unsupported` allow compaction only after the Watch
atomically moves the immutable envelope into its retained quarantine/history
store and saves the corresponding blocking state. No terminal outcome silently
discards the command bytes.

The snapshot also includes, per origin, a contiguous received watermark and a
bounded list of recent `(sequence, mutationID, outcome)` receipts. A watermark
is an optimization for detecting missing transfers. It never replaces the
named acknowledgement required for Watch outbox removal.

### `SnapshotReceipt`

After atomically installing a complete snapshot, the Watch queues a durable
receipt containing its origin ID, the exact snapshot ID, and canonical
generation. This allows the iPhone to retire acknowledgement rows and catalog
tombstones only after the currently paired Watch proves it has crossed them.
Sending a receipt is not a timer mutation and cannot advance the timer head.

## 5. Snapshot contract

`TimerSnapshotEnvelope` is a complete, replaceable projection sent through
application context. It contains:

- supported protocol/schema range and capability flags;
- `TimerLedgerHead`;
- active project and active tag snapshots needed by Watch workflows;
- project/tag tombstones newer than the Watch's last receipt;
- the canonical non-ended run with all its segments, or nil;
- the most recently ended Watch-relevant run needed for a pending summary;
- cached Today/This Week totals with calculation instant and calendar zone;
- conflict ID/state when timer mutation is blocked;
- recent acknowledgement receipts and per-origin watermarks;
- content-free minimum-app-version/update guidance.

Application context replacement is safe because each snapshot is complete for
the Watch working set. It is never the only copy of a mutation,
acknowledgement, conflict branch, or tombstone that has not crossed a confirmed
snapshot receipt.

The Watch installs a snapshot only when it is protocol-compatible and newer
than its last installed canonical generation, or when it has the same
generation and the exact expected snapshot ID. An older/different snapshot is
recorded as stale and ignored. A newer snapshot does not erase unacknowledged
local commands; it is reconciled against their causal chain first.

### Tombstones

Project, tag, run, and conflict-resolution tombstones contain entity type, ID,
canonical generation, and deletion/resolution time. They contain no project
name, note, or tag name. Tombstones are not compacted based on wall-clock age
alone. The phone may compact one after the currently paired Watch acknowledges
a snapshot newer than its generation. A newly installed/replacement Watch
always receives a full catalog snapshot and cannot resurrect phone data because
Watch catalog snapshots are never authoritative inbound writes.

## 6. Watch durable outbox

1. Allocate origin sequence, create the immutable envelope, apply the local
   command, and insert one outbox record in one transaction.
2. Display success only after the transaction commits.
3. If reachable, call `sendMessage` with the persisted bytes as a latency fast
   path. Always enqueue the same bytes with `transferUserInfo` for durability.
4. Track attempts separately from the immutable envelope. Retry on activation,
   reachability changes, explicit user retry, and bounded backoff. Delivery
   attempts never rewrite IDs, sequence, base, predecessor, or boundary.
5. Save a received acknowledgement before removing/moving an outbox record.
6. Compact applied/duplicate entries only by the named mutation acknowledgement.

Outbox entries are independent records, not one rewritable array/file. Each
stores encoded bytes, digest, mutation ID, origin sequence, created time,
attempt metadata, and state. A corrupt entry is quarantined byte-for-byte when
possible, blocks further timer mutation, and offers a `recoveryProposal` built
from the still-durable local run/segments. It is never skipped so later
mutations can appear causally valid.

If local domain persistence succeeds but outbox insertion cannot commit, the
whole command rolls back and no success state is shown. If transport calls
fail, the committed command remains pending and usable offline.

## 7. iPhone durable inbox and deduplication

Inbound processing has two persistence phases:

1. Validate the stable outer header and digest enough to identify the mutation.
   Save an inbox row as `received` before domain application.
2. In a new atomic transaction, validate protocol/capability, device-sequence
   identity, causal base, and WAT-02 invariants; then apply or quarantine the
   command, store its terminal receipt, advance the canonical head only when
   applied, and insert an acknowledgement outbox row.

On restart, every `received` row is resumed. A previously terminal mutation ID
returns the stored outcome and queues the same logical acknowledgement without
calling the command service. Matching mutation UUID with a different digest,
or matching origin sequence with a different mutation UUID/digest, becomes a
review-required protocol conflict.

Inbox rows and acknowledgements are retained until a Watch snapshot receipt
proves the outcome crossed back to that origin. Conflict rows and their raw
envelopes remain until explicit resolution and a later receipt.

## 8. Transport roles

| Watch Connectivity API | Required role | Forbidden assumption |
| --- | --- | --- |
| `sendMessage` | Optional foreground/reachable fast path for a mutation or ack already persisted | Reachability, reply, or error handler is not durability or correctness |
| `transferUserInfo` | Durable queued path for every mutation, acknowledgement, and snapshot receipt | Delivery order and exactly-once execution are not assumed |
| `updateApplicationContext` | Replaceable latest complete project/timer/totals/capability snapshot | It is never the sole copy of a command, ack, or unresolved conflict |
| `transferFile` | Not used in v1 protocol | No command journal is moved as an opaque bulk file |

Both sides activate their connectivity session at startup and process callbacks
through one serialized persistence boundary. UI work and diagnostic logging are
not performed on the Watch Connectivity delegate queue.

## 9. Automatic application versus review

### Causally safe

- Exact duplicate `mutationID` and digest: return stored outcome.
- Redelivery of `(originDeviceID, originSequence)` mapped to the same mutation:
  return stored outcome.
- First offline mutation whose base snapshot/generation still matches the
  canonical head.
- Later offline mutation whose predecessor is terminal `applied` in the same
  origin chain and whose observed run/revision matches that predecessor's
  result.
- Retry of End with the same mutation ID: preserve the first boundary.
- Old acknowledgement or snapshot: save receipt diagnostics if useful, but do
  not roll back state.
- A current application-context snapshot that only confirms mutations already
  reflected in the local chain.

### Review required

- Phone head changed after the Watch base and the incoming command is not an
  exact duplicate.
- Concurrent phone/Watch Start, Pause, Resume, Switch, End, goal, annotation,
  correction, or deletion from the same base.
- A missing/rejected predecessor, origin-sequence collision, payload digest
  mismatch, mixed project/run IDs, invalid boundaries, or divergent annotation
  projection.
- A newer snapshot that contradicts any unacknowledged local mutation.
- Recovery proposal from a corrupt outbox or previously unknown origin branch.

Even apparently commutative changes are not merged in v1. This keeps the policy
small and makes every exact boundary user-reviewable. Later expansion requires
deterministic tests and a contract revision.

## 10. Conflict preservation and resolution

When review is required, the iPhone persists:

- the canonical branch snapshot and ledger head;
- every inbound envelope/raw payload and causal relationship;
- the reconstructed Watch run and all exact segment boundaries;
- fixed reason codes and receive times;
- a stable `conflictID`.

It does not select a winner by `capturedAt`, `receivedAt`, device clock skew, or
last writer. It sends an acknowledgement naming each retained mutation and a
blocking snapshot. Phone and Watch then reject Start, Pause, Resume, Switch,
End, goal, and annotation mutations with `Review on iPhone` until resolution.

The iPhone repair UI may let the user keep one branch, keep both as separate
ended runs, trim/merge exact segments, or choose/end an active run. Resolution
is one explicit `resolveConflict` mutation containing the chosen IDs and
boundaries. It validates WAT-02 invariants, creates tombstones for superseded
branch entities, advances the canonical generation, acknowledges all retained
mutations, and distributes a complete resolved snapshot. Nothing is physically
deleted before the resolution and snapshot receipt are durable.

## 11. Clock skew and diagnostics

`capturedAt`, its zone, receiver persistence time, origin sequence, causal base,
and optional clock-skew estimate are retained for diagnosis. Causality comes
only from snapshot generation, predecessor mutation, and stored receipts. Wall
clock order never decides which interval to delete, shorten, extend, or win.

Production diagnostics use fixed event/reason codes plus protocol versions,
counts, boolean reachability, and opaque IDs when necessary. They exclude
project names, tag names, notes, user-entered text, and raw mutation payloads.
Debug spike logs may print synthetic fixture identifiers only.

## 12. Protocol and app upgrades

- The stable outer header exposes major/minor version, mutation ID, origin, and
  payload digest before action decoding.
- An unknown major version or unsupported action is persisted as raw
  quarantined input and acknowledged `unsupported` when the header is readable.
- A minor-version receiver may ignore unknown optional fields only when it fully
  understands the action and declared capability set.
- A Watch never offers a command absent from the phone snapshot's capabilities.
- A newer incompatible snapshot is retained raw, does not replace the last
  compatible cache, blocks timer mutation, and shows the canonical update copy
  from WAT-01.
- Updating either app resumes pending inbox/outbox processing with the original
  immutable bytes and IDs.

## 13. Reinstall, unpair, and replacement Watch

A replacement or reinstalled Watch gets a new origin ID and sequence. It must
receive a full compatible iPhone snapshot before enabling mutation. It never
continues another origin's sequence or treats an old cache as canonical.

Commands already transferred to the phone survive Watch loss in the iPhone
inbox even if not yet applied. Commands that existed only in storage on a lost,
erased, or unpaired Watch cannot be recovered without a server or Watch backup;
the product must state this limitation in the WAT-05 retention matrix. The
protocol never pretends otherwise. If old-origin commands arrive after a
replacement is paired, the phone persists them and routes them to review rather
than applying them into the new origin's active chain.

## 14. Deterministic scenario matrix

| Scenario | Expected result |
| --- | --- |
| Both apps reachable | `sendMessage` may apply first; queued duplicate returns same receipt; one domain mutation |
| iPhone suspended/terminated | `transferUserInfo` eventually creates inbox row; apply/ack after wake; Watch remains pending meanwhile |
| Ack lost | Watch retains outbox; redelivery returns stored receipt and boundary |
| Receiver crash after inbox save | Row remains `received`; restart applies once |
| Receiver crash after apply transaction | Terminal receipt/ack exists with applied state; restart does not apply again |
| Out-of-order M3, M1, M2 | M3 pending on predecessor; M1 then M2 apply; M3 applies only after M2 terminal |
| Duplicate mutation | Same terminal result and generation; no new segment/revision |
| Stale snapshot | Ignored; local chain and last newer snapshot unchanged |
| New snapshot confirms chain | Install snapshot, persist named acks, compact corresponding outbox rows |
| New snapshot contradicts chain | Preserve local branch; create/block on conflict |
| Concurrent offline Starts | Preserve phone and Watch runs/segments; review required; no timestamp winner |
| Phone End vs Watch Pause | Preserve both commands and boundaries; review required |
| Same End mutation retried | First persisted boundary wins; duplicate ack |
| Unsupported major | Preserve raw input; unsupported ack; update-required state; no domain mutation |
| Origin sequence collision | Quarantine both mapping details; protocol conflict |
| Corrupt Watch outbox row | Quarantine bytes; block later chain; recovery proposal goes to review |
| Watch replaced | New origin waits for full snapshot; late old-origin commands go to review |
| Project/tag deleted offline | Watch command referencing tombstone goes to review/invalid outcome; no silent reassignment |
| Clock changed backward | No wall-clock ordering merge or clamping; invalid boundary goes to review |

Every scenario test asserts domain record counts and exact boundaries, inbox and
outbox states, acknowledgement identity, generation/revision changes, and the
absence of project/note/tag text in diagnostics.

## 15. Spike and implementation handoff

- WAT-04 must use this exact envelope/header shape and prove the three transport
  roles on paired physical devices. Observed platform behavior can amend this
  contract only through an explicit recorded decision.
- WAT-07 implements Codable contracts, fixture encodings, and pure causal
  reconciliation.
- WAT-09 implements protected cache, origin identity, outbox, quarantine, and
  snapshot installation.
- WAT-10 implements both connectivity delegates and acknowledgement outboxes.
- WAT-11 implements the full scenario matrix and iPhone conflict records.

The future CloudKit design must reuse `mutationID`, `originDeviceID`,
`originSequence`, run revision, and causal-base concepts or explicitly migrate
them. It must not add an unrelated second identity system.

## 16. Acceptance checklist

- [x] Envelope, origin sequence, causal base, action IDs, timestamp/zone,
  schema/protocol versions, digest, and acknowledgements are frozen.
- [x] `sendMessage`, `transferUserInfo`, and `updateApplicationContext` have
  non-overlapping correctness roles.
- [x] Watch outbox, iPhone inbox/dedupe, retry, snapshots, tombstones,
  receipts, quarantine, and compaction rules are explicit.
- [x] Duplicate, delayed, reordered, background, restart, stale, unsupported,
  corruption, and replacement-Watch behavior is testable.
- [x] Divergent phone/Watch history preserves all counted time and blocks
  mutation until explicit iPhone resolution.
- [x] Clock skew alone never determines a winning or rewritten boundary.
