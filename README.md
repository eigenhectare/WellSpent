# WellSpent

Native, paired iPhone and Apple Watch time tracker. The iPhone app includes first-launch
onboarding, timestamp-backed Start/Pause/Resume/Switch/Stop, completion notes and
configurable tags, emoji/color project identity, manual corrections, overlap
warnings, and exact Day, Week, and Project reports with source-session
drill-down. Lock Screen and every
Dynamic Island presentation family are implemented with a privacy-first label,
system-derived elapsed time, and a true Stop control. Persisted timer commands
now drive the production ActivityKit lifecycle, including durable Lock Screen
Stop handoff, completion routing, foreground repair, and long-session recovery.

The authoritative iPhone store is the versioned SwiftData v6 schema, with a tested
sequential migration from the oldest v1 store. One stable TimerRun groups every
counted segment across pauses, while reports continue to sum exact segments.
Views invoke the project, timer-run, and standalone-session command boundaries
rather than mutating records.
The store remains on-device, explicitly opts out of device backups, and uses no
account, server, analytics, tracking, or CloudKit synchronization.
Reporting is a pure calendar-aware engine whose segments preserve source
identity and handle local midnight, configurable weeks, daylight-saving days,
active sessions, and fully counted overlaps.

See [DEVELOPMENT.md](DEVELOPMENT.md) for project generation, build, and test
commands. The repository also includes a secrets-free pull-request CI workflow
whose local entry point is `scripts/ci.sh`.

Implementation contracts and scope boundaries are documented in
[CORE-EXPERIENCE.md](CORE-EXPERIENCE.md), [REPORTING.md](REPORTING.md),
[LIVE-ACTIVITY-LIFECYCLE.md](LIVE-ACTIVITY-LIFECYCLE.md),
[WAT-01-WATCH-UX-CONTRACT.md](WAT-01-WATCH-UX-CONTRACT.md),
[WAT-02-TIMER-RUN-CONTRACT.md](WAT-02-TIMER-RUN-CONTRACT.md),
[WAT-03-WATCH-SYNC-CONTRACT.md](WAT-03-WATCH-SYNC-CONTRACT.md),
[WAT-04-CONNECTIVITY-SPIKE.md](WAT-04-CONNECTIVITY-SPIKE.md),
[WAT-06-WATCH-FOUNDATION.md](WAT-06-WATCH-FOUNDATION.md),
[WAT-07-SHARED-CONTRACTS.md](WAT-07-SHARED-CONTRACTS.md),
[WAT-08-IPHONE-TIMER-RUN.md](WAT-08-IPHONE-TIMER-RUN.md),
[WAT-09-WATCH-LOCAL-STORE.md](WAT-09-WATCH-LOCAL-STORE.md),
[WAT-10-WATCH-CONNECTIVITY.md](WAT-10-WATCH-CONNECTIVITY.md),
[WAT-11-RECONCILIATION.md](WAT-11-RECONCILIATION.md),
[WAT-12-PROJECT-PICKER.md](WAT-12-PROJECT-PICKER.md),
[WAT-13-IMMEDIATE-START.md](WAT-13-IMMEDIATE-START.md),
[WAT-14-LIVE-METRICS.md](WAT-14-LIVE-METRICS.md),
[WAT-15-WATCH-CONTROLS.md](WAT-15-WATCH-CONTROLS.md),
[WAT-16-WATCH-END-SUMMARY.md](WAT-16-WATCH-END-SUMMARY.md),
[WAT-18-WIDGETS.md](WAT-18-WIDGETS.md),
[WAT-19-SYSTEM-ACTIONS.md](WAT-19-SYSTEM-ACTIONS.md),
[WAT-20-GOAL-ALERTS.md](WAT-20-GOAL-ALERTS.md),
[WAT-21-LIVE-ACTIVITY.md](WAT-21-LIVE-ACTIVITY.md),
[WAT-22-CI-AUTOMATION.md](WAT-22-CI-AUTOMATION.md),
[WATCH-TESTING-GUIDE.md](WATCH-TESTING-GUIDE.md),
[RELEASE-HARDENING.md](RELEASE-HARDENING.md),
[ACCESSIBILITY.md](ACCESSIBILITY.md), [PRIVACY.md](PRIVACY.md), and
[SUPPORT.md](SUPPORT.md). Beta and
release operations are captured in [BETA-TESTING.md](BETA-TESTING.md),
[RELEASE-CANDIDATE-VALIDATION.md](RELEASE-CANDIDATE-VALIDATION.md), and
[APP-STORE-RELEASE.md](APP-STORE-RELEASE.md).

