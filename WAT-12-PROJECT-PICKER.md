# WAT-12 — Watch project picker and recovery states

Status: Done  
Linear: IDK-373  
Depends on: WAT-10  
Hands off to: WAT-13  
Last verified: September 2, 2026

## Outcome

The Watch now opens onto its cached active-project catalog when no timer is
running. The list scrolls with the Digital Crown and presents project glyph,
color, name, a primary Play action, and a separate options action. A tile tap
selects an open timer. Options offer open, 15-, 30-, and 60-minute choices plus
a Crown-friendly custom goal from 5 minutes to 8 hours.

Selection produces a typed `WatchStartRequest` containing the exact project and
optional goal. WAT-13 consumes it immediately at one timestamp-backed local
persistence boundary. WAT-12 intentionally does not create a TimerRun itself.

## Ordering and authority

The iPhone remains authoritative for project identity, membership, archive
state, and tombstones. The Watch owns only a bounded recent-selection index in
its local SwiftData store. Project order is:

1. active timer destination, when the picker is used from a timer transition;
2. valid Watch-local recents, newest first;
3. the remaining stable phone-provided catalog order.

SwiftData schema V2 adds only `RecentProjectRecord` and migrates from the shipped
V1 schema with a lightweight stage. Selecting a project updates recency in one
save. Installing a phone snapshot prunes recency for every missing or
tombstoned project before the new state is exposed, so the Watch cannot
resurrect an archived project.

## State policy

- A fresh cache with no canonical snapshot says **Finish setup**.
- A valid snapshot with no usable projects says **No active projects**.
- Cached projects remain selectable while offline or while transfers are
  pending; compact status badges explain that state without taking over.
- A protocol/build upgrade says **Update WellSpent** and blocks selection.
- A reconciliation conflict says **Review on iPhone** and blocks selection.
- Project creation, editing, archive, and restore remain on iPhone.

The picker does not use connectivity reachability as permission to work.
Conflict and explicit update guidance are the only WAT-12 blocking states.

## Accessibility and visual baseline

Project names and glyphs carry identity in addition to color. Primary actions
announce project identity, availability, and the immediate open-timer action.
Secondary actions announce their goal-selection consequence. All interactive
regions are at least 44 points high, names can use
two lines, and the vertical layout remains scrollable at accessibility text
sizes.

The first visual pass uses a black canvas, rounded tinted cards, high-contrast
Play circles, restrained borders, and separate ellipsis controls. It has been
visually checked on Series 11 and the 40 mm SE, including an injected
`accessibility5` text-size fixture. Product feedback can revise styling without
changing the ordering, state, accessibility, or start-request contracts.

## Deterministic fixtures

Debug UI tests can launch `-ui-test-watch-fixture` with `setup`, `empty`,
`populated`, `archived`, `long-names`, `offline`, `pending`, `conflict`, or
`unsupported`. `-ui-test-largest-text` injects SwiftUI's largest accessibility
category without depending on simulator preferences.

Tests cover durable recency, V1-to-V2 migration, tombstone pruning, unknown and
duplicate recent IDs, open and preset-goal selection, separate setup/empty
recovery, cached offline/pending use, blocking conflict/update states, long and
duplicate names, missing emoji, and the 40 mm largest-text layout.

Run the focused architecture gate with:

```sh
scripts/watch-project-picker-check.sh
```

Run all production builds and regressions with:

```sh
scripts/ci.sh
```
