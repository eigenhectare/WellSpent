# Accessibility audit

This document records the iPhone and Apple Watch Simulator evidence and remaining
hands-on work for `IDK-324` / `QA-04` and WAT-23. It is not physical-device
evidence.

## Implemented contract

- Primary timer controls have explicit spoken labels. Stop identifies the
  project, action, and elapsed duration and cannot be confused with Pause.
- Active, archived, overlap, stopped, warning, and recovery states use text
  and/or symbols in addition to color.
- Custom primary controls use at least a 44-point interaction target. The
  compact Dynamic Island Stop control is 28 points inside the system-constrained
  compact region; the Lock Screen Stop control and in-app Stop control meet the
  44-point minimum.
- Forms, menus, banners, status rows, report filters, and completion content
  wrap or change axis at accessibility text sizes.
- The app and extension contain no app-owned animation, transition, or symbol
  effect. System navigation and presentation transitions therefore inherit the
  system Reduce Motion behavior; there is no custom motion path to suppress.
- Recovery banners use an opaque system background, a non-color icon/message,
  a leading color accent, and a 44-point action.
- Project emoji remain supplemental to spoken project names. Session-tag
  buttons announce their label, selected state, and add/remove action and keep
  a 44-point minimum target.
- The destructive in-app Stop button uses a dark red fill so its white label
  retains contrast in Light Mode, Dark Mode, and Increase Contrast.

## Automated simulator matrix

`WellSpentAccessibilityUITests` launches every case at
`UICTContentSizeCategoryAccessibilityXXXL` and runs Xcode's native
`performAccessibilityAudit(.all)` across these flows:

1. First-launch onboarding.
2. Active timer, Stop, and session completion with configurable tags.
3. Day, Week, and Project reports.
4. History, session review, and manual session editing.
5. Project management and Settings.
6. Transient, disabled/settings-link, and long-running Live Activity recovery.

Default appearance command:

```sh
cd '/path/to/WellSpent'
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project WellSpent.xcodeproj \
  -scheme WellSpent \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/Accessibility-Light \
  -only-testing:WellSpentUITests/WellSpentAccessibilityUITests \
  clean test
```

Dark Mode with Increase Contrast command:

```sh
cd '/path/to/WellSpent'
xcrun simctl ui booted appearance dark
xcrun simctl ui booted increase_contrast enabled
xcrun simctl ui booted content_size accessibility-extra-extra-extra-large

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project WellSpent.xcodeproj \
  -scheme WellSpent \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO \
  -derivedDataPath .derivedData/Accessibility-Dark-HighContrast \
  -only-testing:WellSpentUITests/WellSpentAccessibilityUITests \
  clean test

xcrun simctl ui booted appearance light
xcrun simctl ui booted increase_contrast disabled
xcrun simctl ui booted content_size large
```

On August 28, 2026, using Xcode 26.6, the iOS 26.5 Simulator, and an iPhone
17 Pro simulator:

- The final clean default-appearance matrix passed 6 of 6 tests.
- The final clean Dark Mode + Increase Contrast matrix passed 6 of 6 tests.
- The Simulator was restored to Light Mode, standard contrast, and Large text
  after the matrix.

On August 29, 2026, a broader 31-scenario UI/accessibility regression ran on an
iPhone 17 Pro Max simulator. Twenty-nine scenarios passed in the full run. The
report contrast audit passed unchanged on focused rerun, confirming a transient
audit sample. The largest-text onboarding scenario passed after its test
harness dismissed the software keyboard before tapping the Create button that
the keyboard covered at Accessibility XXXL. No production accessibility
behavior was weakened or excluded for either result.

The test callback allows only narrow, documented Xcode/iOS-owned findings and
keeps an attachment for each occurrence:

- Contrast samples where scroll content intersects the system translucent tab
  bar.
- Dynamic Type findings wholly inside the system navigation bar.
- Contrast samples for content visually occluded by an opaque recovery banner.
- A Stop-label clipping finding only when the fully visible Stop control is
  present; the rendered failure screenshot was inspected before retaining the
  exclusion.

These exclusions do not suppress app-content clipping, app-content Dynamic
Type failures, general contrast failures, missing labels, missing traits, or
small hit regions.

## Apple Watch accessibility and layout

The paired Watch app exposes written and spoken state for Running, Paused,
Pending, Review Required and failure conditions. Start, Pause, Resume, New/Switch,
End, summary, note/tag and goal actions have labels and visible feedback; no
timer state requires color, animation or haptic perception. Primary actions use
44-point targets. Compact noninteractive metric rows retain the platform's
28-point minimum where a larger row would break Crown paging.

Automated Watch coverage runs on 40 mm, 46 mm and Ultra-class Simulators. It
combines Xcode's accessibility audit with actual scrolling, Crown paging and
action/persistence checks at ordinary, maximum and deliberately expanded English
text. It also covers Bold Text, Increase Contrast, Reduce Motion, privacy
redaction and reduced luminance through production system inputs or DEBUG-only
adaptation fixtures as documented in
`WAT-23-ACCESSIBILITY-AUDIT.md`. App-hosted widget layouts cover rectangular,
circular, inline and corner families with sanitized identity.

The final autonomous clean checkout passed 123 Watch unit and 59 Watch UI cases,
plus the complete phone/shared suites. Narrow hit-region exceptions apply only
to measured, noninteractive native watchOS page indicators and dialog headings;
they never waive app controls, clipping, contrast, traits or descriptions. The
exact geometry, required dialog context and rejection guards are retained in
the WAT-23 evidence ledger.

### Remaining physical Watch checks

- Traverse the complete picker, active/paused metrics, controls, Switch, summary,
  note/tag and conflict/offline guidance with VoiceOver on an installed candidate.
- Repeat core actions with the largest system text, Bold Text, Increase Contrast,
  Differentiate Without Color and Reduce Motion; verify Crown/focus reachability.
- Confirm each haptic has a visible/spoken equivalent and the app remains usable
  with haptics disabled.
- Exercise real dictation/keyboard cancellation and preservation of an unsaved
  fictitious draft through wrist-down/wake.
- Inspect physical Always On, lock/redaction, notification previews and actual
  WidgetKit/Control Center surfaces with project names both private and opted in.

Simulator fixtures and screenshots do not certify VoiceOver focus behavior,
system-owned alert font scaling, physical haptics, dictation, Always On or actual
WidgetKit composition. Do not publish an unqualified “fully accessible” claim
until those candidate checks pass.

## Deferred post-launch manual audit

On August 30, 2026, the product owner deferred the remaining hands-on checklist
until post-launch. The automated evidence above remains valid, but it does not
replace the following manual work. `IDK-324` tracks these checks in Backlog and
is not a launch blocker:

- Enable VoiceOver in the iPhone Simulator and traverse each primary flow in
  reading order, including timer Start/Switch/Stop, completion, report
  drill-down, corrections, project management, settings, and recovery actions.
- Confirm every spoken label/value/hint is concise, every control is reachable,
  focus order is logical, and modal focus returns to the expected control.
- Enable Reduce Motion and repeat Start/Switch/Stop plus sheet/navigation
  transitions. Confirm no app-owned motion is introduced and system transitions
  honor the setting.
- Spot-check the largest Dynamic Type layout with touch exploration in both
  appearances, including scroll reachability and the Stop target.

Physical-device Live Activity accessibility, Lock Screen authentication, and
Dynamic Island behavior remain part of `IDK-323` / `QA-03`; simulator results
must not be represented as physical-device evidence.