## Apple Watch foundation

`project.yml` now generates the production `WellSpentWatch` companion app,
`WellSpentWatchWidgets` extension, and focused Watch unit/UI-test targets. The
iPhone app embeds the Watch app, and the Watch app embeds its widget. The two
Watch bundles share `group.com.drewreilly.wellspent.watch` only for local Watch
state; cross-device synchronization will use Watch Connectivity.

Regenerate and validate the entire production pair without signing credentials:

```sh
xcodegen generate --spec project.yml
scripts/watch-foundation-check.sh
```

The foundation check compiles both Watch test bundles, performs Debug and
Release watchOS Simulator builds and unsigned watchOS device-SDK builds, and
verifies the nested iPhone → Watch → widget package, bundle identifiers,
versions, App Group, and privacy manifests. CI executes both unit suites and
focused iPhone/Watch UI manifests, including disk-backed process-restart tests.
See [WAT-22-CI-AUTOMATION.md](WAT-22-CI-AUTOMATION.md) for the gate, evidence
format, failure guards, Release fixture checks and clean-checkout command.
The production pair now exchanges complete canonical snapshots, immutable
Watch commands, durable acknowledgements, and snapshot receipts. The Watch UI
reports starting, reachable, offline/pending, blocked, and unavailable sync
states while its protected local timer remains usable offline.

## Shared Watch contracts

`WellSpentWatchContracts` is one Foundation-only, multi-platform static module
compiled from the same source for iOS and watchOS. It defines schema-v3 project,
tag, run, segment, mutation, acknowledgement, receipt, tombstone, totals, and
snapshot values. It also owns deterministic sorted-key JSON, payload limits,
pure-Swift SHA-256 integrity checks, stable privacy-safe errors, and pure causal
reconciliation decisions. It deliberately imports none of SwiftData,
ActivityKit, WatchConnectivity, UserNotifications, or SwiftUI.

Run the contract gate independently:

```sh
scripts/watch-contract-check.sh
```

The same golden mutation and snapshot fixtures plus duplicate, stale-base,
tie, divergent-history, malformed, and oversized-payload tests execute on both
iPhone and Apple Watch simulators in CI. The production iPhone TimerRun command
boundary and schema-v4 durable transport journals plus schema-v5 conflict
audit records are connected to the
Watch-local store through Watch Connectivity.

## Watch-local persistence

`WellSpentWatchStore` is the production Watch-only SwiftData boundary. A local
timer command and its immutable outbox envelope commit in one save; retry
metadata, acknowledgement inbox rows, quarantine bytes, snapshot receipts,
installation origin, protocol version, catalog, active/recent timer state, and
totals survive process termination and reboot. The store is protected,
backup-excluded, bounded, and capable of reconstructing a corrupt projection
from the last canonical snapshot plus valid outbox chain.

The Watch widget links the same static module but receives only a minimal status
projection from a configuration with saving disabled. Run
`scripts/watch-store-check.sh` for the architectural boundary gate; the Watch
simulator test bundle exercises atomic failure, restart, retry, acknowledgement,
quarantine, corruption, protocol-upgrade, capacity, erase, and privacy paths.

## Production Watch Connectivity

