# WAT-27 — Watch product and support materials

Status: In Progress. **Draft only; integrated locally but not published or
submission-ready.** Build 3's source-bound drafts remain visual-design evidence,
but build 3 failed App Store processing and cannot be final submission evidence.
Final build-4 captures, visual sign-off, retention evidence, App Store Connect
warnings and independent install review remain open.

## Screenshot story and icon

The five-screen draft sequence is Projects → Time Goal → active metrics →
Controls → saved summary. `WatchStoreAssetDraftUITests` captures the actual app
UI using disconnected DEBUG fixtures and fictitious data. Separate seeded states
are used; this sequence is not an end-to-end transport demonstration. No image
is composited, resized or presented as a signed-candidate capture.

Named review assets and their draft-only manifest are retained in
`.derivedData/WAT27-DraftAssets1/`; its `README.md` is a local visual gallery.
The preferred-size second set is retained in
`.derivedData/WAT27-DraftAssets4/` with a machine-readable manifest.

Run that test on an idle Watch Simulator, then export its successful bundle:

```sh
bash scripts/watch-store-assets-export.sh BUNDLE.xcresult NEW_DRAFT_DIRECTORY
```

Initial proof: `.derivedData/WAT27-DraftScreens1.xcresult`, one passed capture
test, five PNGs plus accessibility trees; log `/tmp/wat27-draft-screens1.log`.
Native Ultra 3 captures are all **422 × 514**, opaque PNGs. All five were visually
inspected: ordinary text, fictitious names, goal choice, live state and saved
billable duration are readable. The picker/goal/summary naturally continue below
the viewport. These are a first composition pass, not final visual approval.

Preferred-size proof: `.derivedData/WAT27-DraftScreens3.xcresult` contains one
passed capture test with no failures. Export validation produced five opaque,
unmodified **416 × 496** PNGs in `.derivedData/WAT27-DraftAssets4/`; its manifest
records individual SHA-256 hashes, `draftOnly: true` and
`releaseCandidate: false`. All five were visually inspected together: headings,
fictitious project identity, controls, state, progress and saved duration are
readable without clipping or compositing. The summary's remaining rows naturally
continue below the viewport. A prior restricted launch/export attempt failed
inside CoreSimulator/xcresulttool permissions and is not acceptance evidence.
This set is the preferred composition draft, but it is still DEBUG fixture output
and must be recaptured from the exact signed candidate before submission.

Physical composition proof: the same capture test passed on a physical Apple
Watch Ultra 2 running watchOS 26.6 after the production paired-install
prerequisite passed. The five unmodified, opaque **410 × 502** screenshots were
visually reviewed together and show no clipping, overlap or privacy issue.
They remain DEBUG ephemeral-fixture captures, not a signed-candidate or
end-to-end transport sequence. The identifier-free record and individual
SHA-256 hashes are retained in
`.derivedData/WAT23-PhysicalUISmoke2-Sanitized/summary.json`. Raw Xcode results
and exports were removed because their metadata named the physical device and
included its identifier.

Apple currently accepts 422 × 514 and 416 × 496 among its Watch sizes and requires
one consistent size across localizations. The physical 410 × 502 evidence is a
device QA artifact, not an App Store screenshot size. Final capture can use the
preferred Series 11 416 × 496 set; recapture all five together, never resize any
set to pretend it came from another display. Recheck [screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/)
before upload (checked September 3, 2026).

The existing Watch icon was visually inspected: WellSpent's navy/teal clock-check
mark with an amber arc, not a fitness/Workout icon. It is the same branded
1024 × 1024 opaque PNG used by the phone, in a Watch-specific asset catalog.
SHA-256: `812345c5b6933ae4c1597386e3df52474cc6a7095bf46da6e0a64e89ec3517c9`.
Compiled asset presence passes WAT-26's preflight. Direct 44, 60 and 80 pixel
downsamples were also inspected: the clock/check silhouette and amber progress
arc remain distinct at each size, all three files are opaque, and recognition
does not depend on text or fine detail. The reproducible sizes and hashes are in
`.derivedData/WAT27-IconQA1/manifest.json`. This closes draft small-size
legibility QA only; final circular masking and the App Store-processed candidate
asset still need review.

Suggested captions, kept outside the unmodified captures:

