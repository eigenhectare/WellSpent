# WAT-23 — Accessibility, privacy and layout audit

Status: In Review. Autonomous Simulator, source, build and clean-CI work is
complete; this remains an evidence ledger, not physical accessibility sign-off.

Most recent full clean-CI checkpoint includes the final rectangular-widget
follow-up, restart-harness correction, physical-reset regression and later
WAT-25/27 evidence-tooling integration. It passed all 13 stages and **381
tests** with no failures, skips or expected failures.
The preceding help/control
checkpoint passed 42 scenario/display pairs and 374 tests but does not validate
the later widget work. Actual WidgetKit placement and physical accessibility
gates remain open.

## Rectangular-widget follow-up — September 3

The constrained app-hosted widget baseline exposed actual visible truncation in
large-text headers, recent-project links and active project/goal details. Its
full accessibility audit also rejected the raw `arrow.down.app` image label.
The fixed proposal is recorded using SwiftUI geometry, independently of child
accessibility frames; the harness does not clip overflow. This is a layout
stress surface, **not** a measured native WidgetKit slot or compositor.

The production rectangular view now tries full content before compact content.
At constrained sizes it preserves running/paused state and elapsed time; recent
projects retain both navigation destinations, first as concise text links and,
when those cannot fit, as numbered folder links with complete accessible labels.
Full-size detail remains in the app. Compact active content omits optional
project/goal detail instead of displaying ellipses. Status icons with adjacent
text are decorative to accessibility. Redaction/reduced luminance still replace
private identity at its source, including link accessibility labels.

Screenshot review then found that privacy-redacted XCTest captures could blank
generic widget content even when the accessibility tree remained populated.
The widget clears drawing redaction **after** its incoming environment has
selected sanitized identity; this must never be moved ahead of that privacy
decision. Names still disappear at their source. Delayed direct Simulator
captures on all three display classes show the sanitized generic content; the
earlier blank direct 40mm frame was transient and is retained as a capture-timing
diagnostic, not classified as a product defect. The data-free DEBUG heading and
proposal background are explicitly unredacted. Physical WidgetKit privacy
behavior remains an independent gate.

