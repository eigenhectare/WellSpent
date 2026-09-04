# WAT-20 — Optional Watch duration-goal alerts

Implemented and autonomously verified September 2, 2026. Linear: In Review.
Physical notification delivery remains an explicit release gate, not a simulated pass.

## Behavior and boundaries

- Open timers still start immediately, without a countdown or permission prompt.
  Project options offer 15/30/60 minutes, custom 5-minute increments through
  eight hours, and up to three distinct recent custom goals.
- Tap the goal (or “No time goal”) on the elapsed page to edit/remove the active
  run's goal. Edits go through the same persisted command/outbox boundary; they
  never rewrite counted segments, switch projects, or end the timer.
- Goal alerts are off by default and are a Watch-local preference for current
  and future time-goal runs. Only the explicit toggle can request notification
  permission. Launch, foreground refresh, Start, and automatic retries cannot.
- Denial, permission-request failure, scheduling failure, and preference-write
  failure are distinct recoverable states. Open and goal timers remain usable.
  Turning alerts off cancels immediately even if persisting that setting fails;
  the displayed save error means the change may not survive a restart.
- One stable, nonrepeating local request is derived from the persisted run's
  counted closed segments plus its current open segment. No paused time is
  included. It uses an absolute deadline and a relative interval trigger, not
  calendar wall-clock components, a background timer, or workout runtime.
- A serial reconciliation worker compares the system's pending request with the
  latest desired projection. Duplicate refreshes and process restart do not
  move the deadline or create another request. A late add completion is followed
  by reconciliation so Pause/End/Switch cannot resurrect the old notification.
- Persisted Start/Pause/Resume/Switch/End/goal edits, received snapshots,
  privacy changes, blocking/update states, and unavailable/erased stores all
  feed this projection. Cancellation also removes the old delivered request.
  Already-overdue goals do not schedule catch-up notifications.
- Finite goal-notification reconciliation is awaited before completing an
  existing WatchConnectivity background task. No extra background capability
  or continuous execution is requested.
- The visible, undimmed elapsed page gives one threshold haptic. Reopening an
  already-reached goal is silent. Elsewhere, the notification delegate permits
  normal system banner/sound delivery; the visible goal suppresses duplicate
  system feedback. The system still controls Focus, sound, and delivery.
- Generic notification copy is the default. A project name is included only
  after the Watch receives an explicit iPhone system-surface privacy opt-in.
  Content never contains notes, tags, or history. Every message says the timer
  is still running. Notification preview behavior is system-controlled.
- Watch-local preferences, bounded recent durations, and the single foreground
  feedback marker use a protected, backup-excluded file. A fresh local store
  identity resets these settings. A phone erase/change cannot affect an offline
  Watch before a corresponding snapshot arrives; this is not remote wipe.

## Implementation

- `WellSpentWatch/Features/Goals`: pure alert plan, protected preference store,
  serial coordinator, local UserNotifications adapter, goal editor, durable
  goal-edit command boundary.
- Runtime state refresh is the integration point, including canonical updates
  received over WatchConnectivity. Only committed timer state schedules alerts.
- Timer goal and project-switch sheets use one explicit modal route. The
  elapsed goal is a 44-point accessible button retaining the metric identifier
  and spoken remaining/reached/overtime label. Normal and compact 40mm layouts
  keep metric paging functional without entering the nested scroll fallback;
  sync is now an explicit, accessible header label.
- DEBUG UI fixtures use in-memory preferences and a fake notification center;
  tests never prompt for real system permission or mutate production data.
- Privacy audit now permits UserNotifications only in the Watch goal adapter.
  Regression fixtures still reject APIs in other targets and APNs registration.
  App Store draft copy no longer incorrectly claims no notification permission.
- `scripts/watch-goal-check.sh` is a structural CI check, not behavioral proof.
  The normal Watch unit suite includes the new deterministic regressions.

## Verification

Verified evidence:

- `/tmp/wat20-final-tests.log`: 108 Watch unit tests (83 XCTest + 25 Swift
  Testing) and ten focused UI scenarios passed together on the 46mm simulator.
- `/tmp/wat20-small-header-final.log`: custom/recent/edit/remove/reapply and vertical
  metric paging passed on the 40mm SE simulator after the adaptive-layout fix.
  Alert denial and immediate goal Start also passed on this size in
  `/tmp/wat20-small-watch.log`; its original paging failure is retained there
  and is superseded by the fixed-layout run, not relabeled as a pass.
- `/tmp/wat20-final-adaptive-tests.log`: adaptive-build full unit suite and
  affected 46mm UI regression confirmation passed. The subsequent header-only
  fit refinement was verified on 40mm in the final header run above.
- `/tmp/wat20-release-header-final.log`: final combined Release Simulator passed.
- `/tmp/wat20-device-header-final.log`: final unsigned Watch Release device passed.
- `/tmp/wat20-final-lint.log`: strict formatting, zero diagnostics.
- Source and built-bundle privacy audit, privacy-audit negative fixtures,
  generated app/extension intent metadata, structural goal/picker/start/metrics/
  controls/connectivity/widget checks, and `git diff --check` passed.
- `.derivedData/WAT20-Visuals-Final` and `.derivedData/WAT20-Small-Visuals-Final`:
  custom picker, edited timer, permission state and enabled-alert captures.
  Final 40mm custom/elapsed screenshots were visually inspected. “Running” stays
  on one line; the sync label falls back to its accessible icon when width is tight.
- `WellSpentWatchTests/WatchGoalAlertTests.swift`: permission grant/denial/error,
  no reprompt, paused counted deadlines, rescheduling and goal edits, offline
  durable state, restart idempotency, in-flight End/Switch races, projection
  failure/retry, name privacy, erase/failing erase, overtime, DST, minimal actual
  UNNotificationRequest contents, once-only foreground feedback, preference
  failure and immediate opt-out, bounded recent goals and backup exclusion.
- `WellSpentWatchUITests/WatchGoalUITests.swift`: alerts default off; denial
  leaves immediate Start usable; enable/disable cannot start a timer; custom,
  recent, edit/remove/reapply workflow using the real app UI.
- Scrolling tests use slow, held, bounded drags. Fling gestures can skip Watch
  list rows, so a missing row after a fling is not accepted as feature evidence.

## Remaining physical gate

On the signed paired candidate, enable alerts and run a five-minute goal with
a pause and resume long enough to cross the original deadline while paused.
Verify one alert only at the accumulated counted-time deadline, including
foreground elapsed page, controls, wrist down/Always On, and background use.
Then test End/Switch/remove-goal cancellation, privacy off/on and hidden previews,
system permission denial, restart, and a delayed phone snapshot. Record actual
Watch/phone models, OS/build, Focus/notification settings, exact timings, and
observed haptic/banner behavior. Do not mark this physical gate passed from the
fake-center suite or unsigned builds.

References: [Apple local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app),
[permission guidance](https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications),
[Watch notification behavior](https://developer.apple.com/documentation/watchos-apps/enabling-and-receiving-notifications),
and the installed watchOS 26.5 UserNotifications interfaces. The SDK specifically
does not expose the iOS hidden-preview-placeholder category initializer on watchOS;
this implementation uses the supported category API and system preview settings.
