# WAT-15 — Watch timer control surface

Status: Implemented and verified  
Linear: IDK-378  
Depends on: WAT-11, WAT-14  
Hands off to: WAT-16  
Last verified: September 2, 2026

## Outcome

An active run now has a horizontally adjacent, Workout-style control surface.
Swipe right from any live metric page to reach three large labeled actions:

- **End** presents a destructive confirmation containing the current exact
  billable duration.
- **Pause** closes the one open counted segment; the control then becomes
  **Resume**, which opens exactly one new segment.
- **New** opens a recent-first destination picker and switches projects at one
  shared old-end/new-start boundary.

The horizontal surface contains the existing three-page vertical metric view,
so vertical swipes and Digital Crown navigation remain dedicated to Elapsed,
Run, and Totals. Symbols, words, shapes, and VoiceOver labels identify every
control without relying on color.

## Command boundary

`WatchTimerControlBoundary` is the single UI-independent adapter for Pause,
Resume, Switch, and End. Each method validates the expected active shape,
captures one `Date` and time-zone identifier, allocates any required identities,
constructs the complete `TimerMutationAction`, and invokes one persistence
closure. It does not import SwiftUI, WatchKit, or Watch Connectivity, so WAT-19
App Intents can reuse it directly.

The runtime is the only production caller connected to
`WellSpentWatchStore.performLocalCommand`. That existing store transaction
updates the local projection and writes the immutable outbox envelope in one
save. Only after it returns successfully does the runtime refresh visible
state, play a haptic, update local project recency for Switch, and ask transport
to retry pending bytes. Phone reachability never gates a timer action.

## Repeated input and failure behavior

The runtime admits one control operation at a time and disables all three
buttons while it is committing. A rapid second tap therefore cannot enter the
store. The store reducer independently rejects repeated or stale state changes,
so there are two layers preventing duplicate segments, duplicate End
boundaries, or multiple active runs.

A failed Pause, Resume, or End keeps the prior run visible and authoritative.
A failed Switch rolls the old run, open segment, new run, and outbox entry back
together and presents **Couldn't switch**. Retry captures a fresh attempted
boundary; Cancel leaves the original run unchanged. Offline and pending-sync
runs retain every normal control.

Switch destinations exclude the current project and any iPhone-authored
tombstone. A single-project catalog presents a clear empty state and keeps the
current timer running.

## End handoff

After a durable End, the Watch routes to a persisted read-only handoff showing
Saved, project, exact billable duration, sync state, and Done. This proves that
success UI follows the local commit and provides the navigation seam for
WAT-16. WAT-16 owns the complete end summary, note/tag editing, and dictation;
those capabilities are intentionally not duplicated here.

## Verification

Fixed-clock tests cover exact Pause, Resume, running End, paused End, and Switch
boundaries; paused-gap exclusion; fresh run/segment identities; repeated Pause;
same-project rejection; Switch rollback; outbox atomicity; and reconstruction
of an ended pending run after store recreation.

Watch UI automation covers horizontal navigation, 44-point-plus controls,
busy/disabled input, running-to-paused-to-running presentation, End
confirm/cancel, persisted summary routing, successful Switch, failed Switch,
offline controls, single-project catalogs, archived destinations, and existing
conflict blocking. The primary controls fit without scrolling on 40 mm and 46
mm simulator displays.

Run the focused architecture gate with:

    scripts/watch-controls-check.sh

Run all production builds and regressions with:

    scripts/ci.sh