This follows Apple's advice to adapt content to the space available and use
`ViewThatFits` for accessory layouts: [creating widget views](https://developer.apple.com/documentation/widgetkit/creating-views-for-widgets-live-activities-and-watch-complications)
and [widget design guidance](https://developer.apple.com/design/human-interface-guidelines/widgets/).

Retained preliminary evidence:

- `WAT23-WidgetLayoutSmallBaseline1.xcresult`: three test-harness failures because
  a decorative background did not expose the proposed-bounds accessibility node.
- `WAT23-WidgetLayoutSmallBaseline2.xcresult`: one expanded geometry-format
  failure and two actual raw-icon accessibility failures. Its screenshots also
  show truncation that the earlier geometry/audit checks did not detect.
- `WAT23-WidgetLayoutSmallAdaptive1.xcresult`: three passed loops over eight
  states each, with ordinary/largest/expanded text; selected screenshots checked.
  This precedes the later concise recent-link layout and strengthened tests.
- `WAT23-NativeWidgetNavigation1.xcresult`: a public-XCTest input diagnostic
  failed before reaching any system widget. Its speculative test source was
  removed from the regression suite; the failed result/log remain preserved.
  It provides no native placement or complication acceptance evidence.
- `WAT23-WidgetRectangular{Small,Standard,Ultra}2.xcresult` exposed overly strict
  test assumptions about explicit-name Link child nodes and compact status text.
  The corrected `...3.xcresult` bundles passed the three 11-state layout loops
  and four existing widget regressions on each display, plus 123 Watch units on
  Small; only the privacy loop's assumed duplicate fixture name failed. Actual
  fixture names were inspected before correcting that expectation.
- `WAT23-WidgetPrivacy{Small,Standard,Ultra}4.xcresult` each passed the nine-case
  corrected privacy loop. Per-case/device metadata is recorded in
  `.derivedData/WAT23-widget-rectangular-coverage.json` for that pre-redaction-fix
  checkpoint. It is **not visual sign-off** for incomplete/blank captures.
- `WAT23-WidgetRenderedSmall5.xcresult` passed the same nine cases with additional
  post-audit screen captures; some still blanked content. Both those captures
  and the independent `WAT23-WidgetNativeDisplay-*.png` files are retained as
  the evidence that prompted the rendering fix, not as accepted final visuals.

The strengthened suite checks all exposed text and both recent-link hit regions,
actual expanded labels, long durations, overtime, and opt-in/redaction/reduced
luminance cases. CI now selects all four layout/privacy methods and the existing
active/paused/blocked regression (59 Watch UI selections total).

### Final sanitized-content source checkpoint

Source/resource/configuration digest:
`e0629625d4ef5d2e02032c9146b82ce84c8c9ed97a6f655107058b6b11ff0168`.
The digest excludes tests, scripts, documents and generated products.

- `WAT23-WidgetPrivacySmall6.xcresult`: XCTest log reports **5/5 passed**—the
  nine-scenario largest expanded privacy loop and four existing widget tests.
- `WAT23-WidgetRectangularStandard6.xcresult` and
  `WAT23-WidgetRectangularUltra6.xcresult`: XCTest logs report **8/8 passed**
  each—33 ordinary/largest/expanded states, nine privacy states, and all four
  existing widget regressions. Exact result extraction confirms eight passes
  per display with no failures, skips or expected failures; attachments were
  exported and visually reviewed.
- `WAT23-WidgetRectangularSmall7.xcresult` passed **131/131**: 123 Watch units,
  all three 11-state rectangular layout loops, the nine-state privacy loop and
  all four widget regressions. Exact result extraction reports no failures,
  skips or expected failures. Attachments were exported and visually reviewed.
- Delayed direct captures are retained as
  `.derivedData/WAT23-RedactedLive-{Small,Standard,Ultra}.png`. They show generic
  sanitized folder/status content on every display without project names. Blank
  or partial XCTest frames and the earlier immediate 40mm capture remain timing/
  privacy-capture diagnostics and are not substituted for these settled frames.
- Joint Release Simulator build and a local development-signed joint archive
  both succeeded for this source. Source and both products' privacy/fixture
  checks, Release localization parity, strict formatting and diff checks pass.
  See WAT-26 for the current archive's separate trust-inspection limitation.

Circular, inline and corner app-hosted combinations passed in the existing widget
regressions on all three display classes. Actual WidgetKit composition and
physical accessibility remain; the fresh clean CI below includes this follow-up.

### Physical Ultra UI smoke — September 3

After the production 0.1.0 (2) paired installation passed WAT-24's sanitized
preflight, the existing five-screen UI smoke ran on a physical Apple Watch
Ultra 2 with watchOS 26.6. The first attempt reached the runner but stalled
before the first assertion; it was interrupted and classified as a host/device
preparation result, not an app failure. A controlled retry with Xcode's GUI
closed passed its single selected test with zero failures or skips in 28.362
seconds.

The test used the DEBUG-only ephemeral fixture store, fictitious project data,
fixture notification services and no live Watch Connectivity. It launched and
checked Projects, Time Goal, active metrics, Controls and saved summary, and
retained native 410×502 screenshots. All five were visually reviewed: headings,
state, elapsed/goal information, controls and saved time are legible, with no
observed clipping, overlap or private-content issue. Sanitized screenshots,
hashes and scope are in
`.derivedData/WAT23-PhysicalUISmoke2-Sanitized/summary.json`.

Xcode's raw result/export metadata contained the owner-assigned device name and
identifier, so the raw result bundles, derived build products, accessibility
exports and auto-generated partial diagnostics were permanently removed after
the pass was summarized. The retained directory contains only the five clean
PNG files and identifier-free summary.

This is physical rendering and interaction evidence, not actual VoiceOver,
system Dynamic Type, Bold Text, Increase Contrast, Reduce Motion, Always On,
haptic, dictation, WidgetKit placement or debugger-detached behavior. Those
physical sign-off gates remain open.

## Coverage to complete

Use the existing 40mm SE, 46mm Series and 49mm Ultra simulators. For each,
exercise picker/long names, immediate Start, goal setup/custom/edit, active and
paused metric pages, controls, Switch, confirmed End, summary/note/tags, offline,
pending, setup/empty, conflict, unsupported and save/permission failure states.
Include ordinary and maximum Dynamic Type, Bold Text, Increase Contrast,
Reduce Motion, privacy redaction, reduced luminance and expanded English copy.

Apple recommends a 44×44-point default control size on watchOS, with a
28×28-point minimum. Primary controls here must meet the plan's 44-point gate;
secondary controls must not fall below the platform minimum.
[Apple accessibility guidance](https://developer.apple.com/design/human-interface-guidelines/accessibility)

Always On must preserve privacy, not merely dim names and notes. Apple documents
using reduced-luminance and redaction environment values to preview this state.
[Apple Always On design guidance](https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state)

The installed Xcode 26.6 watchOS XCTest headers expose all seven relevant audit
types: contrast, element detection, hit region, descriptions, Dynamic Type,
clipped text and traits. `WatchAccessibilityUITests` invokes the actual audit,
retains every reported issue, and handles only the measured native exceptions
described below. Separate action tests check reachability and primary-control
dimensions; negative tests protect against accidentally ignoring app controls.

## First 40mm baseline

`.derivedData/WAT23-Small-Baseline.xcresult`: ten maximum-text cases executed;
eight passed, active/paused metrics failed hit-region audits. Extracted element
screenshots identified the 7-point colored status dot. It was redundantly
exposed as “Active timer,” despite the adjacent written Running/Paused state.

The dot is now decorative to accessibility. The stable running-screen test
identifier moved to its containing metric page; status text remains exposed.
`.derivedData/WAT23-Small-DotFix.xcresult` proves immediate Start and its existing
identifiers still work on 40mm. It also retains two subsequent hit-region
failures: their cropped screenshots show the native vertical paging indicator,
not the removed decorative accessibility element. The next diagnostic run
identified `PUICMaterialPageIndicatorView`, a separate native window at
`{{154, 33.5}, {6, 32}}` with value `page 1 of 3`. Full details are retained in
`.derivedData/WAT23-Small-Reachability-Attachments/D9A95080-9E99-462B-939C-B91A8D0540DC.txt`.
The later audit adds a narrow exception for this native ornament, permitted by
ACCESS-03. It does not remove native paging or hide app-owned controls. Standard
46mm and Ultra 49mm have different measured indicator heights; their initial
failures and subsequent evidence remain in the result bundles below.

Inspected captures include active metrics, controls, long-name picker, conflict
and summary. Several are scrollable at maximum text; screenshots of only the
initial viewport do not prove that every control or explanatory row is reachable.
The focused reachability run proved the goal settings button and summary Done
can be fully revealed, meet 44-point primary-target dimensions, and open their
expected destination at maximum text. Its initial End failure was a test query:
watchOS exposes SwiftUI alert buttons by system label, not the source Button's
identifier. The UI hierarchy contained the expected “End Run” control.
After using that observed label, `.derivedData/WAT23-Small-Controls.xcresult`
passed Pause, Resume and confirmed End, including primary-target dimensions and
the saved-summary transition. These checks cover 40mm only; Switch and complete
scroll/state coverage still need expansion.

This was the initial checkpoint. Later WAT-23 evidence is recorded below;
the earlier WAT-22 clean CI does not validate changes made after its source
checkpoint.

## Follow-up implementation and audit

- Private presentations now cover the picker, goal setup, Switch, saved summary,
  note editor and tag picker. Running/paused metrics retain elapsed time and
  neutral “Billable timer” identity in reduced luminance.
- Toggling privacy while a sheet was open exposed a real navigation-bar abort in
  `WAT23-Privacy1.xcresult`. The privacy modifier now wraps content **inside** the
  sheet's stable NavigationStack, and root presentation modifiers stay outside
  the privacy cover. A generic system navigation title is not confidential.
- Native List accessibility can retain cells while a parent is hidden. Goal
  headers and tag labels therefore redact at their source. The note field is
  removed while private, but its draft remains in the enclosing State; redaction
  does not submit or discard it. The editing sheet and selection stay alive.
- `WAT23-Privacy4.xcresult` passed six privacy UI cases and two preference unit
  cases (eight executed, zero failures/skips/expected failures). Screenshots then
  exposed a separate blank generic overlay in note/tag sheets. Blanket privacy
  marking moved from presentation containers to private text leaves; that visual
  refinement passed functional checks in Standard Adaptations2. The final tag
  overlay also needed `.unredacted()` on its data-free explanation. All six
  privacy cases plus three summary/ordinary-text regression cases then passed
  on **each** of 40mm, 46mm and 49mm in `WAT23-{small,standard,ultra}-Refinements.xcresult`
  (nine tests per display). The final standard note/tag screenshots were
  inspected: the safe explanation is visible and no project/note/tag is shown.
- Controls, Run details and Totals now have a vertical scrolling fallback. The
  controls status is not forced to one line. Action tests explicitly reveal and
  measure controls, and scroll to summary Done, Run segments and totals freshness.
- Reduce Motion uses an identity page transition and disables app animation.
  Increase Contrast strengthens project-card and control outlines. Primary
  states/actions retain written labels and distinct symbols independently of
  color and haptics. Preference tests prove fixture overrides cannot disable
  active system preferences or enable an unrelated adaptation.

The DEBUG accessibility fixture uses native writable environment inputs for
Dynamic Type, Bold Text, reduced luminance and privacy reasons. SwiftUI's motion,
contrast and differentiate-without-color values are read-only: tests inject
**app adaptation inputs**, while production reads the real system values. The
public `simctl ui … increase_contrast` query returned `unsupported` for all three
Watch simulators; no system accessibility setting was changed. These fixtures
are not proof that watchOS itself changed its settings.

### Native audit exceptions

All issue details remain attached. Exceptions apply only to `.hitRegion`, never
contrast, clipping, descriptions, Dynamic Type, detection or traits.

1. `PUICMaterialPageIndicatorView`, an `Other` element with native “page N of 3”
   value and measured six-point width. 40mm first measured 6×32, 46mm 6×46 and
   Ultra 6×48. Normal-size runs reported the same native dimensions.
   It is an ornament in a separate system window, not an app button. Crown and
   swipe navigation remain available. Wrong type, value, description or size
   must fail the policy's negative tests.
2. On 40mm only, the noninteractive native Start-failure **heading** was reported
   as `UIAccessibilityElementMockView` at `{{16,40},{130,19.5}}`. The retained
   screenshot shows the complete “Couldn’t start” title and explanatory copy.
   The exception requires that exact title, frame, static-text type, description,
   hit-region audit, and the explicitly tested native dialog with Retry/Cancel.
   It never covers those action buttons or arbitrary app text. Retry/Cancel's
   accessibility frames can be text bounds; their actual hit region is left to
   the platform audit, and cancellation is exercised.

Initial expanded runs: Small Adaptations2 executed 24 cases with only the native
heading failure; Standard/Ultra Adaptations1 failed the larger native indicator
measurements. These are retained diagnostics, not passing runs. The expanded
suite covers eleven ordinary-text fixture states, largest-text picker/status/
metric variants, custom goal, Start/Switch/Pause/Resume/End, summary Done, error
cancellation, scrolled details and combined adaptations. It does not yet cover
every editing/error state or pseudo-localization.

Small Adaptations3 passed all 25 audit/action/policy tests. Standard
Adaptations2 executed 142 tests: 111 Watch unit cases, six privacy UI cases and
25 audit/action/policy cases; 141 passed and the ordinary-text fixture loop
failed on an app-owned summary row. Ultra Adaptations2 found the same row.
Its accessible frame was only 19.5 points high. This was **not** exempted: summary
detail rows now have an explicit 44-point content shape, verified by all three
subsequent Refinements runs.

Screenshot inspection of the passing Small Adaptations3 run caught problems
the automated audit did not: accessible-size picker names were squeezed between
icons, Run values truncated, and the two-column totals became unreadable.
The next `ReadableLayout` checkpoint therefore introduces full-width stacked
picker/Switch cards and metric/summary rows at accessibility sizes, vertically
stacked totals, and unrestricted project-name wrapping. Ordinary layouts retain
their compact presentation. Noninteractive Run rows use the 28-point minimum
at ordinary sizes so native paging does not acquire an unnecessary scroll view.
The ReadableLayout suite also repeats the existing ordinary Crown-paging test.
Do not treat the earlier green audits as proof of these later layout changes.

Combined Release Simulator and unsigned iOS/Watch device-SDK builds passed at
the pre-ReadableLayout checkpoint. Source/compiled-binary privacy, all four
product fixture-isolation checks, privacy negative tests, CI guard negative
tests, strict formatting and structural checks passed. A byte-audit diagnostic
matched an empty DEBUG-only source filename in compiler metadata, not fixture
code; renaming that file to `WatchAccessibilityPreviewSupport.swift` kept the
fixture **type-name** guards intact. Later ReadableLayout builds have separate
logs and are not implied by this earlier evidence.

## Verified checkpoint — September 3, 2026

The code/resource/configuration digest below is not a git commit:
`b46f9502f4e39f861874f2384b36677d5b80ce54a350720275efb97e11efa082`.
It is SHA-256 of sorted `shasum -a 256` lines for files under WellSpentApp,
WellSpentShared, WellSpentWidgets, WellSpentWatch, WellSpentWatchContracts,
WellSpentWatchStore, WellSpentWatchIntents, WellSpentWatchWidgets,
WellSpentWatchTests, WellSpentWatchUITests and Configurations, plus project.yml.
Documents and generated build products are excluded.

| Evidence | Result and scope |
| --- | --- |
| `WAT23-{small,standard,ultra}-ReadableLayout.xcresult` | All 25 audit/action/policy cases passed on each display. The additional ordinary Crown-paging test failed and was fixed afterward; these bundles are not wholly green. |
| `WAT23-{small,standard,ultra}-SheetAndPaging.xcresult` | 11/11 tests passed on each display: ordinary Crown paging, accessible Run details, actual maximum-text Switch/custom goal/settings, and all six privacy cases. Zero skips or expected failures. |
| `WAT23-Checkpoint-Unit.xcresult` | 111/111 Watch unit cases passed; zero skips or expected failures. |
| `/tmp/wat23-simulator-checkpoint-release.log` | Joint iPhone/Watch/extension Release Simulator build passed. |
| `/tmp/wat23-device-checkpoint-release.log` | Joint unsigned iPhone/Watch/extension device-SDK Release build passed. Not signing or installation evidence. |

Result bundles are under `.derivedData/`. Matching SheetAndPaging UI logs are
`/tmp/wat23-{small,standard,ultra}-sheet-paging.log`; unit log is
`/tmp/wat23-checkpoint-unit.log`. All these processes completed. Final source and
binary privacy scans, Release fixture isolation for both products, strict lint
and structural checks passed.

The paging regression was a real layout interaction: adding minimum accessible
row areas selected the nested ScrollView at ordinary size, consuming the next
page swipe. The compact Run layout now preserves its 28-point noninteractive
row minimum with a compact header/spacing; accessible-size rows still use the
readable stacked/scrolling presentation. The existing two-swipe paging test
passed unchanged on all three displays.

The first sheet screenshots also revealed that root-only DEBUG Dynamic Type
injection did not reach presentation boundaries. Each sheet now explicitly
applies the DEBUG preview environment. This is compiled out of Release. The
later SheetAndPaging screenshots show genuine large-text, full-width Switch
destinations; earlier “largest” sheet captures are not accepted as that proof.

Inspected final small-display captures show complete “Client Launch” and
“Admin & Operations” names, full started time and total durations, custom-goal
confirmation, and readable private editor placeholders. Native navigation
titles can still truncate at extreme sizes; compact app-owned title wording is
part of the remaining localization/layout pass, not silently waived.

## Source-audit follow-up

- App-hosted final privacy screenshots now cover all display classes and the
  reduced-luminance/opt-in combinations. Keep actual system placement separate.
- Verify complete content reachability, not just accessibility existence;
  inspect all scrolled states and actual hit frames on every display class.
- Localization implementation and expanded-string evidence are recorded below.
  Complete the remaining widget/control/notification rendering combinations;
  user project names/notes must remain verbatim user data.
- Continue checking complete note/tag content and all remaining error paths at
  actual maximum text, not just the initial viewport or accessibility existence.
- Exercise setting combinations and visible saved/busy/failure feedback. No
  countdown, animation or haptic may be required to understand timer state.
- Run widget/complication/control and goal notification privacy render checks.
  Do not treat app-hosted widget previews as WidgetKit scheduling evidence.
- Selected privacy/localization/widget cases and catalog guards are in CI. The
  final 379-test clean-checkout run below proves the complete pipeline executed.

Physical VoiceOver interaction, haptic perception, true Always On/lock behavior
and actual system dictation remain explicit device evidence, not simulator
claims. Their procedures can be prepared autonomously; they remain unpassed.

## Localization and expanded-text implementation — September 3, 2026

The shared shipping catalog contains 274 English messages, with a separate
five-phrase Siri catalog. Release compiler extraction supplies the inventory;
DEBUG fixture strings and fictitious project/note data are excluded. There are
no shipping non-English translations in this change. Computed statuses, errors,
notifications, controls and summaries now have explicit localization boundaries;
reusable title parameters use localized resources. Pending-item singular/plural
rules live in the catalog; spoken durations use Foundation's locale-aware units.
Tests cover locale/plural behavior, user-data preservation, invalid/large
durations and actual compiled English resources.

Real `NSDoubleLocalizedStrings` launches first assert that Projects/Running
actually expand. The matrix audits eight primary states at ordinary and maximum
text; action tests exercise Start, custom goal, Pause, Resume, Switch, note/tag
editing and save-failure recovery. Screenshots and accessibility trees are kept.

Screenshot review drove additional fixes: picker cards now give names full
width with separate named Options actions; goal/status text wraps; counters use
verbatim/locale-aware formatting. Note editing has a complete wrapping draft
preview, with Use Note before the long passage. Sheet titles live in content
and cancellation uses a labeled 44-point close control. An explicit empty
navigation title produced an unlabeled native node; removing it fixed the
failure without an audit exception.

A scrolling custom-goal wheel trapped confirmation below it. A subsequent pinned
button passed action tests but visually overlapped the wheel; that temporary
layout is **not** accepted as visual evidence. The final sibling layout has a
flexible wheel, short Goal/Use labels and no overlay. A new test changes the
wheel, starts, reopens settings and checks the persisted selected value at both
text sizes. Inspected small-display screenshots show the selected 85-minute
value and confirmation separately, without overlap.

### Platform expansion artifacts and retained diagnostics

The expansion flag affects native resources too. `WAT23-Small-Expanded2` captured
the raw native indicator value `page @ of @ page 1 of 3`. Its placeholder fragment
comes from platform expansion, not shipping copy. The existing native ornament
hit-region exception accepts the corresponding page 1/2/3 values only in an
explicitly expanded test, retaining exact type/description/dimensions. Negative
tests reject the wrong context, buttons and non-hit-region issues. There is no
new app-owned target or clipping exception. The expansion engine can expose
unformatted fragments in interpolated strings; these captures are stress
diagnostics, not localized release screenshots. Ordinary English and compiled
catalog/plural verification remain separate requirements.

- `WAT23-Localization-Proof`: 116 unit tests plus one real-expansion UI proof
  passed. `WAT23-Small-Expanded1/2` retain navigation, native-indicator and
  trapped-confirmation failures.
- `WAT23-Small-Expanded3`: 14 UI tests passed, but the pinned-goal screenshot was
  rejected as described above. `WAT23-standard-LocalizedCheckpoint`: 14 UI tests
  passed. The Ultra counterpart passed 13 with one lazy-list query failure;
  explicit scrolling to tag confirmation fixed it in `WAT23-Ultra-TagReveal`.
- The small `LocalizedCheckpoint` was contaminated by mistakenly overlapping
  jobs on the same simulator and is not accepted. The newer overlapping custom
  selection job was interrupted; its result recording was incomplete. Both are
  retained. The isolated `WAT23-Small-CustomGoalSelection2` subsequently passed
  and its ordinary/maximum screenshots were inspected. Never run two UI jobs
  on the same simulator, even with different DerivedData directories.

CI now requires 116 Watch unit executions and explicitly names the localization
cases. Its 31 selected Watch UI cases include privacy, expansion and actual
wheel selection. Catalog integrity, Release extraction parity and negative
corruption guards are included. The complete new clean-checkout pipeline still
needs execution; these edits do not close that gate.

### Final localization checkpoint

Code/resource/configuration digest:
`e74cdd7e7acbc15ba30e1d9822c8d5a6b30cec371932796a1fd246c2463ae03c`.
Computed using the earlier checkpoint's sorted SHA-256 procedure, now also
including the new `WellSpentWatchLocalization` directory. Documents/scripts and
build products are excluded from that digest; script verification is separate.

| Result bundle under `.derivedData/` | Verified result |
| --- | --- |
| `WAT23-small-LocalizationFinal.xcresult` | 131 passed: 116 Watch unit cases and 15 UI cases (six localization/action cases, six privacy cases, custom-goal reachability, native-exception policy and ordinary Crown paging). |
| `WAT23-standard-LocalizationFinal.xcresult` | Four passed: actual wheel selection/persistence at both text sizes, normal largest-text goal confirmation, goal privacy restoration and tag privacy/confirmation. |
| `WAT23-ultra-LocalizationFinal.xcresult` | The same four focused cases passed. |

All three final bundles have zero failures, skips or expected failures. Final
standard/Ultra wheel screenshots were inspected as well as the small captures:
selected value and confirmation are separate and readable. The broader earlier
standard/Ultra localization matrix is retained above; four focused tests do not
claim to repeat that entire matrix. All processes completed.

Both combined unsigned Release variants passed. Logs:
`/tmp/wat23-localization-final-release-sim.log` and
`/tmp/wat23-localization-final-release-device.log`. Source and all four compiled
products passed privacy checks (including the strengthened WAT-25 guards) and
Release fixture isolation. Catalog/CI negative guards, required unit identifiers,
strict formatting and `git diff --check` passed. Full clean-checkout CI and the
remaining widget/error/physical requirements are still open.

## Goal error-state follow-up — September 3

Added disconnected DEBUG-only fixtures for alert-settings storage failure,
one-shot notification-permission/scheduling failures, and a one-shot goal-save
failure. Two unit cases verify that the notification fixtures fail before
changing state and recover on explicit retry. Eight UI cases cover the four
errors at ordinary and maximum app text sizes, including immediate Start,
unchanged saved goals after failure, permission/scheduling retry, and persistence
of the subsequently selected goal.

`WAT23-small-GoalErrors3.xcresult` passed 118 unit and eight UI cases; the standard
and Ultra `GoalErrors3` bundles each passed eight UI cases. **These are not final
layout sign-off:** screenshot review found the long permission explanation
ellipsized by a native List row on the standard display. Simply forcing the Text
height (including a single-child wrapper) then drew outside the native row and
overlapped adjacent content. The corresponding `GoalMessageLayout` and
`GoalMessageLayout2` screenshots are rejected despite passing assertions.

The current correction uses a scrolling SwiftUI stack for the preset/alert form,
keeping the native custom wheel in its separate, non-scrolling branch. This
preserves immediate Start and existing goal choices. `GoalMessageLayout3/4` are
retained harness diagnostics (switch activation and navigation occlusion).
`WAT23-standard-GoalMessageLayout5.xcresult` passed the complete permission-error,
off/on retry and immediate-Start path. Its full error/recovery screenshots were
inspected: text does not ellipsize, overlap adjacent content, or draw outside a
fixed-height row. The broader regression and targeted retests are now complete:

| Bundles under `.derivedData/` | Evidence |
| --- | --- |
| `WAT23-small-GoalFormFinal.xcresult` | 118 units and 14 UI cases passed; one small-display scrolling-after-retry harness failure retained. |
| `WAT23-standard-GoalFormFinal.xcresult`, `WAT23-ultra-GoalFormFinal.xcresult` | Each passed 13 UI cases; two older permission tests failed because they tapped behind navigation chrome. |
| `WAT23-small-GoalFormRetest.xcresult` | 118 units and all three legacy goal cases passed; the near-viewport-height paragraph still exposed a scrolling-harness failure. |
| `WAT23-standard-GoalFormRetest.xcresult`, `WAT23-ultra-GoalFormRetest.xcresult` | Four passed on each: all legacy goal cases plus scheduling retry at largest text. |
| `WAT23-small-GoalLongText.xcresult` | Both long-text permission/scheduling recovery cases passed, including separate beginning/end captures of the longest paragraph. |

The final shared `WatchUITestScrolling` helper follows live geometry after a
conditional row disappears, uses drags above the native pan threshold, and
keeps content taps below measured navigation chrome. Near-viewport-height
paragraphs receive explicit beginning/end checks and screenshots; a whole
paragraph need not occupy one pixel-perfect scroll position to be readable.

The latest passing result for each of the 15 required UI scenarios was checked
by exact test identifier on each display: **45 distinct scenario/display pairs**,
plus **118 Watch units**. The per-case mapping is retained in
`.derivedData/WAT23-goal-form-coverage.json`. This is combined evidence from the
full runs and retests, not a claim that the failed bundles were green. Final
error/retry, expanded-form, wheel and privacy screenshots were inspected;
scrolling content can naturally extend beyond the viewport, without intrinsic
ellipsis or the earlier text-row overlap.

Production source/resource/configuration digest (same app code across the full
form runs and retests):
`07ced3f924701c4f230f44986d61bf29f3fd88c0b28cea66e4dc861da6bb19be`.
This uses the sorted SHA-256 procedure above, excluding both Watch test folders.
Including those folders with the final shared helper gives
`a93f6d7f7a6bcefb4ec130d8538a603e4f177544c68d4fb95eaa7d6667c7f856`.
Documents, scripts and build products are excluded from both digests.

Both corrected-form combined unsigned Release builds and their privacy/fixture
scans passed. Logs: `/tmp/wat23-goal-form-final-release-sim.log` and
`/tmp/wat23-goal-form-final-release-device.log`. Release catalog-extraction parity,
strict formatting, CI/localization/privacy negative guards and diff whitespace
checks passed. A complete fresh clean-checkout CI run remains required.

Harness findings are now in WATCH-TESTING-GUIDE.md: native alerts can expose the
same message twice; their OK text is a small Button inside a full-sized tappable
row. Measure and exercise the row. Native Close belongs in navigation chrome,
not the scrolling-content viewport. That viewport must use the navigation bar's
actual height, and native switch activation must not be replaced by a guessed
tap at the center of its label rectangle. No new accessibility-audit exceptions
were added.

CI now requires 118 Watch unit executions and 39 selected Watch UI cases. Its
per-test default/maximum allowances are 90/120 seconds because the already
verified expanded-text wheel round trip takes about 70 seconds. A clean snapshot
at `WellSpentCleanCheckout.mDqRu7/DerivedData/run.J8Luyu` passed source checks,
four combined builds and the iOS golden suite, then was deliberately stopped
during the Watch-unit stage after the screenshot-discovered layout change.
The snapshot/results are retained; it is **not** a completed CI gate. Log:
`/tmp/wat23-goal-errors-clean-checkout.log`. A fresh run must use the corrected
form. Earlier standalone Release privacy/isolation passes in
`/tmp/wat23-goal-errors-release-{sim,device}.log` also predate that form change.

### Corrected-form CI checkpoint and guide-navigation retest

The complete attempt from temporary snapshot
`3f8a1cf41d96e2fe9aca08bcf29ef1fd6ee0f7c5` is terminal and failed, not a passed
pipeline. Evidence root:
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.9SzCev/DerivedData/run.LnxEYw`.
Log: `/tmp/wat23-goal-form-clean-checkout.log`.

Source gates, four joint builds, 19 iOS golden/118 Watch unit/161 phone unit
tests, and Release-product inspection passed. Watch UI finished **38 passed,
one failed**, no skipped/expected failures; phone UI did not run because CI is
fail-fast. The sole failure was the guide test's pre-scroll assertion that a
lazy native List row already existed. The same recorded test then scrolled,
opened Siri & Controls, and returned without starting a timer.

`WatchSystemActionsUITests` now waits for foreground launch and reveals the row
using the measured content viewport before asserting/tapping. No app behavior
or accessibility threshold changed. It passed on the 40mm Watch together with
all **122** Watch units (including four new WAT-25 resource cases):
`.derivedData/WAT25-FullUnitsAndHelp.xcresult`, log
`/tmp/wat25-full-units-help.log`. This targeted retest does not turn the failed
CI bundle green; the separate full retry below is the passed checkpoint.

### Passed clean-checkout checkpoint — September 3

The fresh retry completed successfully from temporary snapshot
`11dbfa1a1e5ef705e52680de18dbaedd994c6aa1`, evidence root
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.xrUdnK/DerivedData/run.XFzPMf`,
log `/tmp/wat25-resource-clean-checkout.log`. It includes the guide fix and
122-unit resource checkpoint. All **13 stages passed** in 1,263 recorded stage
seconds. Five result summaries and required-ID manifests confirm **358 passed,
zero failed/skipped/expected failures**: 19 iOS golden, 122 Watch unit, 161 phone
unit, 39 Watch UI and 17 phone UI. Debug/Release joint Simulator/device builds,
source/negative guards, Release privacy/fixture isolation and localization
extraction parity also passed.

Production source/resource/configuration digest was identical in the clean clone
and working tree at that checkpoint (later changes are recorded below):
`07ced3f924701c4f230f44986d61bf29f3fd88c0b28cea66e4dc861da6bb19be`.
The snapshot is a temporary verification commit, not a project commit or release.
Later additions are separately verified: four resource tests with a stronger
byte-exact acknowledgement assertion (`WAT25-QuarantineBytesFinal.xcresult`),
one five-screen draft capture (`WAT27-DraftScreens1.xcresult`), and WAT-26 tooling
guards. Do not claim those later files were present in this CI snapshot.

This closes the current clean-CI checkpoint, not the entire WAT-23 acceptance
matrix or any physical, signing, beta or release requirement.

## Help, control-error and unavailable-cache follow-up — September 3

The focused final matrix verifies **42 scenario/display pairs**: three help
variants, eight control-error variants, and three unavailable-cache variants on
each of 40mm SE, 46mm Series, and 49mm Ultra. Exact passed test identifiers and
actual Simulator metadata are retained in
`.derivedData/WAT23-help-control-final-coverage.json`. This is not the remaining
widget matrix or physical accessibility sign-off.

### Production and test changes

- The initial native-list help baseline passed paragraph audits and scrolling,
  but screenshot review showed its navigation title squeezed between Close and
  Done. The title now wraps in scrollable content; each section and paragraph
  retains its localized text, native Close remains available, and a full-width
  44-point Done action ends the guide. Tests traverse the beginning and ending
  of all five paragraphs, audit each position, verify actual string expansion,
  and dismiss without starting a timer. Ordinary, largest SwiftUI text, and
  largest doubled-English runs passed on all three display classes.
- `WatchControlErrorUITests` exercises Pause, Resume, Switch and End at ordinary
  and largest SwiftUI text. Two disconnected fixture failures allow Cancel,
  verification of the original project/running-or-paused state, a second
  attempt, and explicit Try Again through the real store boundary. End still
  requires confirmation and routes to a locally saved, pending-sync summary.
  Native alert action rows—not the narrower text glyphs—are measured and tapped
  at 44 points. The existing persistent-failure fixture remains covered by the
  older Switch regression. Failure injection is DEBUG-only and fixture-only.
- The added boundary unit case injects an actual pre-save store failure for
  Pause, Resume, running End and paused End. Entire store state and outbox are
  unchanged after rollback; retry appends exactly one command/sequence and
  preserves the correct segment boundaries and paused gap. All **123 Watch
  unit cases** passed in the standard focused run (90 XCTest + 33 Swift Testing).
- A disconnected `store-unavailable` fixture fails before opening a store. The
  runtime enters fixture mode before initialization, so even failure cannot use
  live connectivity or real notification preferences. Unavailable storage now
  shows existing localized recovery guidance rather than claiming setup is
  incomplete. A later visual check caught text beneath the scroll indicator;
  ten-point horizontal content margins and a hidden decorative indicator fix
  that. All nine final cache cases passed and their captures were inspected.
- CI now requires these 15 new UI/guard cases and the rollback unit case:
  54 selected Watch UI cases and a minimum 123 Watch units. Only Watch UI gets
  240/300-second default/maximum allowances, because the complete doubled-text
  help traversal took 172 seconds on 40mm; other test stages retain 90/120.

### Measured native-heading exception and limits

The first 40mm control run reported hit-region failures on native, noninteractive
dialog headings at `{{16,40},{130,19.5}}`: End this run?, Couldn’t pause,
Couldn’t resume and Couldn’t switch. The next run also retained and visually
verified Couldn’t end at that exact frame. The headings are complete and readable;
the primary actions are separate full-size table rows below them.

The new exception is limited to `.hitRegion`, that exact native mock-view report,
static-text type, frame and one of those five labels. It additionally requires
the explicitly expected dialog title and the native table with the corresponding
Cancel and End Run/Try Again actions. It cannot waive clipping, contrast, traits,
Dynamic Type or app buttons. A negative test rejects missing/wrong context,
description, action labels, unrelated labels, type and geometry. The final
40mm run and standard/Ultra guard retests passed; every handled report remains
attached. Earlier native paging/Start-heading exceptions are unchanged.

**Native system-font limitation:** `xcrun simctl ui <40mm-id> content_size`
returned `unsupported`. The largest-text flags enlarge SwiftUI application
content, not the system-owned alert font. Native dialog captures remain at the
Simulator's actual font size; these runs are not proof of the physical Watch's
largest system alert setting. Include that in the focused physical gate.

### Retained evidence

All paths below are under `.derivedData/`; corresponding `/tmp/wat23-*.log`
files preserve build and test output. Attachment directories have the same
basename with `-Attachments` instead of `.xcresult`.

| Display / purpose | Result bundle | Verified result |
| --- | --- | --- |
| 40mm help | `WAT23-HelpSmallRefinement1.xcresult` | 4 help UI + 7 boundary units |
| 40mm control recovery / guard | `WAT23-ControlFoundationSmall3.xcresult` | 9 control/guard + 3 pre-margin cache UI |
| 46mm control recovery | `WAT23-ControlStandardBaseline.xcresult` | 8 UI |
| 46mm help / full units | `WAT23-HelpFoundationStandard1.xcresult` | 123 units + 4 help + 3 earlier cache UI |
| 46mm regression / guard | `WAT23-FoundationStandardFinal.xcresult` | 3 pre-margin cache + guard + existing Switch/paging |
| Ultra help / control recovery | `WAT23-HelpControlUltra1.xcresult` | 4 help + 8 control UI |
| Ultra guard | `WAT23-FoundationUltraFinal.xcresult` | guard + 3 pre-margin cache UI |
| Final cache layouts, all sizes | `WAT23-Foundation{Small,Standard,Ultra}Margins.xcresult` | 3 UI each, zero failures/skips |

Retained diagnostics are **not passes**: `WAT23-ControlFoundationSmall1.xcresult`
stopped at an exhaustive-switch compile error in the new fixture enum; Small2
passed three cache cases but failed eight control cases on native-heading
reports. `WAT23-HelpSmallBaseline.xcresult` passed one test but its screenshots
exposed the title problem. The earlier
`WAT23-help-control-coverage.json` predates the margin fix and is superseded by
the final coverage record above, not deleted.

The pre-margin production digest was
`feceacdc0ddd547aa88a679ac72daf54b3b22588b6e7da156caeaef72a7d251a`.
Both joint Release builds, Release localization parity, source/binary privacy
and fixture-isolation checks passed there; logs are
`/tmp/wat23-help-control-release-{simulator,device}.log` and
`/tmp/wat26-help-control-inspection.log`. WAT-26's new CI package checks also
passed during the subsequently superseded clean run.

That run's temporary snapshot was `33dd2ef94a6877742398584fbf717ca683312229`,
root `WellSpentCleanCheckout.SWLC0U`, evidence `DerivedData/run.n4GbYz`, log
`/tmp/wat23-help-control-clean-checkout.log`. The first eleven stages passed.
Its live Watch UI process was intentionally interrupted when screenshot review
identified the margin/indicator issue; the run exited 73, Watch UI is failed/
interrupted and phone UI did not run. This is not a full-CI pass or a timeout
restart. All evidence remains in its retained temporary directory.

Final production source/resource/configuration digest, after the margin fix:
`cd0a7feeb6b6f1eded3e8633e5792889b20dc41cb20cf0f78720cff3a886601c`.
A fresh full clean-checkout pipeline must verify this source before the new
checkpoint can be called fully green. Widget-family/state/privacy/layout
combinations and physical gates remain open independently of that CI result.

Replacement clean CI **passed all 13 stages** from temporary snapshot
`058461cdb90b1d39be3561d422dd09378cf54d40`, retained root
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.BB9IUG`,
evidence `DerivedData/run.h0nZNi`, log
`/tmp/wat23-help-control-final-clean-checkout.log`. Its production digest was
verified identical to the final working tree above. All five result bundles and
required-ID manifests were independently rechecked: **374 passed tests**, no
failed/skipped/expected failures (19 golden, 123 Watch units, 161 phone units,
54 Watch UI, 17 phone UI). Stage durations sum to 1,755 seconds. All four joint
build variants, Release localization/privacy/fixture-isolation checks, and the
new WAT-26 package inspection and negative guards passed. Session exited zero;
this is a completed checkpoint, not a live run. Widget and physical gates remain.

### Final widget-source clean CI — September 3

The first full attempt after the widget follow-up passed its first 12 stages,
including all 59 Watch UI tests, then finished the phone UI stage with 16 passes
and one restart-recovery failure. Its hierarchy showed that the initial
`XCUIApplication().terminate()` was attached to PID 0, so the subsequent launch
foregrounded stale ordinary app state without applying the test's launch
arguments. The failed pipeline is retained at
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.phlZ8g/DerivedData/run.AqLH4R`;
log `/tmp/wat23-widget-final-clean-checkout.log`. It is diagnostic evidence, not
a passed run.

`RestartRecoveryUITests` now retries the initial launch exactly once only when
the expected checkpoint is absent and a positively identified ordinary app
surface proves this PID-0 precondition. It does not reseed or retry an unknown,
slow or failed recovery state. The focused cold case, an exact stale-app
precondition case and the full two-case restart suite passed in
`WAT23-PhoneRestartRecoveryFix{1,2,3}.xcresult`; the final bundle contains two
passes and no failures, skips or expected failures.

The replacement clean checkout then passed all **13 stages** from temporary
snapshot `a58f7bd1baeedbbd360b9e4a7422cb15a0c299e7`. Retained root:
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.BafdJZ`;
evidence `DerivedData/run.oIgtlj`; log
`/tmp/wat23-widget-final-clean-checkout2.log`. Five exact result summaries and
required-ID manifests verify **379 passed**, zero failed/skipped/expected
failures: 19 iOS golden, 123 Watch unit, 161 phone unit, 59 Watch UI and 17
phone UI. All four joint build variants, source/negative gates, Release package
inspection, localization extraction, privacy and fixture isolation passed.
The production digest remains the sanitized-widget digest recorded above; the
only post-failure correction is UI-test harness logic. This closes the autonomous
Simulator/build/CI portion of WAT-23, not its physical checklist.

### Post-physical-reset current-source clean CI

The physical WAT-24 diagnostic subsequently corrected the empty-spike reset
path and added two phone unit regressions. WAT-26 also strengthened archive
symbol validation and clean-source provenance. After release-document snapshot
and generated-project drift guards were corrected, the final current-source
pipeline passed all 13 stages from synthetic snapshot
`26e977e184d5651b56efbd960a02680a6a564f8e`. Retained root:
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.xArrZO`;
evidence `DerivedData/run.Q3i2uP`.

All five result summaries and required-ID manifests were independently checked:
**381 passed**, zero failed/skipped/expected failures—19 iOS golden, 123 Watch
unit, 163 phone unit, 59 Watch UI and 17 phone UI. All four joint build variants,
privacy/localization/fixture gates, dSYM/package negative guards, generated
project parity and the same-run clean-source/product receipt passed. The
path-ordered 142-file production source manifest SHA-256 is
`59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`.
This supersedes the earlier manual production digest for the current source;
the synthetic commit is CI evidence, not an approved release commit. Physical
accessibility and actual WidgetKit system-surface checks remain open.

### Post-audit-tooling continuation clean CI

After adding the isolated Watch Simulator runtime sampler, shell syntax gate,
draft icon-size evidence and latest physical preflight record, a new clean
checkout passed all **13 stages** from synthetic snapshot
`1e929e74935550b891cf99dbe2348e99e03b8c49`. Retained root:
`/var/folders/g6/h9knh2zj6sj218p24n0d0p6m0000gn/T/WellSpentCleanCheckout.5Aqsso`;
evidence `DerivedData/run.HOdM21`.

All five result summaries report **381 passed**, zero failed/skipped/expected
failures: 19 iOS golden, 123 Watch unit, 163 phone unit, 59 Watch UI and 17
phone UI. All four joint build variants, release-package inspection, privacy,
localization, fixture-isolation, project-drift and source gates passed. The
production source manifest remains
`59e8d569f95ba1b92eba486e51cc69b760c00005cc3cad3b2f5aae37d9face75`;
the newer synthetic tree is `1c99388f2dd9be466c0e997dd260b512a155eeec` because
the snapshot also contains the updated scripts and evidence documents. This
supersedes the preceding pipeline as current CI evidence without promoting any
physical accessibility or WidgetKit placement gate.

## Focused physical verification — prepared, not run

Use the production WellSpent companion, not WC Probe, installed by the unified
workflow in WATCH-TESTING-GUIDE.md. Record build/version, device class and OS;
never serial/account identifiers. Use fictitious projects and notes. Do not
erase, unpair, reinstall, or change personal projects for this audit.

1. With VoiceOver, traverse the picker in order. Hear each full project name,
   immediate-Start action and separate Options action. Start once and confirm
   visible Running/elapsed state with no countdown and no duplicate timer.
2. Traverse elapsed, goal settings, Run and Totals. Hear units, paused duration,
   started time, segment count and freshness. Confirm Crown/page navigation and
   scrolling do not trap focus; visit controls and return without changing time.
3. Pause, Resume, open New/Switch, cancel once, then choose another project.
   Hear full destination names and changed state. End with confirmation, then
   traverse the saved summary in order and return with Done. Confirm iPhone
   history preserves all counted intervals and excludes paused time.
4. Repeat key actions with largest supported text/Bold Text, Increase Contrast,
   Differentiate Without Color and Reduce Motion. Record visible equivalents
   for each haptic. Verify the app remains understandable with haptics off.
5. Open note/dictation and cancel; reopen, enter a fictitious draft, lower the
   wrist and wake. Verify no draft leaks or disappears. Repeat with unsaved tag
   selection and with goal/Switch sheets; privacy transitions must not dismiss
   them, start a timer, commit edits or crash. Do not include personal keyboard
   suggestions or notifications in recordings.
6. With names private by default, inspect actual complication/Smart Stack/control
   and goal notification surfaces. Repeat after opting into project names, then
   lower the wrist/lock and restrict previews. Names must be suppressed in the
   private state; active/paused time/state remains neutral where intended. A
   Simulator or app-hosted widget preview does not satisfy this step.

Record each row as Pass/Fail/Not run for the exact build, with a short sanitized
observation. A failed row stays open. Physical transport, long-goal delivery and
multi-hour battery measurements belong to their separate WAT-24/25 scenarios;
do not expand this accessibility session into repeated probe troubleshooting.
