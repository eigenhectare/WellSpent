# WAT-28 — Beta, release and incident runbook

Status: In Progress for preparation. **No tester invited, submission updated,
review approved, or version released.** Build 3 was uploaded but failed App
Store processing; corrected build 4 is distribution-export verified, validated,
uploaded, processed and Ready to Submit. WAT-26/27 and the open quality/device
gates remain prerequisites. This runbook grants no authority to message testers
or erase personal data.

## Candidate ledger

Record actual candidate commit, version/build, archive and export hashes,
processed-build identity, dSYM UUIDs, Xcode/SDK, installation channel, device
aliases/OS versions, approved asset manifest and relevant issue/result links.
Each result needs date, tester alias, case, outcome and sanitized evidence.
Use Pass / Fail / Not run / Inconclusive; retain failed attempts. A new binary
or material capability change resets the affected archive and regression gates.

## Internal beta, then external beta

- [x] WAT-26's real signed/exported candidate and upload validation pass.
- [ ] Verify beta description, contact, encryption answers and What to Test.
  Obtain approval for the exact build, recipient cohort and invitation text.
- [ ] Internal testers first: standard and Ultra display classes, oldest
  supported OS/store upgrade and current OS where available. Missing coverage
  remains Not run; do not invent hardware or tester counts.
- [ ] Exercise automatic/manual companion install, phone-first setup and update
  from the previous iOS-only version without reset. Confirm actual counterpart
  detection before treating failures as connectivity problems.
- [ ] Test Start/Pause/Resume/Switch/End, saved summary/notes/tags, history/reports,
  optional alerts, complication/control privacy, and delayed acknowledgement.
- [ ] Execute WAT-24's authorized offline, lifecycle, conflict and long-duration
  cases; validate WAT-25's accepted battery/storage budget on the real pair.
  Reinstall/unpair/erase require a dedicated dataset and explicit permission.
- [ ] Triage all feedback and crashes. Only then approve a small external cohort
  and complete any required beta review. Repeat the same installation/core/
  offline cases using TestFlight distribution, not Xcode installation.
- [ ] Exit only with no unresolved data-loss, duplicate-time, privacy,
  accessibility, battery or install blocker. Archive the accepted evidence.

Apple's [TestFlight workflow](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)
separates upload, internal/external groups, beta review and feedback. This project
does not treat successful processing or an invitation as successful testing.

### What to Test — draft

> Use fictitious work only. Create two projects on iPhone, open WellSpent on your
> paired Watch, and test immediate Start, Pause, Resume, New/Switch and End.
> Confirm paused time is excluded and completed work reaches iPhone history once.
> Try an optional time goal with alerts both disabled and enabled. Check that
> default widgets/controls do not expose project names. If a change is Pending,
> keep it intact and reconnect/open the pair; do not reinstall to clear it.
> Report the version/build, device class, OS, last successful action and visible
> result. Omit private project names, notes, account details and notifications.
> Do not perform uninstall, erase or unpair tests without a separately approved
> dedicated dataset and recovery plan.

### Build-3 beta package — September 4

`.derivedData/WAT28-Build3BetaPackage1/` contains an identifier-free candidate
ledger, `WhatToTest.txt`, and a concise operator README. It binds version 0.1.0
(3) to source commit `8ead2308259fa030abdd0d81ef3ba9ab0199c7b9`, the clean
381-test CI result, the four-component archive inspection and the source-bound
draft-asset review. The ledger correctly records export, upload, processed-build
confirmation and both tester cohorts as false. No invitation was sent and no
external beta was created; those scopes remain separately gated.

App Store Connect later retained 0.1.0 (3) as a failed upload with error 90626,
Invalid Siri Support; it never became an installable or selectable beta build.

### Build-4 beta package — September 4

`.derivedData/WAT28-Build4BetaPackage1/` binds 0.1.0 (4) to pushed source commit
`ad70ffc6c3f66510151c541e7316101e96f053ab`, the clean 381-test CI result and the
strictly inspected four-component archive. Its compiled Start intent description
removes the term rejected by Apple's server. Xcode validation/upload passed and
App Store Connect now records the exact build as Complete and Ready to Submit.
Both tester cohorts remain false; no tester or external cohort was added.

Authenticated build-metadata inspection independently reports build 4 as
Validated, with symbols included, non-exempt encryption `No`, Watch-only `No`,
and device family iPhone + Apple Watch. Its TestFlight page has zero groups,
zero individual testers and blank What to Test, beta-description, feedback,
URL, contact and review-note fields. Those fields remain unsent drafts; no Save,
group, invitation or cohort action occurred.

