# Remaining Watch delivery work

Objective: complete WAT-05 and WAT-18–28 against their full Linear acceptance
criteria. Autonomous implementation/preparation does not close physical or
distribution gates. See `WAT-05-ACCEPTANCE-MATRIX.md` for evidence ownership and
`WAT-OWNER-DECISIONS.md` for the exact remaining approval boundaries and
recommended next-phase reply.

| Issue | Working state | Next evidence |
| --- | --- | --- |
| WAT-05 | Done; acceptance matrix written, reviewed and linked in Linear | Execution remains with downstream owners |
| WAT-18 | In Review; autonomous implementation/tests/builds verified | Actual WidgetKit placement/tint/Always On and physical multi-hour gate |
| WAT-19 | In Review; autonomous implementation/tests/builds and generated metadata verified | Actual system/Siri/Action button and real offline-convergence evidence |
| WAT-20 | In Review; autonomous implementation, tests, builds and visual checks verified | Physical long-goal notification delivery remains separate |
| WAT-21 | In Review; canonical projection, handoff, rendering, tests and builds verified | Physical mirrored placement/authentication and delayed delivery |
| WAT-22 | Done; full clean-checkout CI passed, including 322 executed tests and four joint build variants | Evidence in WAT-22-CI-AUTOMATION.md; WAT-23 has a separate later checkpoint |
| WAT-23 | In Review; autonomous accessibility/layout/privacy work, current-source 381-test clean CI and a five-screen physical Ultra fixture smoke are verified | Actual VoiceOver/system accessibility settings, Always On, haptic, dictation and WidgetKit placement checks; see WAT-23-ACCESSIBILITY-AUDIT.md |
| WAT-24 | In Progress; 31-case/55-record manifest and validator pass; prior aligned 0.1.0 (2) foreground diagnostic is verified; build 3 was installed nondestructively on iPhone and version-checked, but the locked phone/disconnected Watch prevented companion verification; zero matrix rows are promoted | Unlock iPhone and Watch, restore the Watch developer tunnel, verify both at 0.1.0 (3), then execute frozen debugger-detached rows; reinstall/unpair/upgrade/replacement retain separate gates; see WAT-24-PAIRED-DEVICE-MATRIX.md |
| WAT-25 | In Progress; source/binary guards, Simulator storage and CPU/memory regression reporting, physical file protection/backup-exclusion, four isolated physical storage workloads and a refreshed 1.56 MB physical storage inventory are verified; owner accepted the resource/privacy budget | Debugger-detached battery/reload/wakeup/memory, network and restart-before-unlock evidence; backup/restore remains separately gated; see WAT-25-RESOURCE-PRIVACY-AUDIT.md |
| WAT-26 | In Progress; App Store Connect confirms build 3 is unused; approved commit `8ead2308` passed all 13 CI stages/381 tests; its signed four-component 0.1.0 (3) archive passed signature/dSYM inspection | Unlock Mac; use authenticated Xcode Organizer to export the unchanged archive, generate the candidate privacy report, validate/upload and continue physical gates; see WAT-26-ARCHIVE-VALIDATION.md |
| WAT-27 | In Progress; build-3-bound five-screen 416×496 draft passed visual review; stale live iPhone-only public copy is corrected in local site commit `3a9b9cb` | Publish with a GitHub account authorized for the support-site repo; visually review live pages; recapture/review the installed distribution candidate and processed icon/screenshots; see WAT-27-STORE-MATERIALS-DRAFT.md |
| WAT-28 | In Progress; identifier-free build-3 beta package binds source/CI/archive/assets; no testers or external cohort were used | Export/upload/process exact build, complete authorized review/manual release and public-binary smoke; see WAT-28-BETA-RELEASE-RUNBOOK.md |

User decisions retained: immediate Start with no countdown; simulator-first
development; physical verification is a separate, focused gate; the
nondestructive physical session, resource/privacy budget, App Store submission
and manual public release are approved. Personal-data erase/unpair,
backup/restore, replacement/upgrade, and tester invitations remain separately
gated as recorded in `WAT-OWNER-DECISIONS.md`.

Resolved tooling interruption (September 3): Linear reads and authorized local
execution work again. Preserve the failed HTTP-404/restricted-context artifacts
as diagnostics, but do not use them as current blockers. The final 40mm widget
run passed 131 tests; Standard/Ultra result extraction and visual review passed;
the sanitized development archive passed a new authorized trust inspection.
A fresh continuation clean checkout passed all 13 stages and **381 tests** from
the latest synthetic snapshot `1e929e74935550b891cf99dbe2348e99e03b8c49`, evidence
`WellSpentCleanCheckout.5Aqsso/DerivedData/run.HOdM21`. Its production source
manifest matches the preceding current-source run. That preceding full run's
single PID-0 launch-harness failure is retained separately; its focused repair
and both restart cases passed before the green replacement. WAT-23's autonomous
work is ready for review; physical and distribution gates below are unchanged.

