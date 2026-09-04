# WAT-18 — Watch complications and Smart Stack

Implementation and autonomous verification completed September 2, 2026. The
issue remains In Review for the actual WidgetKit/device gate, not falsely Done.

## Behavior

- All four Watch accessory families are supported: circular, corner, inline,
  rectangular. The rectangular widget also supplies the Smart Stack surface.
- Running elapsed comes from closed counted segments plus the open segment;
  SwiftUI owns date-based ticking. Paused elapsed is frozen. No per-second
  extension execution is requested.
- Timelines contain now and, when relevant, the next goal boundary, with a
  30-minute fallback refresh. Runtime changes reload only when the projected
  widget state changes; transport retries/timestamp-only total changes do not
  themselves require new widget timelines. WidgetKit controls actual delivery.
- Idle rectangular content links the first two recent/catalog projects to goal
  setup. Circular/inline idle surfaces reopen Projects. Taps never issue timer
  mutations. Stale run/project links yield to the current run, conflict or update
  state. Repeating a link reopens its destination.
- Widget read uses a separate read-only ModelContext and returns a bounded
  projection without notes, tags, history, payloads, or confidential glyphs. It
  will not create a missing store. Corrupt/unavailable data yields generic UI.
- An additive optional snapshot preference mirrors iPhone's explicit project-name
  opt-in. Absent/false is private, including legacy snapshots/stores. Preference
  changes advance canonical generation and trigger phone publication. Pending
  local runs survive newer catalog/privacy snapshots; older snapshots cannot
  revert them. An offline Watch necessarily uses its last received preference.
- Gallery snapshots never read real projects. Names are omitted from the widget
  model by default; opt-in views also use privacySensitive and generic identity
  under reduced luminance/redaction. System privacy behavior still needs the
  device gate below.

## Evidence

Xcode 26.6 / watchOS and iOS 26.5 Simulator, Series 11 46 mm and iPhone 17 Pro:

| Check | Result / artifact |
| --- | --- |
| Full Watch unit suites | 58 XCTest + 25 Swift Testing cases passed; `/tmp/wat18-watch-tests.log` |
| Phone sync tests | 22 passed, including preference/generation regression; `/tmp/wat18-phone-tests.log` |
| Widget UI suite | 4 passed together after visual fix; `/tmp/wat18-widget-ui-final.log` |
| Shared view visual inspection | Running, paused, circular, recent private/opt-in/redacted captures inspected; `.derivedData/WAT18-Visuals*` |
| Debug Watch Simulator | Passed; `/tmp/wat18-build.log` and UI/unit builds |
| Combined Release Simulator | Final build passed; `/tmp/wat18-release-final.log` |
| Unsigned Watch Release device architectures | Final build passed; `/tmp/wat18-device-final.log` |
| Formatting, store/widget structural gates | Passed; `scripts/lint.sh`, `scripts/watch-store-check.sh`, `bash scripts/watch-widget-check.sh` |
| Source + combined Release binary privacy audit | Passed; `scripts/privacy-audit.sh` with WAT18-Release bundle |

The first sandboxed build failed because macro/Simulator services were denied.
The normal-Xcode run passed. The first shared-view harness build exposed a
read-only widgetFamily environment key; family injection is now explicit in
the harness. Screenshot review found oversized default Link styling in the
idle widget; plain links fixed it and all four UI tests passed again.

The debug-only harness renders the exact production SwiftUI view, but it is not
a watch-face compositor. It does not prove WidgetKit's curved corner labels,
tinting, placement, real timeline scheduling, or physical Always On. Recent
project links use 30-point targets inside the constrained rectangular family;
full in-app primary actions remain at least 44 points.

## Remaining acceptance evidence

- Install the actual release-like widget on a face and Smart Stack; exercise all
  families and full-color/accented system rendering.
- Confirm privacy after opt-in/opt-out, wrist-down, lock and Hide Sensitive
  Complications settings on physical hardware.
- Exercise active/paused/offline/pending/conflict and actual tap routing, including
  delayed phone state, over a multi-hour run; record reload count and store reads.
- Complete expanded-text/small/Ultra coverage with WAT-23 and physical matrix
  WAT-24. No simulator transport result substitutes for these rows.

References used: [Apple widget creation and privacy](https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension),
[Apple WidgetKit](https://developer.apple.com/documentation/widgetkit), and the
installed watchOS 26.5 WidgetKit/SwiftUI interfaces. See
`WAT-05-ACCEPTANCE-MATRIX.md` for release gate ownership.
