# Hourglass candidate — physical device check

WellSpent **0.2.0 (6)** has passed engineering validation. Physical installation
and the icon/complication walkthrough are **blocked**, not passed.

## Validated candidate

- Frozen source: `6c5f66f954ee3f891e4b7e438ecd4eba60d2fc29`.
- Tree: `22e8d45f8c80c1205a6e0b153d8a1548cdf49978`.
- Production-source manifest SHA-256:
  `9680ce4d31c8a523209d838b9afc72bff873d9b31479b2c38392545ed4509e72`.
- Independent source, compiled icon and signed Release archive inspections
  passed. All thirteen CI stages and all 386 tests passed, without failures,
  skips or expected failures. Evidence is under
  `AgentControl/evidence/ICON-02-BUILD/`.
- The Apple Development-signed Release archive is retained at
  `AppStore/Hourglass-0.2.0-6/WellSpent-0.2.0-6.xcarchive`. Its manifest SHA-256 is
  `cd80baeb328c60450663997cfda705e4366e3655e6fe906efffbee2e8ac88ebd`.
  It has not been exported, uploaded or installed by this task.

The light and dark primary iPhone icons and matching Watch icon are described
in `WAT-30-HOURGLASS-ICON.md`. Simulator widget/rendering and reentry results do
not establish real WidgetKit taps or installed Home Screen appearance.

## September 6 installation attempt

The coordinator used a separate, initially clean checkout of the frozen source,
selected the production `WellSpentWatch` scheme, its existing **Debug** Run
configuration and the paired physical Watch destination, and invoked Xcode Run.
This was an attempted developer installation, separate from the Release archive.

Xcode first displayed a connection operation, then reported that it was browsing
the local network for the Watch, which had previously reported preparation
errors, and requested that the Watch be unlocked and discoverable via Bluetooth.
The coordinator canceled the blocked preparation. No successful installation,
app launch or counterpart registration was observed. The generic "Finished
running" toolbar text after cancellation is not counted as a successful launch.

No apps were uninstalled, no stores were erased, and no pairing, radio, account
or personal-content changes were made. The owner readiness request for USB and
a worn/unlocked Watch remains pending.

Xcode automatically rewrote three shared schemes on opening this diagnostic
checkout. The actual nonempty patch was retained, and those changes were
restored before Run; the checkout was clean at that point and immediately after
Run was invoked. After the stopped attempt, Xcode had also reformatted the Watch
string catalog and added four stale-extraction metadata fields. That unrelated
change was preserved and restored after closing Xcode; no string values or
keys were adopted into the candidate. The frozen archive/CI checkout was not
opened in Xcode and remained clean throughout this attempt.

Sanitized operation records, exact patches and their digests remain in ignored
local artifacts under `.derivedData/IconDeviceInstall-20260906T1902Z/`. The
independent post-attempt preflight is a separate observation; it cannot establish
installation from this attempt merely by finding an app with the same version.

## Remaining physical observations

| Check | Result |
| --- | --- |
| Paired installation and exact phone/Watch versions | Blocked; independent post-attempt readiness recorded separately |
| Counterpart registration and project delivery | Not run |
| iPhone light, dark and Automatic Home Screen icons | Not run |
| Watch launcher hourglass icon | Not run |
| Idle complication/Smart Stack tap opens Projects without starting | Not run |
| Selecting a project starts its timer | Not run |
| Paused complication tap reopens the same paused timer without resuming | Not run |
| Running/warm reentry preserves the active timer and elapsed time | Not run |
| Large text, locked/wrist-down privacy and real widget families | Not run |

## Resume checklist

1. Connect the iPhone to this Mac with a data-capable USB cable, and keep it
   awake and unlocked. The observable prerequisite is a wired CoreDevice route.
2. Keep the paired Watch nearby, worn, awake and unlocked, with Bluetooth
   available. Xcode must finish device preparation and offer a usable physical
   Watch destination. This unblocks the single Xcode-owned paired install.
3. After that install, independently confirm both exact production versions,
   the canonical readiness result and counterpart registration. With a fictitious
   project, perform the icon and idle/paused/running steps in
   `WAT-29-DESIGN-REVISION.md`. Record only observed results.

The Mac's iPhone Mirroring app reported that iCloud was not syncing, so it did
not provide a usable phone screen for this session. Account changes were not
attempted. Owner-operated observations may be needed for the physical walkthrough.

The owner confirmed that public privacy/support copy has not changed since the
last release. This task leaves that copy unchanged. Wider resilience, oldest-store
upgrade, battery, distribution, App Review and public-binary release gates retain
their separate evidence boundaries; none is closed by these icon checks.
