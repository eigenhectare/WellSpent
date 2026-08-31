# REL-03 App Store release preparation

This is a non-final release package. Product metadata and technical
declarations are prepared now, but REL-03 remains blocked until REL-02 beta is
complete and the signed post-beta archive passes the release checklist.

## Current binary audit

### Privacy

- User-created project names, optional emoji/color identity, notes, tags, and
  session timestamps remain in the local SwiftData store.
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
| App Group | App and widget use `group.com.drewreilly.billablehours` | Required for durable Lock Screen Stop handoff |
| Live Activities | Enabled in app and widget Info.plists | Core timer projection; source session remains SwiftData |
| Calendar | Absent | Do not mention Calendar integration |
| iCloud/CloudKit | Absent | Do not claim sync or backup |
| Network client | Absent | No account, server, analytics, or telemetry |
| Notifications | Absent | Do not claim timer reminders |
| Non-exempt encryption | `false` | Reconfirm during upload/export-compliance flow |

### Versioning

- Marketing version: `0.1.0`
- Build number: `1`
- App and widget Info.plists inherit the same canonical settings.
- Increase the build number for every TestFlight or App Store upload.

## Metadata draft — English (U.S.)

### Name

`Billable Hours`

### Subtitle

`Track time. Trust the total.`

### Promotional text

`Start with one tap, annotate completed work, and turn exact local timestamps into day, week, and project totals you can explain.`

### Description

Billable Hours is a focused, local-first time tracker for professionals who
need dependable records without a complicated workspace.

Start work with one tap. Switch projects at one exact timestamp. Stop from the
app, Lock Screen, or Dynamic Island, then add a note and reusable tags when the
work is fresh.

Review exact totals by day, week, or project. Every aggregate opens its
contributing segments and source sessions, so you can understand where the
time came from before preparing a timesheet.

Features:

- Timestamp-backed Start, Switch, and Stop
- Lock Screen and Dynamic Island timer controls
- Optional emoji and color identity for projects
- Completion notes and configurable tags
- Manual entries and corrections with overlap warnings
- Exact Day, Week, and Project reports with source-session drill-down
- Privacy-first Lock Screen labels
- Local storage with no account, advertising, analytics, or tracking

Billable Hours does not upload project names, work notes, tags, or session
records. Your work data stays on your iPhone unless you choose to share it
through an operating-system feature outside the app.

### Keywords

`billable,time,timer,timesheet,consultant,lawyer,freelance,projects,hours,worklog`

### Categories

- Proposed primary: Productivity
- Proposed secondary: Business

### URLs and ownership fields

The owner must provide these before submission:

- Privacy Policy URL — required, publicly accessible
- Support URL — required for the version submission
- Marketing URL — optional
- Copyright holder and year
- Developer support contact

### App Review notes draft

Billable Hours requires no account and has no server component. On first
launch, create a project, tap its timer button, then use Switch or Stop. A Live
Activity appears on supported iPhones. Project names are hidden there by
default; Settings contains the explicit visibility opt-in. Completed sessions
are available in Session History and Reports. The app requests no Calendar,
iCloud, notification, advertising, or tracking permission.

## Asset inventory

| Asset | Status | Requirement before submission |
| --- | --- | --- |
| Production AppIcon asset catalog | Missing | Design and approve; verify all required sizes and no transparency where prohibited |
| In-app icon | Generic during development | Replace through the production AppIcon catalog |
| iPhone screenshots | Missing | Capture from the post-beta Release build using fictitious data |
| App previews | Optional, not planned | Omit unless a polished preview is produced |
| Launch screen | System configuration present | Inspect in signed Release build |
| Localization | English only | Confirm intended launch storefronts |

Recommended screenshot story:

1. One-tap project timers with emoji/color identity.
2. Active timer and Switch workflow.
3. Completion note and reusable tags.
4. Day/Week report totals with project breakdown.
5. Aggregate drill-down to exact source sessions.
6. Privacy-first Lock Screen and Dynamic Island presentation.

Use only fictitious names and notes. Capture the same release build and visual
theme across the set; do not show debug fixtures, status alerts, or personal
notifications.

## Release checklist

### Before TestFlight

- [ ] REL-02 candidate source is committed and the tree is clean.
- [ ] Version/build values match across app and widget.
- [ ] Strict lint, privacy audit, unit, UI, migration, and Release builds pass.
- [ ] A signed archive embeds both privacy manifests in the expected bundles.
- [ ] TestFlight beta information and sanitized contact details are complete.
- [ ] Export-compliance answer matches the archived binary.

### Before App Review

- [ ] REL-02 exit gate is complete and all P0/P1 beta findings are closed.
- [ ] Production AppIcon and final screenshots are approved.
- [ ] Privacy Policy URL and Support URL are live.
- [ ] Xcode privacy report matches the App Store Connect privacy answers.
- [ ] Age rating questionnaire is complete.
- [ ] Category, keywords, description, copyright, price, and availability are set.
- [ ] Agreements, tax, banking, and regional compliance requirements are current.
- [ ] Clean install and oldest-supported upgrade both pass on a signed build.
- [ ] Physical-device smoke covers Start, Switch, Stop, relaunch, Reports, and
      the IDK-353 Settings route.
- [ ] App Review notes describe the no-login flow and Live Activity behavior.

### Submission and release

- [ ] Upload a new build number and wait for processing.
- [ ] Verify bundle identifiers, entitlements, embedded extension, version, and
      privacy manifests in App Store Connect.
- [ ] Attach the intended build to the version and complete the review contact.
- [ ] Submit for review only with no unresolved metadata warning.
- [ ] Use manual release unless a deliberate release date is approved.
- [ ] After release, install from the App Store and repeat the core smoke test.
