# REL-03 App Store release preparation

Watch-candidate boundary: the historical iPhone readiness checks below are not
sign-off for the paired app. Use WAT-26-ARCHIVE-VALIDATION.md,
WAT-27-STORE-MATERIALS-DRAFT.md and WAT-28-BETA-RELEASE-RUNBOOK.md for the joint
candidate. Watch copy/assets are drafts, and signed/device/distribution gates
remain open. Do not publish the old iPhone-only retention wording for Watch.

Product metadata, technical declarations, screenshot drafts, repository support
copy, and the support contact are prepared for version 0.1.0. The remaining work
includes physical retention/accessibility/resource gates, an exact signed
candidate, candidate screenshots, public-page publication/review, and the App
Store Connect upload/submission workflow.

## Current binary audit

### Privacy

- User-created project names, optional emoji/color identity, notes, tags, and
  session timestamps remain in the local SwiftData store and are excluded from
  iCloud and computer device backups.
- The app contains no networking, advertising, analytics, crash-reporting, or
  third-party runtime dependency.
- Production source contains no diagnostic logging calls.
- Lock Screen project names are disabled by default and require explicit opt-in.
- The privacy manifests declare no tracking and no collected data types.
- The app manifest declares app-only `UserDefaults` (`CA92.1`) plus App Group
  `UserDefaults` (`1C8F.1`); the widget manifest declares App Group
  `UserDefaults` (`1C8F.1`) for its statically linked shared code.

Based on the current binary, the proposed App Store Connect answer is **No, we
do not collect data from this app**. Reconfirm this against Xcode's privacy
report from the signed submission archive. A public privacy-policy URL is still
required even when no data is collected.

Apple references:

