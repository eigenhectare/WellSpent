# Privacy, logging, retention, and diagnostics audit — QA-05

## Current behavior

- Projects (including optional emoji/color identity), notes, session tags,
  exact session timestamps, and report contents remain in the local SwiftData
  store.
- The app contains no networking, analytics, advertising, crash-reporting, or
  third-party runtime dependency.
- Production sources contain no `print`, `NSLog`, `os_log`, `Logger`, or
  equivalent diagnostic emission.
- Expected failures use fixed user-facing categories rather than interpolating
  project names, notes, session IDs, file paths, or underlying error payloads.
- Live Activity state includes a project name only after explicit persistent
  opt-in. The default is the generic `Billable timer` label.
- The cross-process Stop handoff stores only session UUID, end timestamp, and
  time-zone identifier. It never stores project names or notes.
- Handoff requests are removed after the authoritative stop is saved. Completed
  sessions remain until the user explicitly deletes them; revision retention,
  Calendar, and iCloud policies are outside this release.

Run the source audit directly:

```sh
cd '/Users/dev/Documents/Billable Hours App'
scripts/privacy-audit.sh
```

The same audit runs before builds in `scripts/ci.sh`. The app and widget bundles
now include privacy manifests for their narrowly scoped `UserDefaults` use and
declare no tracking or collected data types. `IDK-328` must still compare the
manifests and App Store Connect answers with Xcode's privacy report from the
signed post-beta archive.
