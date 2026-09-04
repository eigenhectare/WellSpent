# WellSpent support

WellSpent is a local-first time tracker for iPhone and Apple Watch. It requires
no account or paid service. For support, email `wellspent_support@pm.me` and
include the app version, device type, operating-system version and a short
description of the last successful action. Do not include real client names,
work notes, personal notifications or account details.

## Set up the paired app

Create and manage projects on iPhone. After installing WellSpent on the paired
Apple Watch, open both apps and allow the project list to arrive. On Watch, tap
a project's play button to begin an open timer immediately—there is no countdown.
Use Options to choose an open timer or a duration goal; choosing a goal also
starts immediately.

If the Watch app is absent, confirm that the iPhone build includes the Watch
companion and use the normal Apple Watch companion-install flow. A development
tool named WC Probe is not part of WellSpent and is never needed by customers.

## Work when the iPhone is unavailable

Projects already cached on the Watch remain available for local timing. A Watch
change is saved locally first and may show **Pending** until the iPhone receives
and acknowledges it. Keep both devices available and open both apps to help
resume synchronization. Do not start another timer merely to clear Pending.

Cached phone-authored totals can be older than the Watch's current timer. The
Watch keeps a bounded local queue. If it reports that it cannot save more work,
follow the displayed recovery guidance; do not assume an action succeeded.

## Pause, switch and finish

Pause excludes the paused interval from billable time. Resume begins a new
counted segment. New switches projects at one shared boundary, so the old run
ends exactly when the next begins. End asks for confirmation and saves the run
before showing its summary. Notes and tags can then be added while the work is
fresh.

## Resolve Review Required

**Review Required** means the iPhone and Watch changed the same timer from a
shared earlier state. Open the conflict review on iPhone and inspect both
histories before choosing a resolution. Canceling preserves both versions.
Do not erase, reinstall or unpair devices to bypass review.

## Goal alerts

Notifications are optional. Enable Goal alerts explicitly if wanted. Declining
permission does not prevent timers or goals. Alerts are local, use counted time
rather than paused time, and never end a timer. Delivery depends on system
authorization, notification previews and Focus settings. An offline Watch cannot
immediately learn that the iPhone changed or ended a run.

## Reinstall, unpair and replacement precautions

Unsynchronized Watch time is device-local and may be lost if an app is deleted,
a device is unpaired or a Watch is replaced. Before any of those actions:

1. Confirm the intended time appears in iPhone history.
2. Resolve every Pending or Review Required state.
3. Keep a separate record of any time that has not synchronized.

Do not rely on backup/restore or a replacement Watch to recover a pending local
queue. Deleting one companion app must not be treated as a remote erase of the
other device.

## Privacy

The paired devices exchange the project/tag catalog, timer and annotation
changes, acknowledgements, privacy preferences and current snapshots needed to
keep the local ledger consistent. This uses Apple's Watch Connectivity between
the paired devices. WellSpent has no developer server, account, advertising,
analytics SDK or remote-push registration.

Project names are hidden by default on glanceable system surfaces. If you opt in
to showing names, system lock-screen, Always On and notification-preview settings
still affect what is visible. Avoid using real client data in screenshots or
support reports.

## Accessibility

WellSpent provides labeled controls, text equivalents for timer state and
layouts that adapt to larger text. Timer actions do not require interpreting a
color, animation or haptic. If a control or message is difficult to use, include
the accessibility setting and device class in a privacy-safe support report.

## Beta feedback

TestFlight is an Apple beta-distribution service separate from WellSpent's local
data exchange. TestFlight may share diagnostic/usage information and feedback
with the developer under Apple's terms. Structured testers must use fictitious
projects and notes and review every attachment for private content before sending.
