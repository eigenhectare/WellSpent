# WAT-17 — iPhone companion integration

Status: Implemented and verified  
Linear: IDK-377  
Depends on: WAT-11, WAT-16  
Hands off to: WAT-21, WAT-22  
Last verified: September 2, 2026

## Phone presentation and controls

Track labels Watch-origin runs using the persisted transport origin, not a
guess based on the absence of a phone origin record. Paused runs Resume,
Switch, and Stop through the existing TimerRun command service. Report totals
sum exact counted segments; paused gaps never become billable time.
Completion and History retain one row per run with segment drill-down, note,
tags, origin, and an inspectable run ID. Existing no-Watch Track stays simple.

Sync copy distinguishes saved phone data from a pending Watch acknowledgement
or snapshot receipt. A phone edit advances the ledger even when transport is
unavailable. Sending a packet is not a confirmation. The receipt-confirmed
label says **Last saved changes confirmed by Watch**, not that an offline
Watch has no newer changes. Settings states that unseen offline work cannot
be known to the phone and offers Retry Watch Sync.

Conflict deliveries now refresh the app even when no canonical mutation was
applied. Receipt and connectivity changes also update the visible status.

## Explicit conflict review

Track and Settings open the preserved-time review. The iPhone version exposes
its existing details; each latest reconstructable Watch origin chain exposes
project, state, exact counted time, boundaries, note, tags, and segment details.
Unreconstructable input stays in the audit and cannot silently replace a run.

The three available outcomes are:

- Keep iPhone: retain canonical runs and exclude Watch-only changes from reports.
- Use Watch: replace involved canonical runs with the selected Watch version,
  retaining its running/paused state and annotations.
- Keep both: retain the phone runs and save a separate Watch version. The user
  reviews the explicit end boundary for any unfinished Watch run. Both versions
  count fully, including overlapping time; the confirmation warns about this.

All outcomes have a second confirmation screen. `PhoneConflictResolutionPlan`
captures immutable replacement IDs, exact boundaries, a resolution mutation ID,
and the complete observed conflict. It validates the whole result before
confirmation. If another branch arrived meanwhile, the save rejects the stale
preview. Store failure retains both versions and stays in confirmation for
retry. No action chooses time based on device origin or clock ordering. Exact
trim/merge payloads remain supported by the WAT-11 domain API; this UI offers
the three complete-version choices above rather than a new timeline editor.

After a durable resolution, the app refreshes reports and reconciles Live
Activity from the resulting active run. WAT-21 owns further cross-surface
Live Activity hardening.

## Handoff and links

The Watch conflict screen advertises a privacy-limited Handoff activity carrying
only a conflict UUID. The iPhone declares that activity and routes it to review;
`wellspent://review/<UUID>` uses the same route. Stale links cannot mutate data.
The Watch also names the manual Track action, because Handoff availability is
system-controlled. Handoff is not a command to force-open the iPhone.

This follows Apple's [Implementing Handoff in Your App](https://developer.apple.com/documentation/foundation/implementing-handoff-in-your-app).
No notes, names, durations, search indexing, or public indexing are included in
the activity. Physical Handoff delivery is reserved for WAT-24; simulator tests
verify the route, declarations, and code paths, not radio delivery.

## Erase and privacy

The additive V6 schema reuses V5 unchanged and adds one content-free reset
generation. Erase removes user records, conflict branches, snapshots, inboxes,
acknowledgements, notes, tags, preferences, and Lock Screen handoffs. Only a
numeric reset fence remains. Fresh phone generations stay higher than the
old Watch cache. Delayed pre-erase envelopes are rejected before their user
content enters the durable inbox, and cannot restore erased work.

This is an iPhone erase, not a promise to remotely wipe an offline Watch.
Settings and confirmation tell the user to remove WellSpent from the Watch to
erase its separate cache and unsent work, then reinstall it after the phone
erase. A Watch that retained rejected pre-erase commands may remain blocked
until that reinstall. This deliberately avoids silently deleting unseen
Watch-only work. Onboarding and privacy copy explain optional paired, offline,
device-to-device operation without suggesting a server or cloud account.

## Verification

Run `scripts/watch-companion-check.sh` for architecture/test coverage checks,
and `scripts/ci.sh` for clean Debug/Release builds, privacy checks, migrations,
Watch regressions, and iPhone unit/integration tests.

`WatchCompanionUITests` covers paused Watch Resume/Switch/End, exact paused
exclusion, grouped history, each conflict outcome, failed-save recovery,
relaunch, cancellation, and largest accessibility text. The existing iPhone
UI suite covers onboarding, reports, editing/deletion, settings, erase, and
Live Activity flows. Simulator/fake-transport results are not physical
Watch Connectivity or Handoff acceptance evidence.

### September 2 verification results

- Clean CI passed: Debug/Release builds, privacy and architecture gates,
  142/142 iPhone unit/integration tests, and 70/70 Watch tests.
- All eight new companion UI tests passed together on the final build.
- The complete 51-case iPhone UI sweep initially passed 47 cases. The four
  remaining cases all passed on focused reruns after corrections: an explicit
  fresh fixture process, accessible/high-contrast Pause controls, and scrolling
  to the optional note editor below the expanded summary. This is combined
  sweep-and-rerun evidence, not a claim that the initial full run was green.
- All six accessibility audits were covered, including the successful active,
  completion, and recovery reruns. At accessibility text sizes, timer buttons
  stack vertically; Pause/Resume uses high-contrast primary text.
- Normal and largest-text conflict confirmation screenshots were inspected.
- The final Release rebuild, formatting/lint, diff validation, and focused
  companion/reconciliation gates passed after the UI refinements.
