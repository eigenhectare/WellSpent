# Release-candidate validation record

## Environment

- Validation date: August 30, 2026 (America/New_York)
- Source baseline: `cf0f508` (`Initial Billable Hours application baseline`)
- Xcode: 26.6 (`17F113`)
- Swift: 6.3.3
- Simulator runtime: iOS 26.5
- Primary simulator: iPhone 17 Pro
- Candidate version/build: `0.1.0 (1)`

Generated products and result bundles live under `.derivedData/` and are not
committed. This record captures the durable commands and outcomes.

## Automated evidence

| Check | Command or scope | Result |
| --- | --- | --- |
| Strict formatting | `scripts/lint.sh` | Pass |
| Privacy source audit | `scripts/privacy-audit.sh` | Pass; no production logging, networking, tracking, analytics, or diagnostics API |
| Debug simulator build | `scripts/ci.sh` | Pass |
| Release simulator build | `scripts/ci.sh` | Pass |
| Unit and migration tests | `scripts/ci.sh` | Pass — 100 tests, 0 failures |
| Primary UI flows | `BillableHoursUITests` | Pass — 28 tests, 0 failures |
| Automated accessibility flows | `BillableHoursAccessibilityUITests` | Pass — 6 tests, 0 failures |
| Generic iPhone Release compile | Release, `generic/platform=iOS`, signing disabled | Pass |
| Privacy manifest packaging | Inspect generic-iPhone Release app and widget bundles with `plutil` | Pass — both final executable bundles embed valid manifests with the expected reasons |
| Clean-checkout reproducibility | Pre-boot iPhone 17 Pro; set `CI_SIMULATOR_DESTINATION` to its UDID; run `scripts/verify-clean-checkout.sh` | Pass — fresh clone, Debug and Release builds, privacy/lint audits, and 100 tests with 0 failures |

The persistence suite includes opening the oldest shipped v1 fixture through
the migration harness and initializing the v2 project, session, tag, and tag
assignment entities. UI coverage includes optional project emoji, multiple
session tags, tag add/removal, disabled-Live-Activity recovery, reporting
drill-down, correction/deletion, privacy defaults, relaunch, and failure paths.

The initial sandboxed CI attempt could not access CoreSimulator and Xcode's
preview macro service. The identical pipeline passed after being granted normal
Xcode/Simulator access; this was an execution-environment denial, not a product
failure.

Two initial clean-checkout attempts built successfully but Xcode's simulator
test runner timed out before establishing its connection. After the iPhone 17
Pro simulator was explicitly shut down, booted to a ready state, selected by
UDID, and given a fresh app install, the complete clean-checkout pipeline passed
in 5.8 seconds of test execution. Set `KEEP_CLEAN_CHECKOUT=1` when running the
verification script only when a failure workspace needs to be retained for
diagnosis; cleanup remains automatic by default.

## Packaging audit

- App and widget versions now inherit `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION` from `project.yml`.
- `ITSAppUsesNonExemptEncryption` is `false`; the app implements no custom or
  non-exempt encryption.
- The app privacy manifest declares app-only `UserDefaults` (`CA92.1`) and App
  Group `UserDefaults` (`1C8F.1`).
- The widget privacy manifest declares App Group `UserDefaults` use with
  approved reason `1C8F.1`, covering the statically linked shared code in the
  extension executable.
- Both manifests declare no tracking domains and no collected data types.
- The app and Live Activity extension share only the Billable Hours App Group
  entitlement. Calendar, iCloud, advertising, analytics, and notification
  capabilities are absent from this release.

## Remaining non-code release gates

- Produce and approve the production AppIcon asset.
- Capture final App Store screenshots from the post-beta build.
- Publish a privacy policy and support page at public URLs.
- Complete the age-rating, pricing, availability, agreements, and compliance
  fields in App Store Connect.
- Complete REL-02 with representative beta users and resolve all P0/P1 findings.
- Produce a signed archive, generate its Xcode privacy report, and compare that
  report with the declarations in `APP-STORE-RELEASE.md` before submission.
