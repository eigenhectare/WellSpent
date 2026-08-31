# Exact reporting — RPT-01 through RPT-05

## Pure engine

`ReportingEngine` depends only on Foundation value types and the pure overlap
detector. It accepts snapshots, an explicit half-open report selection,
`Calendar`, and `now`, and returns chronological `ReportSegment` values.

For every source session it:

1. Resolves an active end to the injected `now` without changing the source.
2. Intersects the source interval with the selected half-open range.
3. Asks the supplied calendar for each local day interval and splits at its
   real end boundary.
4. Preserves source session/project IDs, source timestamps, note, active state,
   and overlap state on every segment.

Totals and groups reduce those same segments. There is no duration cache,
rounding, deduplication, overlap exclusion, or 24-hour clamp.

## Reports UI

- Day shows the exact total, project totals, chronological segments, notes,
  provisional active labels, overlap explanations, and empty state.
- Week derives its interval from the injected user calendar, including locale,
  time zone, first weekday, and minimum-days rules. It shows the week total,
  daily totals, and project totals.
- Project offers every active or archived project and an inclusive local-day
  date selector whose internal query remains half-open.
- Every aggregate is a navigation link to a live `ReportSelection`. The
  drill-down recomputes against current snapshots, displays its exact segment
  sum, and links every segment to session review/correction. Edits and deletes
  therefore update an already-open drill-down without hidden adjustments.

## Automated evidence

`ReportingEngineTests` covers clipping, half-open intervals, source identity,
cross-midnight allocation, 23-hour spring days, 25-hour fall days, configurable
week starts/minimum days, active sessions with injected `now`, overlaps above
24 hours, adjacent non-overlaps, time-zone rebucketing without timestamp
mutation, project filters, aggregate equality, and empty ranges.

`ReportingInvariantTests` independently computes clipped source durations and
checks the engine's total, source totals, project groups, and local-day groups
against them. Its deterministic calendar matrix includes US and British locale
week rules, a year boundary, New York and London DST, Lord Howe's half-hour DST,
Chatham's 45-minute time-zone offset, and Kathmandu's 45-minute offset. It also
covers multi-day active and completed sessions, exact 23/25-hour day buckets,
overlaps, project filters, sessions outside the selection, and totals above 24
hours. Every returned segment must stay inside the half-open selection and one
real local calendar day while preserving its source identity and timestamps.

UI automation covers empty/current/cross-midnight/overlap/archived fixtures,
Day/Week/Project aggregates, source navigation, and recalculation after a
source deletion. Fixed-clock domain coverage remains the authoritative edge
case evidence; the UI never reimplements report arithmetic.
