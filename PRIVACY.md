# Privacy, logging, retention, and diagnostics audit — QA-05

## Current behavior

### Paired Watch candidate additions (WAT-20–27)

- Optional duration-goal alerts use local UserNotifications only on the Watch.
  There is no APNs registration, push token, server, or notification analytics.
- Permission is requested only when Goal alerts is enabled. Denial does not
  disable timers or goal tracking. Foreground goal feedback remains local.
- One pending request contains only a run UUID, goal duration, deadline, and
  minimal display text. Names are generic unless the last received iPhone
  system-surface privacy preference explicitly allows project names. Watch
  notification preview settings remain system-controlled.
- Watch-local alert preferences and at most three recent goal durations are
  stored in a protected, backup-excluded file, with no project names or notes.
  A fresh/erased local store resets these preferences. Ending, switching,
  removing a goal, or receiving an empty/blocked projection cancels obsolete
  alerts; an offline Watch cannot learn of an iPhone change until it arrives.
- Signed-candidate privacy reporting and physical delivery/redaction remain
  WAT-24–26 gates. This source audit does not prove system delivery or remote wipe.

The paired devices exchange only the local ledger information required by the
companion experience through Apple's Watch Connectivity: project/tag catalogs,
timer and summary-annotation mutations, acknowledgements, canonical snapshots,
totals and the glanceable-surface privacy preference. This is device-to-device
transfer, not a developer server or CloudKit sync path. The Watch persists a
bounded protected cache and durable pending queue so offline actions can be
saved before delivery.

Deleting, reinstalling, unpairing or replacing one device must not be described
as a remote erase or guaranteed recovery mechanism. Unsynchronized Watch data
may be lost. The public support copy therefore tells users to confirm iPhone
history and clear Pending/Review Required states before those actions. Physical
backup/restore and file-protection behavior remains a WAT-24/25 release gate.

### User-facing paired-data disclosure draft

> WellSpent stores your projects, timer records, notes and tags on your devices.
> The iPhone and its paired Apple Watch exchange the information needed to keep
> that local ledger consistent. WellSpent does not send this content to a
> WellSpent account or developer-operated server, and it includes no advertising
> or in-app analytics. Unsynchronized Watch changes are device-local and may be
> lost if you delete the app, unpair devices or replace the Watch. Confirm that
> your intended time appears in iPhone history before doing so.

### Existing iPhone behavior

- Projects (including optional emoji/color identity), notes, session tags,
  exact session timestamps, and report contents remain in the local SwiftData
  store. The store and transient App Group Stop handoff are explicitly excluded
  from iCloud and computer device backups.
- The app contains no networking, analytics, advertising, crash-reporting, or
  third-party runtime dependency.
- Production sources contain no `print`, `NSLog`, `os_log`, `Logger`, or
  equivalent diagnostic emission.
- Expected failures use fixed user-facing categories rather than interpolating
  project names, notes, session IDs, file paths, or underlying error payloads.
- Live Activity state includes a project name only after explicit persistent
  opt-in. The default is the generic `WellSpent timer` label.
- The cross-process Stop handoff stores only session UUID, end timestamp, and
  time-zone identifier. It never stores project names or notes.
- Handoff requests are removed after the authoritative stop is saved. Completed
  sessions remain until the user deletes them individually or confirms **Erase
  All WellSpent Data** in Settings. Calendar integration and CloudKit sync are
  absent from this release.

Run the source audit directly:

```sh
cd '/path/to/WellSpent'
scripts/privacy-audit.sh
```

The same audit runs before builds in `scripts/ci.sh`. The phone app, Watch app
and both widget bundles include privacy manifests for their narrowly scoped
`UserDefaults` use and declare no tracking or collected data types. WAT-26 must
still compare all four manifests and the App Store Connect answers with Xcode's
privacy report from the exact signed candidate.
