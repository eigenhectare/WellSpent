# WAT-10 — Production two-way Watch Connectivity

Status: Implemented and verified  
Linear: IDK-376  
Depends on: WAT-08, WAT-09  
Last verified: September 2, 2026

## Outcome

WellSpent now connects the production iPhone TimerRun store and the protected
Watch-local store through three deliberately different `WCSession` lanes:

| Lane | API | Payload | Contract |
| --- | --- | --- | --- |
| Fast | `sendMessage` | Watch mutation or iPhone acknowledgement | Best-effort latency optimization used only while reachable |
| Durable | `transferUserInfo` | The same immutable mutation, acknowledgement, or snapshot receipt bytes | At-least-once delivery across suspension and temporary unreachability |
| Replaceable | `updateApplicationContext` | Complete bounded iPhone canonical snapshot | Latest-state projection; never the sole copy of an unacknowledged mutation |

The disposable WC Probe remains isolated under `Spikes/WatchConnectivity` and
is not imported by either production app.

## Durability boundaries

The Watch considers a command locally successful only after its TimerRun
projection and immutable outbox row commit together in the WAT-09 store. A
transport error leaves that row pending; it does not turn the local command
into a false failure. Activation, reachability changes, explicit retry, and a
Watch Connectivity background wake all retry the same persisted bytes.

The iPhone receiver uses two saves:

1. Decode only the bounded stable header and save the mutation bytes, digest,
   origin, and sequence as `received`.
2. Resume received rows in causal order, apply through
   `TimerRunCommandService`, and save the domain change, resulting canonical
   head, terminal inbox result, and durable acknowledgement together.

Termination after step 1 resumes from the inbox. Failure during step 2 rolls
back both the TimerRun change and terminal receipt. Re-delivery of an exact
terminal mutation reuses its stored acknowledgement and never invokes the
command service again. Reuse of a mutation identity or origin sequence with
different content is rejected.

The four iPhone sync journals are introduced by additive SwiftData schema V4.
V3 is unchanged, and a focused on-disk migration regression proves that domain
data survives V3→V4 while the new journals begin empty.

## Snapshot and acknowledgement rules

- The phone increments its canonical generation for accepted mutations and
  other detected canonical content changes, then publishes one complete
  snapshot containing a bounded active catalog, active/recent run details,
  totals, recent acknowledgements, and origin watermarks.
- The Watch installs only an acceptable complete snapshot. Its store reapplies
  still-pending local mutations over the canonical projection, so a newer
  snapshot cannot erase offline work.
- A named acknowledgement is durably installed before the matching Watch
  outbox row is compacted. Lost acknowledgements therefore cause safe duplicate
  delivery, not duplicate TimerRuns or segments.
- After snapshot installation, the Watch queues a durable receipt for the
  exact snapshot ID and generation. The iPhone uses that receipt to retire
  acknowledgement rows that the paired Watch has demonstrably crossed.
- Transport diagnostics are fixed content-free codes. The production adapters
  do not log project names, tags, notes, envelope bytes, or stable origin IDs.

WAT-11 owns the richer user-facing divergent-history resolution workflow. This
milestone already preserves conflicting bytes and exposes blocking/review
states rather than silently overwriting them.

## Lifecycle wiring

The iPhone activates the coordinator when its root scene becomes active,
resumes its durable inbox, retries acknowledgements, and publishes a snapshot
after canonical refreshes. A Watch-applied mutation refreshes the iPhone model
and reconciles its Live Activity projection.

The Watch opens its local store before activating `WCSession`. The application
delegate forwards `WKWatchConnectivityRefreshBackgroundTask` instances to the
coordinator and completes them only after the session has no pending transfer
work. UI status distinguishes starting, reachable, offline-with-pending,
blocked, and unavailable states while keeping the local timer usable offline.

## Verification

The deterministic Simulator suite covers:

- reachable fast-path plus unreachable durable-path dispatch;
- duplicate mutation delivery and a lost acknowledgement;
- delayed predecessor followed by ordered convergence;
- termination after durable receipt but before application;
- rollback at the atomic domain/result/ack save boundary;
- exact acknowledgement compaction;
- snapshot receipt queuing, duplicate snapshot handling, and preservation of a
  newer pending Watch projection;
- stable bounded snapshots and V3→V4 migration.

Run the focused architecture gate with:

```sh
scripts/watch-connectivity-check.sh
```

Run all production builds and unit regressions with:

```sh
scripts/ci.sh
```

Simulator fakes prove the application protocol and persistence semantics, not
Apple's device-to-device delivery implementation. Physical acceptance must use
an Xcode-installed iPhone/Watch companion pair and follow
[WATCH-TESTING-GUIDE.md](WATCH-TESTING-GUIDE.md). A temporary unreachable state
is expected; `isReachable` controls only `sendMessage`, never whether a durable
command may be queued.
