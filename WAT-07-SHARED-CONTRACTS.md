# WAT-07 — Shared Watch Contracts and Reconciliation

Status: Complete  
Linear: IDK-369  
Depends on: WAT-03, WAT-06  
Last updated: September 1, 2026

## Outcome

`WellSpentWatchContracts` is a single native Xcode target with iOS and watchOS
destinations. Both platforms compile the same source into a static framework,
and both execute the same `WatchContractTests.swift` suite. iOS executes it as a
standalone test bundle; watchOS also compiles that standalone bundle and
executes the source through the Watch app's hosted test bundle because Xcode
does not expose standalone Watch test bundles to Watch Simulator destinations.
The module is a wire and decision boundary only; it does not read or write
application state.

## Contract surface

- protocol 1.0 and domain schema 3 compatibility values;
- stable project, tag, timer-run, and timer-segment snapshots;
- complete timer-ledger heads, tombstones, totals, conflict summaries, receipt
  watermarks, update guidance, and replaceable snapshot envelopes;
- immutable mutation envelopes with mutation ID, stable random origin ID,
  monotonic origin sequence, exact captured instant and time zone, canonical
  causal base, predecessor, observed run/revision, tagged action, and SHA-256
  payload digest;
- acknowledgement and exact snapshot-receipt values;
- tagged Start, Pause, Resume, Switch, End, Annotate, Set Goal, Resolve Conflict,
  and Recovery Proposal actions with every affected entity ID allocated before
  persistence;
- pure mutation and snapshot reconciliation classifications for apply,
  duplicate, missing predecessor, stale input, invalid input, or iPhone review;
- deterministic segment, project, and tag presentation ordering.

## Wire rules

Canonical bytes are JSON encoded with sorted keys, unescaped slashes, and dates
as integer-capable milliseconds since 1970. Mutation digests cover the complete
versioned envelope except the digest itself. The implementation uses an
in-module pure-Swift SHA-256 routine so the contract remains Foundation-only.

Decoding rejects mutation payloads above 256 KiB and snapshot payloads above
1 MiB before parsing. Unknown optional JSON keys are ignored. An unsupported
required protocol major or schema produces `unsupported_protocol`; unknown
required actions produce `unsupported_action`. Malformed, oversized, invalid,
or digest-mismatched input yields a fixed content-free `ContractWireError` and
never includes project, tag, or note content.

## Causal rules

1. The exact mutation ID and digest return the stored outcome as a duplicate.
2. Reusing a mutation ID with other bytes, or reusing one origin sequence for a
   different mutation identity, requires review.
3. A first offline mutation applies only against its exact snapshot ID and
   canonical generation and exact observed active-run identity/revision.
4. A successor waits when its predecessor is absent. It applies only when that
   predecessor was applied by the same origin, its result remains the current
   canonical head, and the successor observed that result.
5. Timestamps never break causal ties.
6. Older snapshots are stale. The same generation with another snapshot ID, or
   a newer snapshot that contradicts pending local mutations, requires review.

## Integration boundary

The production iPhone and Watch targets depend on the static contract module.
Existing iPhone schema-v2 timer behavior remains unchanged. WAT-08 adds the
iPhone schema-v3 command adapter, WAT-09 adds the Watch store/outbox, and WAT-10
connects both sides through Watch Connectivity.

## Verification

Run:

```sh
xcodegen generate --spec project.yml
scripts/watch-contract-check.sh
```

The gate fails if the target imports anything beyond Foundation or references
SwiftData, ActivityKit, WatchConnectivity, UserNotifications, or SwiftUI. It
then performs Debug and Release builds plus test-bundle compilation for both
iOS Simulator and watchOS Simulator. CI runs the complete shared test suite on
an iPhone simulator and an Apple Watch simulator, proving that both platforms
produce the same golden mutation and snapshot bytes.

Completion evidence from September 1, 2026:

- contract gate passed for iOS/watchOS Debug and Release plus both standalone
  test-bundle builds;
- 17/17 shared contract tests passed on iPhone 17 Pro Simulator;
- the same 17/17 tests passed through the production Watch host on Apple Watch
  Series 11 (46mm) Simulator, plus the Watch foundation test;
- the full CI suite passed, including Watch packaging/privacy validation and
  all 103 pre-existing iPhone tests;
- strict Swift formatting, privacy audit, shell syntax, and `git diff --check`
  passed.
