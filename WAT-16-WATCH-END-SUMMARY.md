# WAT-16 — Persisted Watch end summary

Status: Implemented and verified  
Linear: IDK-379  
Depends on: WAT-15  
Hands off to: WAT-17, WAT-23  
Last verified: September 2, 2026

## Outcome

The Watch now presents the complete end summary only after the End command has
committed the ended run and immutable outbox mutation locally. In the frozen
reading order it shows project, exact billable duration, paused duration,
start, end, optional goal result, segment count, sync state, note, tags, and
Done. All duration values are recalculated from the exact persisted segment
boundaries rather than copied from transient UI state.

The saved run is readable and dismissible without entering text or selecting a
tag. Done returns to the project picker. If a draft exists, Done explicitly
offers to keep editing or discard only the unsaved annotation; it never deletes
or reopens the ended run.

## Note and tag editing

The Note row opens a standard watchOS `TextField`. Dictation, Scribble, and the
paired/system keyboard are therefore owned by watchOS, including cancellation
and input failure behavior; WellSpent implements no custom keyboard or speech
capture. Notes are whitespace-normalized, empty text clears a note, and the
existing 1,000-character contract limit is enforced before persistence.

The Tags row lists the active iPhone-authored tag catalog. A tag already
assigned to the run remains visible as **Archived tag** if it has since left the
active catalog. Note-only edits preserve that historical identity, while the
user may explicitly remove it. Unknown, never-assigned tag IDs remain invalid.

## Local-first annotation boundary

`WatchTimerAnnotationBoundary` validates that the target is durably ended,
normalizes note and tag input, captures one save date and time zone, builds the
complete `AnnotateTimerAction`, and invokes one persistence closure. It imports
no SwiftUI, WatchKit, or Watch Connectivity API.

`WellSpentWatchRuntime` admits only one annotation save at a time. The existing
`WellSpentWatchStore.performLocalCommand` transaction updates the recently
ended projection and appends the immutable outbox envelope together. Success
UI and haptic feedback occur only after that transaction returns. Offline state
never blocks editing, and transport retries the already-persisted envelope.

If local persistence fails, the ended run and outbox remain unchanged. The
failure states that the run is still saved and offers Try Again or Discard
Edit. A retry is locally safe because a failed transaction leaves no partial
mutation, while transport redelivery is idempotent by immutable mutation ID and
digest.

## Cross-device conflict behavior

The annotation command uses the existing frozen causal policy. If the iPhone
edits the same ended run after the Watch's base snapshot, the late Watch
annotation is retained as a review branch and acknowledged as a stale-base
conflict; timestamps never select a winner. Exact redelivery returns the stored
conflict acknowledgement and cannot overwrite the phone revision or create a
second conflict.

On successful phone application, the existing `TimerRunCommandService`
atomically projects the canonical note and tag assignments to the TimerRun and
all of its legacy report segments. iPhone history therefore continues to group
the Watch-created work as one coherent run while exact reports sum its segments.

## Lifecycle, accessibility, and privacy

End and annotation mutations survive process termination in the protected,
backup-excluded Watch store. Leaving the summary with no annotation, cancelling
system text entry, discarding a draft, or terminating the app cannot alter the
ended boundaries. A canonical recently ended fixture also verifies summary
reconstruction after relaunch.

The visual and accessibility trees follow the same semantic order. Every
editable row and action has a word label, symbol, state, hint, and 44-point
minimum target. Long project, note, and tag content wraps or scrolls rather than
shrinking the primary duration beyond readability. Production diagnostics add
no note, tag name, project name, or duration logging.

## Verification

Fixed-boundary tests cover note normalization and clearing, stable tag order,
historical tag preservation, unknown tag rejection, the note limit, unchanged
input, exact capture, atomic rollback, durable relaunch, and pending outbox
reconstruction. Phone tests cover concurrent late edits and duplicate delivery.

Watch UI automation covers exact displayed totals, no-annotation Done, system
text-entry cancellation, offline annotation and busy state, failure/discard,
historical tags, long content, and relaunch.

Run the focused architecture gate with:

    scripts/watch-summary-check.sh

Run all production builds and regressions with:

    scripts/ci.sh