Linear reporting boundary: WAT-20 In Review and WAT-21 In Progress updates
succeeded. Detailed WAT-20/21 comments were rejected by approval review as
internal implementation/test-data exports; they were not posted or retried via
another route. Keep technical evidence in local handoff docs unless the user
approves summaries. An optional approval question was sent; no answer is needed
to continue development or ordinary issue status updates.

## Verified checkpoint — September 2, 2026

- WAT-05 is Done in Linear. WAT-18 and WAT-19 have issue-specific handoff docs
  with full implementation/evidence details and explicit unpassed device gates.
- WAT-19 final evidence: 91 Watch unit cases (66 XCTest + 25 Swift Testing),
  five focused UI cases, combined Release Simulator, unsigned Watch Release
  device build, source/binary privacy, formatting, generated metadata checks.
- Logs `/tmp/wat19-verified-{tests,release,device}.log`; compiled products and
  result bundles under `.derivedData/WAT19-*`.
- WAT-20 is implemented. See `WAT-20-GOAL-ALERTS.md`: protected local preferences,
  counted-segment scheduler, explicit opt-in/denied/failure handling, immediate
  cancellation, durable goal edits, recents, and foreground feedback. Final
  full unit/focused UI run passed (108 unit + ten focused 46mm UI cases) in
  `/tmp/wat20-final-tests.log`. Final adaptive unit/affected standard UI passed
  in `/tmp/wat20-final-adaptive-tests.log`; final 40mm goal/paging cases passed
  in `/tmp/wat20-small-header-final.log`, and final 40mm screenshots were checked.
  Combined Release Simulator and unsigned Watch Release device builds passed in
  `/tmp/wat20-{release,device}-header-final.log`; source/binary privacy, generated
  intent metadata and strict formatting pass. Earlier failed paging runs are
  retained as diagnostic evidence, not claimed as passes.
- The goal editor exposed a normal-size metric paging regression: adding a
  44-point button activated the nested ScrollView fallback. Compact spacing and
  a header sync label preserve the button target while restoring vertical page
  gestures; custom/edit/remove/recent and paging passed together after the fix.
- WAT-21 implemented: synchronous canonical desired-state publication, serialized
  generation-fenced ActivityKit writer, revision-bound persistence-first Stop
  handoffs with cross-process locking and app bridge, privacy-safe payloads,
  frozen conflict cards, background creation deferral, explicit mirrored iPhone
  copy, and current-state Watch deep links. See `WAT-21-LIVE-ACTIVITY.md`.
- WAT-21 verified: 161 iPhone unit tests, five focused iPhone UI tests, 109 Watch
  unit tests, 27 presentation renders, combined Release simulator and unsigned
  device-SDK builds. Final logs `/tmp/wat21-final-tests.log`,
  `/tmp/wat21-watch-receipt-verified.log`, `/tmp/wat21-watch-tests.log`,
  `/tmp/wat21-release-final.log`, `/tmp/wat21-device-release.log`.
  Source/binary privacy, negative fixtures, generated intent metadata, strict
  formatting and diff checks pass. No physical transport/authentication claim.
- Two iPhone 17 Pro unit-test attempts stalled before loading XCTest; live hosts
  were inspected and the attempts canceled. Standard-signed iPhone 17 Pro Max
  runs passed repeatedly. Preserve diagnostics and investigate reproducibility
  in WAT-22; do not erase/unpair devices to bypass it. The unsigned App Group
  failure and invalid causal test fixture are retained in the issue handoff.
- WAT-22 is complete: the 13-stage clean-checkout run passed in about 11 minutes
  with 19 shared-contract, 109 Watch unit, 161 phone unit, 16 Watch UI and 17
  phone UI tests; no failed/skipped/expected failures. Four clean joint build
  variants, product metadata/privacy and Release fixture isolation all passed.
  See WAT-22-CI-AUTOMATION.md for the exact source checkpoint and retained paths.