The local App Store distribution export preserves 0.1.0 (4), includes symbols,
and passed signature, App Store profile, entitlement, package, architecture and
privacy checks for all four components. Its IPA SHA-256 is
`93946e48f157576de8e41689276599806a7aba5ea93afcba6a3d21afe7db6fe0`; sanitized
inspection evidence is at
`.derivedData/WAT26-Build4DistributionExportInspection1/summary.json` and the
beta package records the same binding.

### Repository beta-package integration — September 3

`BETA-TESTING.md` now identifies a combined iPhone/Watch build, requires a new
non-reused build number and exact processed-build identity, separates internal
from external cohorts, and adds six paired Watch scenarios. Those scenarios
cover immediate Start, complete controls/history, detached offline convergence,
conflict review, goals/system-surface privacy, physical accessibility and only
explicitly authorized retention/long-run rows. Its privacy-safe feedback form
records both device classes and install/version alignment.

`scripts/watch-release-copy-check.sh` verifies that the beta, App Store, support,
privacy and accessibility drafts retain these paired-product boundaries and do
not regress to the old iPhone-only retention claim. The complete current CI
source-gate sequence passes. No TestFlight group, tester, build, review record or
public page was changed by this local preparation.

## Crash and feedback triage

1. Preserve the build and reproduction conditions. Identify whether failure is
   installation, local save, transport delay, conflict, layout, energy or crash.
   Never dismiss missing time as an expected asynchronous delay without evidence.
2. Reproduce with fictitious fixtures in Simulator first; use a focused physical
   scenario only when required. Preserve pending/quarantined data unchanged.
3. For voluntarily supplied/TestFlight crash reports, match binary and dSYM UUIDs
   before symbolication. Keep raw reports private and redact personal metadata
   before attaching a minimal stack/reproduction to an issue. Do not add runtime
   telemetry or content-bearing logs to make diagnosis easier.
4. Record severity, affected versions, exact invariant violated, reproduction,
   owner, fix and verification. Any loss/duplication/privacy/install blocker
   stops cohort expansion and release; inconclusive evidence stays open.
5. A fix requires targeted regressions plus the relevant clean CI, signed archive
   and physical retests. Do not relabel a failed build as passed after a code edit.

## Review and manual release

- [ ] WAT-26 and WAT-27 are complete for the same candidate; beta exit approved.
- [ ] Confirm the processed build, Watch assets, iOS copy, support/privacy URLs,
  review contact, accessibility declarations, price/availability and compliance.
- [ ] Select manual release; retain a reviewable submission summary. Obtain
  approval before Add for Review / Submit for Review and before sending replies.
- [ ] Resolve review questions with evidence. A capability/metadata mismatch may
  require a new build and a fresh signed-candidate gate.
- [ ] After approval, confirm Pending Developer Release and obtain explicit
  approval for that version/build before Release This Version.

Apple describes this separation in [manual release options](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/).
Approval is not public release, and an initiated release is not proof that the
version is downloadable in the intended storefront.

## Public-binary smoke and closure

- [ ] Verify actual App Store availability/version in the intended storefront.
- [ ] Install through the public App Store on the authorized pair; do not
  substitute an Xcode/TestFlight build. Verify the phone and embedded Watch
  version/build correspond to the processed candidate.
- [ ] Create fictitious projects and run Start → Pause → Resume → New/Switch →
  End. Check summary, notes/tags, exact history/report segments and paused time.
- [ ] Repeat detached offline work and delayed acknowledgement; verify eventual
  convergence once, default privacy, optional goal notification and system
  surfaces. Record any timing window as observed, not guaranteed delivery.
- [ ] Record outcome, storefront/time, install channel, device aliases, build
  evidence and residual issues. Update release docs and Linear only after proof.

## Containment and recovery — approval required

There is no application server or remote kill switch, and no assumed safe
downgrade of the local store. Preserve user records and pending changes.

- Before public release: hold the version, stop invitations and obtain approval
  to expire an affected beta build. Apple's [Expire Build](https://developer.apple.com/help/app-store-connect/test-a-beta-version/stop-testing-a-build/)
  prevents new TestFlight installations; do not claim this restores existing
  users' data or fixes already installed code.
- If a phased **update** was explicitly chosen, seek approval to pause it. Users
  can still manually download an update during phased release, so pausing is
  not a recall. See [phased release behavior](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases/).
- For public incidents, prepare a sanitized support notice and assess store
  availability changes with the owner. Do not make such changes autonomously.
  Build a forward fix that preserves current stores; rerun migration, archive
  and physical gates. Never instruct users to erase/reinstall to recover time
  without a verified, case-specific recovery path.
- Keep the previous source/candidate, incident timeline and support response.
  A prior binary is diagnostic context, not an automatically safe rollback.

WAT-28 remains open until beta, review, authorized release and public-binary
verification have actually happened. Preparation alone cannot close it.