1. Give your time a project.
2. Set a time goal—or keep it open.
3. Know what counts.
4. Pause, resume, or switch projects.
5. Finish with a saved record.

## English (U.S.) product copy draft

Name: **WellSpent**. Retain subtitle: **Track time. Trust the total.**

Promotional text:

> Track billable time from your wrist. Start instantly, pause when work pauses,
> switch projects, and review your saved time on iPhone.

Description addition:

> WellSpent for Apple Watch keeps your timer close at hand. Set up your projects
> on iPhone, then start from your Watch with one tap—there is no countdown.
> Pause and resume without counting your break, switch projects at one boundary,
> and end with a saved summary. Add a note or tags while the work is fresh.
>
> Choose an open timer or a time goal. Optional local goal alerts let you know
> when your counted time reaches the goal; they never stop the timer for you.
>
> Cached projects remain available when your iPhone is unavailable. Changes are
> saved on the Watch and shown as pending until acknowledged. When both devices
> changed the same timer, review the conflict on iPhone instead of silently
> losing one version. Review your history and reports on iPhone.
>
> WellSpent is local-first, with no account, advertising or in-app analytics.
> Your paired devices exchange the information needed for your timer and project
> list. Project names are hidden on glanceable system surfaces by default.

Do not carry forward the old iPhone-only wording “stays on this iPhone” as a
description of the paired app. Do not claim instant synchronization, guaranteed
background execution, remote wipe, backup recovery, or unlimited offline storage.
Final privacy wording requires WAT-24–26 evidence.

## Repository copy integration — September 3

The paired-product draft is now integrated into the actual repository release
materials rather than living only in this handoff:

- `APP-STORE-RELEASE.md` contains the Watch description, promotional text,
  reviewer path, five-screen story and candidate-only asset gates.
- `SUPPORT.md` contains setup, offline/Pending, conflict, notification,
  reinstall/unpair, privacy, accessibility and privacy-safe contact guidance.
- `PRIVACY.md` records the Watch Connectivity disclosure and cautious local
  retention language without promising remote erase or backup recovery.
- `ACCESSIBILITY.md` records current Watch adaptations and the still-required
  physical VoiceOver, haptic, dictation, Always On and WidgetKit checks.
- `BETA-TESTING.md` now describes a combined build and adds six paired Watch
  scenarios, candidate identity, cohort, privacy-safe feedback and exit gates.
- `README.md` links the support material and names the current SwiftData v6
  store instead of the superseded v5 description.

`scripts/watch-release-copy-check.sh` prevents the obsolete “stays on this
iPhone” claim and stale iPhone-only beta identity from returning, and verifies
the required paired-app boundaries above. It passes locally and is a clean-CI
source gate. These are repository drafts only; no public page or App Store field
was changed.

## Support and privacy FAQ draft

**How do I start?** Install WellSpent on your iPhone and its paired Watch. Open
the phone app, create a project, then open WellSpent on the Watch and allow the
project list to arrive. Tap a project's play button for an immediate open timer.
Options opens Time Goal; choosing a duration also starts immediately. Project
creation and management remain on iPhone. WC Probe is not needed by customers.

**What happens without my phone?** Already cached projects can be timed locally.
Pending changes remain on the Watch until acknowledged. Keep the pair available
and open both apps to help resume synchronization. Do not repeatedly start a
second timer to clear Pending. Cached totals may be older than your local timer.
There is a bounded local queue; if the app cannot save more work, follow its
error guidance rather than assuming the action succeeded.

**What does review required mean?** Both devices may have changed the same work.
Open conflict review on iPhone and inspect both histories before choosing a
resolution. Do not erase, reinstall or unpair to bypass review.

**Are notifications required?** No. Enable Goal alerts explicitly if wanted.
Denying permission does not prevent timers or goals. Alerts are local, use
counted time rather than paused time, and do not end the timer. Delivery depends
on system authorization, preview and Focus settings. An offline Watch cannot
immediately learn that the phone changed or ended a run.

**What if I delete the app, reinstall or unpair?** Unsynchronized Watch time is
device-local and may be lost. First confirm that the intended time appears in
iPhone history and resolve pending/review states. Do not rely on backup/restore
or a replacement Watch to recover an outbox. Exact retention behavior must be
published from the authorized WAT-24 test results, not guessed from restart tests.

