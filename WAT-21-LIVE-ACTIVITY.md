# WAT-21 — Canonical Live Activity projection

Linear: IDK-382. Working state: In Review; autonomous implementation verified.
This document records implementation and local evidence; it does not certify
physical mirroring, device authentication, or distribution.

## Canonical ownership and ordering

- Every new ActivityKit identity is a TimerRun UUID. The compatibility fields
  `activityID` and `sessionID` remain decodable; `runID` is the semantic alias.
- Start, Pause, Resume, Switch, End, conflict resolution, and Watch receipts save
  through the existing canonical commands before publishing a desired activity.
  End uses the saved count, end boundary, and revision, not a pre-save snapshot.
- `setDesiredState` runs synchronously during refresh, fencing suspended old
  operations before their successor task is scheduled. One drain owns every
  ActivityKit write; every suspension is followed by a generation check before
  another side effect. A superseded request cannot create its run afterward.
- Missing/ambiguous active state never selects an arbitrary run. Read failure is
  represented as unavailable, not as an empty database that deletes good cards.
- Erasure commits before its projection. Retained completed cards are also
  eligible for privacy refresh and deletion. Starting a newer run removes old
  cards; it does not end the new run.
- An unchanged content payload does not spend another ActivityKit update.
  Running elapsed text uses a system date anchor, not an extension timer loop.

## Stop intent and recovery

The intent captures a content-free protected request with run UUID, expected
revision, exact stop time, and time zone. It does not update/end ActivityKit.
A process-local lock plus a protected advisory file lock serialize first-write
and acknowledgement across the app and intent processes. The first pending
request for a run wins; retries do not move its timestamp.

The app bridge consumes the durable queue when ready. Startup/foreground retry
also consumes it, covering cold launch and absent bridges. The canonical store
checks identity/revision and persists End before the projection changes:

- A completed run is idempotent and cannot stop a newer active run.
- A different revision or deleted run is explicitly rejected and acknowledged,
  with a message directing the person to current controls.
- Persistence/conflict failures retain the request for recovery.
- Projection success cannot erase an unapplied-handoff recovery message.
- Old asynchronous operations cannot replace newer recovery UI state.

Existing requests without an expected revision remain readable for the
compatibility release. They still pass the run-identity and boundary checks.

## Delayed delivery and system surfaces

An existing iPhone Live Activity can update/end during a background Watch
receipt. A missing activity defers creation until iPhone foreground and recovers
there automatically. WatchConnectivity receipt is not treated as an
OS-executed LiveActivityIntent, and no push server or fabricated background
execution privilege is introduced. This follows [Apple's Activity
documentation](https://developer.apple.com/documentation/activitykit/activity).

A pending acknowledgement/snapshot receipt is labeled as pending rather than
confirmed. The iPhone cannot infer an unseen offline Watch mutation.
A single known canonical conflict run gets a generic, noninteractive review
card, with count frozen at the review boundary across refreshes. Multiple
ambiguous active runs suppress projection. Canonical time remains preserved.

The Lock Screen and expanded Dynamic Island expose revision-bound Stop.
Compact/minimal presentations show status and open the activity through normal
system interaction; long-press expansion provides controls. Running/paused/
review links open the tracker; completed links target the completed run.

Apple automatically mirrors iPhone Live Activities and budgets delivery to
Watch. The supplemental small family therefore identifies itself as the
**iPhone copy** and offers a route to the current Watch app instead of another
potentially stale Watch timer/control surface. Native Watch widgets remain the
watch-local timer surface. Mirrored links cannot replace or recreate a run.
The Watch opts into activity launches using
`WKSupportsLiveActivityLaunchAttributeTypes`. OS/user-pinned cards cannot be
guaranteed absent; this is not a claim to disable Apple's mirroring.
See [Apple's Watch Live Activity session](https://developer.apple.com/videos/play/wwdc2024/10068/).

Project names are removed from outgoing content unless explicitly enabled,
and always removed for review. The actual shared presentation views also honor
privacy redaction and hide names with reduced luminance. Notes/tags never
enter activity state or Stop requests.

## Local verification

- Full iPhone unit suite: 161 passed on iPhone 17 Pro Max, iOS 26.5.
  Final expanded Watch-receipt coverage is in
  `/tmp/wat21-watch-receipt-verified.log`: Start/Pause/Resume/Switch/End,
  duplicate receipt, pending confirmation, and post-save content all pass.
- Focused iPhone UI suite: five passed, covering background/End persistence,
  projection failure/retry, disabled Live Activities, privacy preference, and
  long-running recovery. Final combined 161-unit/five-UI rerun:
  `/tmp/wat21-final-tests.log`.
- Watch suite: 109 passed (84 XCTest plus 25 Swift Testing), including mirrored
  link rejection/routing. `/tmp/wat21-watch-tests.log`.
- Rendered actual production presentation views: 25 family/state combinations
  plus two privacy/Always On variants. Height bounds passed for full/small
  families. Attachments: `.derivedData/WAT21-Visuals`. Representative running,
  paused, ended, review, compact/minimal, small, and privacy images were inspected.
  These are hosted view renders, not proof of system placement or physical AOD.
- Final combined Release simulator build passed: `/tmp/wat21-release-final.log`.
- Unsigned combined iPhone/Watch device-SDK Release build passed:
  `/tmp/wat21-device-release.log`. This is not a signed archive/install.
- Source/Release-binary privacy audit, negative privacy fixtures, existing widget/
  intent/goal structural gates, new Live Activity structural gate, and diff
  whitespace checks passed. `/tmp/wat21-final-lint.log` has zero diagnostics.
  Generated Watch app/widget intent metadata was rechecked against the final
  Release product. All test/build handles were terminal before this checkpoint.

### Failed attempts retained

The first compile exposed an outdated companion test adapter; it was updated
to the new desired-state protocol. The first unsigned suite passed 49/50 cases
but correctly failed its actual App Group check (`suiteUnavailable`).
Two subsequent signed iPhone 17 Pro attempts stalled before XCTest loaded.
Their live processes were inspected and explicitly canceled, not restarted
solely after an observation timeout. No simulator was erased/unpaired.
Standard simulator signing on iPhone 17 Pro Max passed the complete suite,
including actual App Group and intent handoffs. The app bridge also preserves
SwiftUI-owned StateObject initialization. The precise host-loading cause was
not isolated; the canceled attempts are not passing evidence.

The expanded five-action receipt fixture initially mixed a fresh snapshot with
an offline predecessor from an older base. The protocol correctly froze it as
a conflict. The fixture now models commands observing the delivered current
snapshot (no unacknowledged predecessor); all actions pass. Production causal
reconciliation was not relaxed to make this test pass.

## Remaining evidence

Actual locked-screen authenticated intent invocation, Dynamic Island/system
placement, Watch small-card tap routing and delayed mirroring, physical
Always On, and hours-long/offline behavior remain WAT-23/24 gates. Unit calls
to `perform()` test handoff logic, not OS authentication or transport.
A signed archive/TestFlight/store build remains WAT-26/28 work.
