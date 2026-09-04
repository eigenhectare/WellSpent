# WAT-13 — Immediate persisted Watch timer Start

Status: Implemented and verified  
Linear: IDK-374  
Depends on: WAT-08, WAT-09, WAT-12  
Hands off to: WAT-14  
Last verified: September 2, 2026

## Outcome

Selecting a project now starts billable time immediately. One boundary object
captures the timestamp and time-zone identifier once, allocates the run and
first-segment identities, and sends the complete Start action to the
Watch-local store. The run, segment, projection, causal mutation, and durable
outbox entry commit in the store's existing atomic transaction.

There is no pre-start screen or artificial delay. The Watch changes to its
persisted running state and plays one confirmation haptic only after the local
save succeeds. Phone reachability is not part of the success boundary.

## Start contract

1. A project tile or goal choice invokes one `WatchStartRequest`.
2. `WatchTimerStartBoundary` captures one `Date` and one time-zone identifier.
3. It creates one `StartTimerAction` with fresh run and segment UUIDs.
4. `WellSpentWatchStore.performLocalCommand` atomically persists the projected
   run, first open segment, immutable mutation, and outbox entry.
5. The runtime refreshes exclusively from the persisted store state, gives one
   success haptic, and asks Watch Connectivity to transfer pending work.
6. Recent-project ordering is updated after the timer commit as non-authoritative
   picker metadata; a recency failure cannot turn a successful timer into a
   false failure.

The first successful Start owns the state. A rapid repeated Start encounters
the already-active projection and cannot add another run, segment, or outbox
entry.

## Failure and offline behavior

A local persistence failure leaves the projection without a running timer and
presents **Couldn't start** over the still-usable picker. **Try Again** retries
the same project and goal as a new persistence attempt; **Cancel** returns to
the picker. Neither path emits a success haptic before a durable commit.

An offline Start follows the same local transaction. The running screen says
**Saved on Watch** and keeps the mutation in the durable outbox. Reachable but
unacknowledged work says **Pending sync**. Both are normal states rather than
errors, and a later acknowledgement removes the marker.

## Current running surface

WAT-13 supplies the minimum persisted running presentation needed to prove the
transition: Running state, timestamp-derived elapsed time, project identity,
optional goal, and sync state. WAT-14 owns the complete paged metric experience,
Digital Crown navigation, totals, goal progress, and final visual refinement.

## Verification

Deterministic tests cover the exact captured timestamp, time zone, goal, run
identity, segment identity, mutation identity, rapid repeated Start, atomic
save failure, cached offline Start, pending sync, and reconstruction from a
persisted active-run fixture. The pre-existing store suite also verifies that a
committed command survives container recreation and that save failure rolls
back the run and outbox together.

Run the focused architecture gate with:

```sh
scripts/watch-start-check.sh
```

Run all production builds and regressions with:

```sh
scripts/ci.sh
```