- WAT-23: private-sheet navigation crash corrected; note/tag drafts survive
  redaction; private names removed from native List accessibility; generic
  redacted overlays visually checked. Three display classes passed nine focused
  privacy/summary regressions each. The small display also passed 25 expanded
  audits/actions, but screenshot review exposed squeezed names/truncated metrics,
  so adaptive full-width layouts were implemented and visually checked. The
  September 3 checkpoint passed 111 Watch unit cases and 11 focused privacy,
  sheet and ordinary-paging cases on each of three Watch sizes. Joint Release
  Simulator and unsigned device-SDK builds and privacy/isolation scans passed.
  See WAT-23-ACCESSIBILITY-AUDIT.md
  for retained failures, narrowly documented native exceptions and remaining
  complete editor/error/widget coverage and physical gates.
- WAT-23 localization follow-up: shared English/Siri catalogs, real expanded-text
  tests, full-width picker names, readable editor headings and an operable custom
  goal wheel. Final small run passed 116 unit plus 15 UI cases; standard/Ultra
  each passed four focused final goal/privacy cases. Both Release build variants
  and source/binary/privacy/fixture guards passed. Full new clean CI is pending.
- WAT-24: physical resilience matrix prepared; a non-matrix foreground paired
  diagnostic passed through Watch Start/Pause/Resume/End and phone history
  convergence, but no frozen physical matrix row is claimed.
- WAT-23 goal-error follow-up: settings, permission, scheduling and goal-save
  errors now have ordinary/maximum-text coverage across three display classes.
  Screenshot review caught native List clipping/overlap; the goal form now uses
  a scrolling stack while keeping the custom wheel separate. Per-case full-run
  plus retest evidence covers 45 scenario/display pairs and 118 Watch units.
  Corrected-form Release builds and privacy/isolation checks passed. The later
  full-CI checkpoint below passed; widget/control-error and physical gates remain.
- WAT-25: initial source/unsigned-binary audit passed with added fitness and
  extended-runtime rejection guards. Energy/network/backup evidence is pending.
- WAT-27/28 preparation does not close distribution gates.
- WAT-25 resource follow-up: four automated persistent-store scenarios now
  verify offline capacity, repeated acknowledgement compaction, quarantine
  retention and 48-hour timestamp projections without writes. Reproducible JSON
  reports retain actual file-size/CPU observations with explicit Simulator
  limits; arithmetic and ten invalid-report guards pass. Full Watch suite plus
  the corrected Siri & Controls navigation test passed: 123 cases, no skips.
- WAT-23 corrected-form clean CI passed build/unit/product gates but finished
  38/39 Watch UI cases. Its lazy-list pre-scroll assertion is corrected and
  retested; the failed bundle remains retained, separate from the passed retry.
- WAT-26 preparation: unsigned joint-device inspection and 21 rejection guards
  passed. The report distinguishes unchecked signatures from release approval;
  no genuine signed archive has been validated. Version/build remain unchanged.
- WAT-27/28: five native 422×514 fictitious-data draft captures and the existing
  opaque 1024px icon were inspected. Store/support/privacy/accessibility/review
  copy and beta/crash-triage/manual-release/containment procedures are drafted.
  Nothing was published, submitted, uploaded or sent to testers.
- Final clean CI: all 13 stages passed, **358 tests** with no failures/skips
  (19 golden, 122 Watch units, 161 phone units, 39 Watch UI, 17 phone UI).
  Exact snapshot and paths are in WAT-23-ACCESSIBILITY-AUDIT.md. Later additional
  quarantine-byte assertions, draft captures and release-tool guards passed
  separately. WAT-23–28 remain In Progress against their complete acceptance
  criteria; no physical/signing/distribution gate was promoted from preparation.
- Help/control follow-up: 42 ordinary/largest/expanded scenario-display pairs
  passed across 40mm, 46mm and Ultra, plus 123 Watch units and existing regression
  checks. Help title clipping and cache text/scroll-indicator overlap were fixed.
  Native system alert font size is not controlled by the SwiftUI test fixture;
  physical largest-font validation remains separate. An exact native-heading
  hit-region exception has negative guards and preserves all reports/actions.
- WAT-26 package inspection and its rejection guards now run inside CI. A
  pre-margin clean run passed the first eleven stages, then was deliberately
  stopped after screenshot review found the final cache-layout issue. It is not
  a full pass; a fresh final-source CI run remains required. Earlier 358-test
  evidence is retained separately, and all WAT-23–28 statuses remain In Progress.
- The replacement margin-fix clean CI passed all 13 stages and 374 tests with
  no failures/skips. Exact snapshot `058461cdb90b1d39be3561d422dd09378cf54d40`,
  retained workspace `WellSpentCleanCheckout.BB9IUG`, evidence
  `DerivedData/run.h0nZNi`; see WAT-23 for verified counts and production digest.
  Widget combinations and physical/signing/distribution requirements remain.