Reachable commands use `sendMessage` only as a fast duplicate; immutable Watch
mutations and iPhone acknowledgements use `transferUserInfo` for durable
at-least-once delivery, while a complete bounded canonical snapshot uses
`updateApplicationContext`. The phone persists inbound bytes before applying
them and commits each TimerRun change, terminal receipt, canonical head, and
acknowledgement atomically. Exact redelivery is therefore safe after suspension,
termination, reordering, or a lost acknowledgement.

Run `scripts/watch-connectivity-check.sh` for the focused production-boundary
gate. Simulator tests deterministically cover the protocol and failure windows;
physical transport validation follows [WATCH-TESTING-GUIDE.md](WATCH-TESTING-GUIDE.md).

## Deterministic reconciliation

Safe one-sided offline chains apply in causal order. Divergent histories are
preserved under one stable review identity with their exact canonical and
Watch branches; neither timestamps nor delivery order selects a winner. An
explicit iPhone resolution can retain, separate, trim, merge, or end reviewed
runs, and a conflict-resolution tombstone clears the Watch freeze only after a
newer authoritative snapshot arrives. Run
`scripts/watch-reconciliation-check.sh` for the focused persistence and
architecture gate.

## Watch project picker

When no timer is active, the Watch presents its cached project catalog as a
Digital Crown-scrollable, recent-first list with primary open-timer and
secondary time-goal actions. Watch-local selection recency survives relaunches,
while the iPhone remains authoritative for catalog membership and tombstones.
Cached projects remain usable offline and during pending sync; setup, empty,
protocol-update, and conflict states have distinct recovery guidance. Run
`scripts/watch-project-picker-check.sh` for the focused architecture gate. The
first visual pass and its deterministic fixtures are documented in
[WAT-12-PROJECT-PICKER.md](WAT-12-PROJECT-PICKER.md).

## Immediate Watch Start

Selecting a project or confirming a time goal captures and atomically persists
the Watch timer boundary immediately; there is no pre-start delay. The running
state appears and one haptic plays only after the run, first segment, and
durable outbox mutation commit locally. Offline starts remain fully usable and
show **Saved on Watch** until delivery. Run `scripts/watch-start-check.sh` for
the focused gate; the persistence and recovery contract is documented in
[WAT-13-IMMEDIATE-START.md](WAT-13-IMMEDIATE-START.md).

## Watch timer controls

An active timer has a horizontally adjacent control surface with large labeled
End, Pause/Resume, and New actions. Every action captures one exact boundary and
commits the local projection plus durable outbox mutation before haptic or
success UI. End requires confirmation and routes to the persisted-summary
handoff; New uses a recent-first picker and atomically ends the old run as the
new one starts. Run `scripts/watch-controls-check.sh` for the focused gate; the
interaction, failure, and App Intent reuse boundaries are documented in
[WAT-15-WATCH-CONTROLS.md](WAT-15-WATCH-CONTROLS.md).

## Watch end summary

After End commits locally, the Watch shows exact segment-derived billable and
paused durations, boundaries, goal result, segment count, and sync state. Notes
use standard watchOS dictation/Scribble/keyboard entry, while tags come from the
active iPhone-authored catalog and preserve already-assigned historical IDs.
Annotation and its durable outbox entry save atomically, including offline;
failure never changes the ended run. Run `scripts/watch-summary-check.sh` for
the focused gate; the lifecycle, accessibility, and conflict rules are
documented in [WAT-16-WATCH-END-SUMMARY.md](WAT-16-WATCH-END-SUMMARY.md).

## iPhone Watch companion

Track shows Watch origin and receipt-based sync status while retaining the
existing paused-run controls. Conflict review preserves both versions and
requires an explicit, previewed choice before changing report totals. Watch
Handoff and review links route to the same iPhone screen. Erase includes a
content-free reset fence against delayed old Watch messages and explains how
to remove the Watch's separate cache. See
[WAT-17-IPHONE-COMPANION.md](WAT-17-IPHONE-COMPANION.md) and run
`scripts/watch-companion-check.sh` for the focused gate.

## License

Copyright © 2026 WellSpent contributors.

WellSpent is licensed under the [GNU Affero General Public License v3.0](LICENSE).
