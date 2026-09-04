# WAT-14 — Live Watch metrics and goal progress

Status: Implemented and verified  
Linear: IDK-375  
Depends on: WAT-13  
Hands off to: WAT-15, WAT-18, WAT-20  
Last verified: September 2, 2026

## Outcome

An active timer now opens a three-page, vertically paged Watch experience:

1. **Elapsed** presents Running or Paused, exact billable elapsed, foreground
   project identity, goal progress or the no-goal state, and offline/pending
   sync status.
2. **Run** presents exact billable and paused duration, local start time, and
   segment count.
3. **Totals** presents the iPhone reporting engine's cached Today and This Week
   values, plus explicit iPhone, stale, or offline provenance.

The native vertical page style gives matching vertical-swipe and Digital Crown
navigation. It also reserves the horizontal axis for the WAT-15 control surface.

## Exact timing boundary

WatchTimerMetrics calculates billable elapsed from the active run's owned
segment half-open intervals at an injected presentation instant. Closed
segments never change. Only an open segment on a Running run advances. Paused
billable time therefore remains fixed while paused duration continues to
reflect the growing wall-clock gap.

The UI uses an ordinary SwiftUI timeline rather than owning a second timer
model. It refreshes each second in the foreground and allows the system to
throttle updates. In reduced luminance the requested cadence drops to one
minute; no command or persisted boundary depends on presentation refreshes.

All elapsed calculations use absolute Date instants. Midnight, time-zone, and
daylight-saving changes affect labels but cannot add or subtract billable time.
Durations remain readable beyond 99 hours.

## Goals and totals

Goal presentation derives progress, remaining time, reached state, and overtime
from exact billable elapsed. The progress bar caps visually at 100 percent while
the overtime label continues to report the full excess duration.

Today and This Week are never recomputed on the Watch. They are copied verbatim
from TimerTotalsSnapshot, which the iPhone creates with the reporting engine.
A snapshot older than five minutes, from a different local day in the
snapshot's time zone, or from an invalid time zone is marked cached/stale.
Offline totals are always labeled offline with their update time.

## Privacy, accessibility, and layouts

Reduced-luminance presentation replaces the project name with **Billable
timer**, dims project-specific decoration, keeps state and elapsed legible, and
slows decorative refreshes. A deterministic debug override exercises the same
redaction path in Simulator.

VoiceOver elements identify state, project, exact elapsed, goal, sync state,
each run metric, and both aggregate totals without relying on color or page
dots. The smallest supported 40 mm layout was checked with the largest dynamic
type and privacy redaction; primary status, elapsed, and identity stay legible,
while secondary content may scroll as specified by the UX contract. Standard
and paused states plus all three pages were visually checked on 46 mm.

## Verification

Pure tests cover running segment math, accumulated paused gaps, a paused timer
that never advances, no-goal/reached/overtime states, large durations, midnight,
daylight-saving fallback, exact phone-authored totals, stale/offline
classification, and privacy copy. UI tests cover vertical paging, every metric
page, persisted reconstruction, pending and offline markers, stale totals,
paused stability, goal variants, large duration, and redaction.

Run the focused architecture gate with:

    scripts/watch-metrics-check.sh

Run all production builds and regressions with:

    scripts/ci.sh