**What is shared?** The paired devices exchange project/tag choices, timer
commands, acknowledgements and snapshots through Watch Connectivity. The
production app has no developer server, analytics SDK or remote push registration.
Apple's TestFlight is separate: beta testing shares diagnostic/usage information
and submitted feedback with developers under [TestFlight's terms](https://testflight.apple.com/).
Avoid including client names, notes or personal notifications in support reports.

## Accessibility copy draft

> WellSpent uses labeled controls, text equivalents for timer state and scalable
> layouts. Timer actions do not require interpreting a color, animation or
> haptic. If a control or message is difficult to use, contact support with your
> app version, device class and accessibility setting—without private work data.

Do not claim fully verified VoiceOver, Always On, dictation or accessibility
labels until the final WAT-23 device evaluation is complete. Support must explain
the actual remaining limitations, not turn a Simulator audit into certification.

## App Review notes draft

No login, paid service or HealthKit setup is required. On iPhone, create two
fictitious projects, then open WellSpent on the paired Watch. Start a project,
observe its elapsed time, swipe right for Controls, Pause and Resume, choose New
to switch projects, and End with confirmation. The saved summary supports notes
and tags. Inspect the resulting history and reports on iPhone after sync.

For a time goal, open project Options and choose a duration; the timer starts
immediately with no countdown. Goal alerts are optional and requested only when
enabled. Denial leaves timer/goal tracking available. Alerts do not end runs.
Watch Connectivity provides paired synchronization, not server sync; offline
work remains visibly pending until acknowledged. Conflicts are reviewed on
iPhone. Project names are private on glanceable system surfaces by default.
The app does not use HealthKit, Workout Processing or extended runtime sessions.

Before submission: replace draft screenshots with exact-candidate captures,
proof every asset after processing, reconcile privacy/support claims, have a
reviewer follow these steps unaided, and verify there are no unresolved App Store
Connect warnings. No public page, metadata field or review message has been sent.

## Build-3 source binding and public-page correction — September 4

The five preferred-size screens were regenerated after the approved build-3
source checkpoint. The single capture test passed in 18.222 seconds and exported
five opaque, unmodified 416 × 496 PNGs to
`.derivedData/WAT27-Build3DraftAssets1/`. All five were visually inspected in
story order—Projects, Time Goal, active metrics, Controls, saved summary—with no
clipping, overlap or private data observed. The sanitized binding record at
`.derivedData/WAT27-Build3AssetsCandidateBinding1/summary.json` ties their
manifest to source commit `8ead2308259fa030abdd0d81ef3ba9ab0199c7b9` and the
build-3 production-source manifest. It deliberately records
`binaryCapture: false` and `submissionReady: false`: these are DEBUG isolated
fictitious fixtures, not the installed exported/TestFlight binary.

Review of the live privacy, support and root pages found stale iPhone-only claims,
including no notification access and no paired exchange. The corresponding
GitHub Pages repository was corrected locally to disclose the iPhone/Watch
product, Watch Connectivity, local goal alerts, Pending/Review Required recovery,
and uninstall/unpair/backup cautions. The isolated clean commit is `3a9b9cb`
(`docs: add Apple Watch support and privacy guidance`) on branch
`codex/wellspent-watch-support` in
`.derivedData/WellSpentSupportSite`. Publication did not occur: the available
Git credential is authenticated as an account without write access and the push
was rejected with HTTP 403. Publish and visually review these exact pages using
an authorized GitHub account before attaching their URLs to the submission.

### Build-4 draft regeneration — September 4

After build 3 failed App Store Siri validation, the five preferred-size screens
were regenerated from build 4's unchanged production UI. The focused capture
passed in 18.439 seconds and exported five opaque, unmodified 416 × 496 PNGs to
`.derivedData/WAT27-Build4DraftAssets1/`. Visual review of Projects, Time Goal,
active metrics, Controls and saved summary found no clipping, overlap or private
data. The binding record at
`.derivedData/WAT27-Build4AssetsCandidateBinding1/summary.json` ties the asset
manifest to commit `ad70ffc6c3f66510151c541e7316101e96f053ab` and the build-4
production-source manifest. It deliberately keeps `binaryCapture: false` and
`submissionReady: false`; final processed-distribution captures and sign-off
remain required.