- [Privacy manifests](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Required-reason APIs](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [Manage App Store privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)

### Entitlements and capabilities

| Capability | Current state | Release statement |
| --- | --- | --- |
| App Group | App and widget use `group.com.drewreilly.wellspent` | Required for durable Lock Screen Stop handoff |
| Live Activities | Enabled in app and widget Info.plists | Core timer projection; source session remains SwiftData |
| Calendar | Absent | Do not mention Calendar integration |
| iCloud/CloudKit | CloudKit absent; local activity data excluded from device backups | Do not claim sync; disclose the no-backup policy |
| Network client | Absent | No account, server, analytics, or telemetry |
| Notifications | Optional local duration-goal alerts in the Watch candidate | Permission is requested only when enabled; no push registration or server. Physical delivery remains a Watch release gate. |
| Non-exempt encryption | `false` | Reconfirm during upload/export-compliance flow |

### Versioning

- Marketing version: `0.1.0`
- Current engineering build number: `2`; select a higher build for the next
  TestFlight/App Store upload and never reuse it for different bytes
- App and widget Info.plists inherit the same canonical settings.
- Increase the build number for every TestFlight or App Store upload.

## Metadata draft — English (U.S.)

### Name

`WellSpent`

### Subtitle

`Track time. Trust the total.`

### Promotional text

`Track billable time from your wrist. Start instantly, pause when work pauses, switch projects, and review saved time on iPhone.`

### Description

WellSpent is a focused, local-first time tracker for professionals who need
dependable records without a complicated workspace—on iPhone and Apple Watch.

Start work with one tap. Switch projects at one exact timestamp. Stop from the
app, Lock Screen, or Dynamic Island, then add a note and reusable tags when the
work is fresh.

Set up projects on iPhone, then start from Apple Watch with one tap—there is no
countdown. Pause and resume without counting the break, switch projects at one
shared boundary, and end with a saved summary. Add a note or tags while the work
is fresh.

Choose an open timer or a time goal. Optional local goal alerts let you know when
counted time reaches the goal; they never stop the timer for you.

Cached projects remain available when the iPhone is unavailable. Changes are
saved on the Watch and shown as pending until acknowledged. If both devices
changed the same timer, review both versions on iPhone instead of silently
losing one.

Review exact totals by day, week, or project. Every aggregate opens its
contributing segments and source sessions, so you can understand where the
time came from before preparing a timesheet.

Features:

- Timestamp-backed Start, Switch, and Stop
- Immediate Apple Watch Start, Pause, Resume, Switch, End and saved summary
- Open timers and optional duration goals with local alerts
- Offline Watch timing with visible pending and conflict-review states
- Privacy-aware Watch complications, Smart Stack and controls
- Lock Screen and Dynamic Island timer controls
- Optional emoji and color identity for projects
- Completion notes and configurable tags
- Manual entries and corrections with overlap warnings
- Exact Day, Week, and Project reports with source-session drill-down
- Privacy-first Lock Screen labels
- Local storage with no account, advertising, analytics, or tracking

WellSpent has no account, advertising or in-app analytics. The paired devices
exchange the project, timer and annotation information needed to keep the local
ledger consistent through Apple's Watch Connectivity. Project names are hidden
on glanceable system surfaces by default. Unsynchronized Watch changes are
device-local and may be lost if the app is deleted, devices are unpaired or the
Watch is replaced; confirm intended time appears in iPhone history first.

### Keywords

`billable,time,timer,timesheet,consultant,lawyer,freelance,projects,hours,worklog`

### Categories

- Proposed primary: Productivity
- Proposed secondary: Business

### URLs and ownership fields

- Privacy Policy URL — `https://wellspent-holdings.github.io/privacy/`
- Support URL — `https://wellspent-holdings.github.io/support/`
- Public support email — `wellspent_support@pm.me`
- Marketing URL — omitted
- Copyright — `2026 Drew Reilly`
- Private App Review contact — use the Apple account holder information in App Store Connect

### App Review notes draft

WellSpent requires no login, paid service or HealthKit setup and has no developer
server. On iPhone, create two fictitious projects, then open WellSpent on the
paired Apple Watch. Tap a project's play button to start immediately with no
countdown. Observe elapsed time, swipe right for Controls, Pause and Resume,
choose New to switch projects, and End with confirmation. The saved summary
supports notes and tags. Inspect the resulting history and reports on iPhone
after synchronization.

For a time goal, open project Options and choose a duration; that choice starts
immediately. Goal alerts are optional and notification permission is requested
only when enabled. Denial leaves timer and goal tracking available. Alerts use
counted billable time, exclude pauses and never end a run. Delivery depends on
system authorization, previews and Focus settings.

Watch Connectivity provides paired device-to-device exchange, not server sync.
Offline work remains visibly pending until acknowledged; concurrent changes are
preserved for conflict review on iPhone. Project names are private on glanceable
system surfaces by default. The app uses no HealthKit, Workout Processing,
extended runtime session, Calendar, CloudKit, advertising, analytics or tracking
service.

## Asset inventory

| Asset | Status | Requirement before submission |
| --- | --- | --- |
| Production AppIcon asset catalog | Ready | Present as a 1024 × 1024 opaque production asset |
| In-app icon | Ready | Uses the production AppIcon catalog |
| iPhone screenshots | Ready | Six English (U.S.) 6.9-inch captures at 1320 × 2868 using fictitious data |
| Watch screenshot composition | Draft | Five visually reviewed, opaque 416 × 496 Simulator captures with a SHA-256 manifest; recapture from the exact signed candidate |
| Watch icon | Engineering-ready | Watch-specific catalog contains the opaque branded 1024 × 1024 icon; inspect masking and App Store processing on the candidate |
| App previews | Optional, not planned | Omit unless a polished preview is produced |
| Launch screen | System configuration present | Inspect in signed Release build |
| Localization | English (U.S.) only | United States-only launch confirmed |

Recommended iPhone screenshot story:

1. One-tap project timers with emoji/color identity.
2. Active timer and Switch workflow.
3. Completion note and reusable tags.
4. Day/Week report totals with project breakdown.
5. Aggregate drill-down to exact source sessions.
6. Privacy-first Lock Screen and Dynamic Island presentation.

Use only fictitious names and notes. Capture the same release build and visual
theme across the set; do not show debug fixtures, status alerts, or personal
notifications.

Recommended Watch screenshot story, using one unmodified accepted size across
the set:

1. Give your time a project.
2. Set a time goal—or keep it open.
3. Know what counts.
4. Pause, resume, or switch projects.
5. Finish with a saved record.

## Release checklist

### Before TestFlight

- [ ] The verified candidate source is committed, pushed, and the tree is clean.
- [x] Version/build values match across app and widget.
- [x] Strict lint, privacy audit, unit, UI, migration, and Release builds pass.
- [ ] A signed archive embeds both privacy manifests in the expected bundles.
- [ ] TestFlight beta information and sanitized contact details are complete.
- [ ] Export-compliance answer matches the archived binary.

### Before App Review

- [x] Automated release validation has no unresolved test failures.
- [ ] Production phone/Watch icons and screenshots are verified from the exact
      signed candidate after App Store processing.
- [ ] Privacy Policy URL and Support URL are reviewed against the paired-product
      copy and confirmed live.
- [ ] Xcode privacy report matches the App Store Connect privacy answers.
- [ ] Age rating questionnaire is complete.
- [ ] Category, keywords, description, copyright, price, and availability are set.
- [ ] Agreements, tax, banking, and regional compliance requirements are current.
- [ ] Clean install and oldest-supported upgrade both pass on a signed build.
- [ ] Physical-device smoke covers Start, Switch, Stop, relaunch, Reports, and
      the IDK-353 Settings route.
- [x] App Review notes describe the no-login flow and Live Activity behavior.

### Submission and release

- [ ] Upload a new build number and wait for processing.
- [ ] Verify bundle identifiers, entitlements, embedded extension, version, and
      privacy manifests in App Store Connect.
- [ ] Attach the intended build to the version and complete the review contact.
- [ ] Submit for review only with no unresolved metadata warning.
- [ ] Use manual release unless a deliberate release date is approved.
- [ ] After release, install from the App Store and repeat the core smoke test.
