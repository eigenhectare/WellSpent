# WellSpent

Native, iPhone-first time tracker. The app now includes first-launch
onboarding, one-tap timestamp-backed Start/Switch/Stop, completion notes and
configurable tags, emoji/color project identity, manual corrections, overlap
warnings, and exact Day, Week, and Project reports with source-session
drill-down. Lock Screen and every
Dynamic Island presentation family are implemented with a privacy-first label,
system-derived elapsed time, and a true Stop control. Persisted timer commands
now drive the production ActivityKit lifecycle, including durable Lock Screen
Stop handoff, completion routing, foreground repair, and long-session recovery.

The authoritative store is the versioned SwiftData v2 schema, with a tested
lightweight migration from the oldest v1 store. Views invoke the
project, timer, and session command boundaries rather than mutating records.
Reporting is a pure calendar-aware engine whose segments preserve source
identity and handle local midnight, configurable weeks, daylight-saving days,
active sessions, and fully counted overlaps.

See [DEVELOPMENT.md](DEVELOPMENT.md) for project generation, build, and test
commands. The repository also includes a secrets-free pull-request CI workflow
whose local entry point is `scripts/ci.sh`.

Implementation contracts and scope boundaries are documented in
[CORE-EXPERIENCE.md](CORE-EXPERIENCE.md), [REPORTING.md](REPORTING.md),
[LIVE-ACTIVITY-LIFECYCLE.md](LIVE-ACTIVITY-LIFECYCLE.md),
[RELEASE-HARDENING.md](RELEASE-HARDENING.md),
[ACCESSIBILITY.md](ACCESSIBILITY.md), and [PRIVACY.md](PRIVACY.md). Beta and
release operations are captured in [BETA-TESTING.md](BETA-TESTING.md),
[RELEASE-CANDIDATE-VALIDATION.md](RELEASE-CANDIDATE-VALIDATION.md), and
[APP-STORE-RELEASE.md](APP-STORE-RELEASE.md).
