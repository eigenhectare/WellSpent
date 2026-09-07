# WellSpent 0.2.0 update preparation — September 6, 2026

**Current update status — September 6, 2026:** The owner confirms WellSpent **0.2.0 (9) has been added for review**. Apple’s exact queue state has not been independently rechecked; App Review approval and public release are not yet confirmed. See the dated owner update in WAT-33-UPDATE-RELEASE.md. Earlier validation gaps and historical observations remain recorded separately.

The owner requested all preparation that can be completed without the physical iPhone or Watch. Physical queries, installation and tests are deferred. App Review submission and public release remain behind the outstanding factual acceptance gates. WAT-OWNER-DECISIONS.md section 4 retains authority for archive/export, upload validation and submission-workflow upload; tester invitations and external beta enrollment have not been authorized.

## Current candidate

- Version/build: **0.2.0 (9)**.
- Exact source: **31538cee04c3bf1ddddc3be152ae5fa0da56cef1**.
- Exact tree: **a954ab56b998f62c61c536f042207c8d89b94d0f**.
- Frozen checkout: `/Users/dev/Documents/WellSpent-abstract-release-9-r2`.
- Candidate artifacts: `AppStore/Abstract-0.2.0-9/attempt-2/` (ignored local storage).
- Source receipt and production manifest: `attempt-2/source-receipt/`.
- Approved abstract light/dark artwork remains that of ICON-04-ABSTRACT. Product changes afterward are disclosure strings and build allocation only: optional Watch notifications, iPhone-scoped backup wording, goal-alert privacy preferences and iPhone-only erasure results. Behavior, schemas, bundle identities, entitlements and signing configuration are unchanged.

## Candidate history

Builds 7 and 8 were locally archived but never exported/uploaded. Their frozen sources and raw evidence remain under `AppStore/Abstract-0.2.0-7/` and `AppStore/Abstract-0.2.0-8/`; their CI runs were deliberately interrupted with exit 129 when the disclosure audit found additional stale copy. Neither is acceptance evidence for this update.

The first build 9 source, ad367038b1a746933eb114b6fa724fcd40c6c9e3, archived successfully but failed the source lint gate on one overlong assignment. A formatting-only follow-up produced 31538ce in a new frozen checkout. The initial archive, failed CI and source receipt remain at their original paths; attempt-2 artifacts alone belong to the current candidate. No uploaded build number, published release tag, or historical evidence was reused or rewritten.

## Automated validation

The frozen candidate passed all **13 CI stages** and **386 tests**: 19 golden, 124 Watch unit, 163 iPhone unit, 62 Watch UI and 18 iPhone UI. There were zero test failures, skips or expected failures. Aggregate stage time was 2,038 seconds. Debug and Release builds passed for Simulator and generic device SDK destinations; generic-device compilation did not query or operate physical hardware.

The retained run is `.derivedData/AbstractRelease9R2CI/run.oq8W3w/` under the main repository, with its driver at `.derivedData/AbstractRelease9R2CI/driver.log`. The independent verifier re-extracted all five result bundles and checked minimum counts and critical coverage. Final receipt: `AgentControl/evidence/REL-09-PREP/CI-REL-09-PREP-20260906-202624.json` (ER-2).

The Watch UI result records ten non-failing SwiftUI publishing-during-view-update warnings. The same warning/test pairs occur in earlier passed DesignCI and IconCI runs. They occur during deliberately injected failure/cancel/retry paths whose recovery assertions pass. Alert dismissal synchronously clearing published error state is a plausible source; the available diagnostics do not prove the exact cause. Keep this as a pre-existing follow-up, and include alert dismissal/retry in the physical pass. No functional regression or failed assertion was demonstrated; the run is not described as warning-free.

## App Store observations

On September 6, App Store Connect displayed live version **0.1.0 Ready for Distribution with build 2 selected**. Build 4 is uploaded and Ready to Submit in TestFlight. This direct observation differs from the earlier owner-confirmed build-4 submission/approval record; preserve both records and use the actually distributed build 2 as the supported upgrade starting point. Do not relabel historical build-4 package hashes.

Created the **0.2.0 Prepare for Submission** draft and saved new description, promotional text, What's New and reviewer instructions. Retained manual release, current rating, name **WellSpent: Time Tracker**, subtitle, categories, US storefront configuration and no-sign-in behavior. Old build-2 physical-video claims were removed from the new version notes; no claim of build-9 physical validation was added. The new draft did not inherit the old video attachment.

App Privacy still shows **Data Not Collected** and the same privacy URL. App Information shows Productivity / Business, 4+, standard EULA and no third-party content. General DSA/medical setup controls are not treated as new applicable requirements for this US-only productivity release.

## Prior public-build provenance

A read-only audit found `.derivedData/ReleaseValidation/WellSpent-0.1.0-2.xcarchive`, created September 1 at 00:34:06 UTC. Retained Organizer metadata reports successful App Store upload of build 2 at 11:35:09 UTC, with zero recorded errors/warnings. It contains only the iPhone app and widget, both 0.1.0 (2), with no Watch companion.

Commit `b7a31da5da905777942d68c1cb6a95111d22230b` / tree `1d387a8276f7f6d6d6c932efdd9a9c62a964e3d7` is corroborated candidate source: its 61 production/configuration files match the retained ReleaseSource snapshot. Their relative manifest SHA-256 calculated September 6 is `069341baca46290f72162e0e1a31da01eff8f918b855e1614b29555693a85145`. No contemporaneous archive-to-commit receipt or build-2 IPA/export was found. Therefore exact original binary-source attribution and export hashes remain unavailable; the corroborated commit is not substituted for proof.

The current retained archive's 27-file relative manifest hashes to `16008ca4de9c02fe09468525ddc5eacf378ef231f0e7b520ccfa0cf19797d3d5`. That measurement identifies today's retained files, not an Apple-served binary or historical export. Future upgrade coverage must start from the actual public build 2 and treat first Watch installation separately.

## Public-copy discrepancy

Both support and privacy URLs returned HTTP 200. As the owner stated, they remain unchanged since the iPhone-only release. They still describe records remaining on one iPhone and no paired synchronization. That copy needs a Watch-aware publication before the changed product is released. Proposed exact replacement sections are staged at `AppStore/Abstract-0.2.0-9/attempt-2/public-copy-draft.md`. No public page was changed. Set the policy effective date to the actual publication date.

Public observations and SHA-256 digests are retained in `attempt-2/privacy-public-observation.json` and `attempt-2/support-public-observation.json`.

## Remaining device session

No physical device was queried, installed, erased or tested during this preparation.

When the owner returns, batch the outstanding candidate-bound checks:

1. Confirm the intended build and supported paired phone/Watch; use a wired phone and unlocked/worn Watch where required. Record actual app versions and source/package provenance.
2. Inspect light, dark and Automatic iPhone icon appearances and the Watch circular icon; compare the installed screens with the candidate-source store captures.
3. Check idle complication → Projects → deliberate start; running and paused reentry; paused reentry must not resume. Exercise real complications, Smart Stack and widgets, not only in-app render fixtures.
4. Exercise Start/Pause/Resume/Switch/End, persistence/restart, offline acknowledgement/reconciliation, default/private labels and opt-in labels, goals and denied/allowed notifications, VoiceOver/Dynamic Type, Always On and haptics.
5. Complete the recorded runtime privacy, battery/storage and transport matrix. Keep physical, simulator and signed-package evidence separate.
6. Plan the actual public-build-2 upgrade and any destructive erase/reinstall/unpair cases under their separate explicit data-loss authority. Do not infer consent to those operations from general testing approval.

External beta invitations remain separately unauthorized. App Review/public release wait for applicable physical gates, accurate public copy and the exact chosen build.

## Additional external prerequisites observed

Xcode native UI is blocked because the Mac is locked. Command-line archive and automatic App Store distribution export succeeded. A subsequent command-line upload failed with exit 70 because the Xcode account credentials were unavailable; no upload success or server processing was observed. Apple's documented Generate Privacy Report command is in Organizer; the aggregate Xcode PDF remains pending until the Mac is unlocked. Independent source/compiled manifest reconciliation is recorded separately and must not be called that PDF.

The review-contact phone/email fields were not reliably readable or editable through the browser in either the existing version or new draft. Account-holder name and email are available in the existing account profile, but a contact number was not exposed in membership details. An unsuccessful contact edit was discarded by reloading the saved draft. Verify both required fields when the owner returns; no private contact details are committed here.

The Developer account displayed a new program-license agreement with an acceptance deadline of **October 1, 2026**; the prior agreement is accepted. No agreement was accepted on the owner's behalf. This is an owner legal follow-up, not asserted to be a current upload blocker while export works.

## Store capture provenance

Capture targets are iPhone 17 Pro Max at native **1320 × 2868** and Watch Series 11 46 mm at native **416 × 496**. Apple also accepts Watch 410 × 502; the older WAT-27 statement excluding that Ultra size is stale. Use one consistent Watch size across localizations. Current reference: https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications/ (checked September 6, 2026).

The existing screenshot fixtures exercise the current app's native views with fictitious local data. They are Debug Simulator captures from the frozen candidate source, not the signed distribution executable or an end-to-end paired transport sequence. Preserve the Watch exporter's draft classification. Final installed-candidate comparison and any signed-device capture needed by WAT-27 remain part of the deferred physical acceptance; no simulator artifact closes those requirements.

## Verified package and upload boundary

Independent archive and distribution-export checks passed for binary source 31538ce. The distribution gate initially expected one phone icon; it was corrected in the separate, independently verified tooling commit **aafcf4adaa698dd3c2b939e3e3f1c129e70355d8**. The new gate verifies exactly the default/dark phone icons and default Watch icon, all rendition metadata, and 76 rejection cases. It adds per-appearance records while retaining the default digest. The binary was not rebuilt or relabeled after this tool-only fix.

- Archive file manifest SHA-256: `78e6f569821acecdeccac15a8a708afa2195869ec6845a28e382b95bfd8e76be`.
- App Store distribution IPA SHA-256: `ce086d92fb86e9d3ef5be065b0f5789aa9cbf6a148c9e60949feef48580e128e`.
- Exported product manifest SHA-256: `9ae974dff57e88a48d7e032938c18241e3774a811cb955c6ac51ee33eec38098`.
- Four components: iPhone app/widget and Watch app/widget, all version 0.2.0 build 9, App Store distribution signatures/profiles, symbols, expected architecture/entitlements and source-matching privacy manifests.
- Detailed receipt files are under `AgentControl/evidence/REL-09-PREP/`; the failed old-gate attempt remains alongside the later passed gate.

The upload attempt ended before confirmed upload with `Failed to Use Accounts` / missing Xcode username credentials. The exact local IPA remains available in `attempt-2/distribution-export/WellSpent.ipa`. Upload validation, processing, build attachment and processed-icon review remain pending.

## Screenshot staging boundary

Six light iPhone captures and one dark timer capture passed. Six unmodified files selected for the store are in `attempt-2/screenshots/phone-store/`, ordered active timer, projects, completion notes/tags, reports, exact records and dark timer. The Settings capture remains a QA artifact rather than a selected marketing image. Independent visual review found no blocking defect.

The 0.2.0 draft's inherited six iPhone screenshots were cleared; the live 0.1.0 version was not changed. Uploading the new files was denied by the Chrome extension's local-file permission. The draft currently has **zero iPhone screenshots** and needs the prepared six uploaded after enabling **Allow access to file URLs** in the ChatGPT Chrome extension, or manual file selection. No screenshot-upload pass is claimed.


The five Watch images are now in `attempt-2/screenshots/watch-store/`, ordered Projects, Time Goal, active metrics, Controls and saved summary. The single capture test passed and yielded five unmodified opaque 416 × 496 RGB PNGs. Its `manifest.json` binds the clean source receipts, exact commit/tree, native file hashes and source-only limitations. The original `watch-assets/manifest.json` keeps `draftOnly: true` and `releaseCandidate: false`. Independent visual/source review passed in `AgentControl/evidence/REL-09-PREP/SRC-REL-09-PREP-MATERIALS-20260906-202422.json`, covering 43 artifact digests, both screenshot sets, metadata, public-copy draft and compiled-manifest reconciliation. No Watch screenshot upload is claimed.

The phone and Watch contact sheets at `screenshots/phone-light-review.png` and `screenshots/watch-review.png` are QA conveniences only; only individual unmodified files are staged for eventual upload.

## Candidate-specific test handoff

`attempt-2/beta/` contains local `BetaDescription.txt`, `WhatToTest.txt` and `README.txt` drafts bound to source 31538ce and the verified distribution IPA. They include the idle complication → Projects workflow, paused reentry without automatic resume, exact time accounting, goals, private system surfaces and offline acknowledgement. They preserve the build-2 provenance gap and the separate destructive-data authority boundary. Independent beta-draft review is recorded in `AgentControl/evidence/REL-09-PREP/SRC-REL-09-PREP-BETA-20260906-202816.json`. No beta group, cohort, enrollment or invitation was created.

The return session must use the detailed existing acceptance matrix, not treat the short checklist as a replacement:

- WAT-05 `SURF-02/03`: Siri, Shortcuts, controls, assigned Action button, Lock Screen/Dynamic Island, and stale or duplicate invocation safety.
- WAT-05 `SYNC-05`, `ALERT-01/02`: approved clock/time-zone cases, actual permission dialogs and obsolete-alert cancellation.
- WAT-23 six-step physical audit: VoiceOver/focus/Crown, maximum text/contrast, canceled dictation, draft persistence across wrist-down and real system redaction.
- WAT-24 physical evidence gate: 31 case IDs and 55 minimum records, including repeated detached trials; LONG-01 at least three hours and LONG-02/03 at least two hours. Preserve unavailable hardware coverage and obtain separate destructive-data authority.
- WAT-25 accepted budget and measurement protocol: battery, CPU/wakeups, memory/storage/reloads, attributable runtime network behavior, protection before first unlock and retention observations.
- WAT-26/28 installation and upgrade: actual public iPhone build 2, separate first Watch installation, automatic/manual companion installation and the appropriate signed distribution channel. WAT-27 still requires final installed-candidate asset comparison/capture.

App Store-installed public-binary smoke remains a separate post-release step.

## Handoff state

All feasible local product, build, capture and preparation work is complete. REL-09-PREP remains blocked at external staging; it is not marked done or submission-ready. Resume when the Mac is unlocked, Xcode account access works, and local-file uploads are enabled or the owner selects the files manually. Generate the privacy PDF, confirm reviewer contact, publish the reviewed Watch-aware public copy under explicit authority, finish physical acceptance and then attach/submit the exact processed build. The task retains the existing factual and authority boundaries, and the shared resource leases are released at handoff.

Detailed independent source, full-CI, signed-package and store-material receipts are under `AgentControl/evidence/REL-09-PREP/`. Tooling evidence is under `AgentControl/evidence/REL-10-ICON-GATE/`. Failed and superseded attempts remain alongside the later results. The exact binary source remains 31538ce even after later evidence and release-ledger commits. `attempt-2/RELEASE-PACKAGE.json` indexes the retained receipts, source, package and staged materials; `attempt-2/RETURN-CHECKLIST.txt` gives the return-session sequence.

## September 6 resumed session, after owner return

The owner restored website sign-in and connected the iPhone. The separate `REL-11-DEVICE` session installed and normally launched Debug development build **0.2.0 (9)** on both the physical phone and Watch. Independent preflight passed at 23:09:49 UTC; source/product provenance, default device-rendered icons and all observation limits are recorded in **WAT-34-CANDIDATE-DEVICE-SESSION.md**. No production-reset tests or destructive device actions ran. Actual counterpart exchange, complication/Smart Stack behavior, Home Screen appearance switching and the broader physical matrix remain unverified pending owner observations. This does not alter the earlier statement that REL-09's nonphysical preparation did not operate devices.

App Store Connect sign-in now works. A fresh read confirmed the saved 0.2.0 draft text, manual release, no attached build and zero images in the inspected 6.5-inch and 6.9-inch iPhone slots. The review-contact phone/email controls remain unconfirmed; the accessibility surface exposes no values, which is not treated as proof that the saved data is empty. No metadata or App Store state was changed in this resumed attempt.

The current Apps page explicitly says the Account Holder must review and accept the updated Apple Developer Program License Agreement to update apps. This newer observation supersedes the earlier assumption that the October 1 deadline might permit updates beforehand. The owner was asked to review/accept in the Developer account; no acceptance or agreement status change is claimed.

A separate operator copy of the retained build-9 archive was prepared for Organizer. Independent reconciliation confirmed all 56 files still match the prior canonical archive manifest SHA-256 `78e6f569821acecdeccac15a8a708afa2195869ec6845a28e382b95bfd8e76be`, and the original distribution IPA remains `ce086d92fb86e9d3ef5be065b0f5789aa9cbf6a148c9e60949feef48580e128e`. The copy's differently formatted manifest omits `./` path prefixes; its different text digest does not represent changed archive bytes.

The Mac subsequently locked. The attempted native Chrome screenshot picker could not be operated; Xcode Organizer privacy-report/validation work also remains unavailable. No screenshot upload, new upload attempt, processing, build attachment, App Review submission or public release is claimed. The prepared archive copy and independent reconciliation are under `AppStore/Abstract-0.2.0-9/resumed-staging/`; the original archive/export and all earlier observations are preserved.

Resume external staging after the owner unlocks the Mac and resolves Apple's agreement request. Verify Xcode account access separately from browser login. Continue the native screenshot selection, aggregate privacy PDF, validation/upload, contact confirmation and processed build/asset checks. Public-copy publication and remaining physical acceptance retain their existing gates. REL-09-PREP remains blocked, and REL-11-DEVICE is separately waiting for owner-operated physical observations.

## September 6 successful validation, upload and draft attachment

After the owner reported the Mac unlocked and the Apple agreement accepted, the update-agreement banner disappeared from the freshly read Apps page. The release steward used the native file picker to upload and order **six iPhone and five Watch screenshots**, without changing extension permissions. The saved orders are active timer, projects, notes/tags, day report, exact records and dark timer for iPhone; Projects, Time Goal, active metrics, Controls and summary for Watch. The 6.9-inch phone slot contains six images, and the Watch Series 11 slot contains five. Their Debug Simulator provenance remains unchanged.

Xcode Organizer validated **0.2.0 (9)** successfully, then uploaded it successfully around 23:50–23:51 UTC. App Store Connect showed upload **Complete**, build **Ready to Submit** and binary **Validated**. Build record `12826a50-4dcd-4ef4-9b43-cfa88f8d0b22` was selected in the 0.2.0 draft and saved. A subsequent page read retained build 9, a disabled Save button and manual release. The Apple-processed default phone and circular Watch hourglass icons were visually inspected and correct. No processed dark-appearance preview was shown. No Add for Review action, tester invitation or public release occurred.

The actual Organizer-upload IPA is retained in both `resumed-staging/organizer-upload-package/` and `resumed-staging/organizer-upload-result/`: **8,436,591 bytes**, SHA-256 **`c3ad0920723278a6871058a5687367bd527a2c66c4a9b2f4336e710c266ad38a`**. This newly re-signed package is distinct from the earlier local export `ce086d92…`; that historical export is not relabeled as the uploaded binary. Authentic Organizer result files preserve destination `upload`, automatic signing, symbols enabled and version/build management disabled. All four components retained 0.2.0 (9).

Independent supplemental inspection found all four strict signatures, distribution profiles and entitlements valid; all 207 Mach-O sections, six UUIDs, 29 non-signing resources, compiled icons and privacy declarations matched the retained candidate material. The original 56-file archive is unchanged. The six symbol caches have different bytes after generation; printable content matches after normalizing the embedded dSYM path, which is not claimed as complete binary/semantic equivalence. The canonical export gate rejects authentic `destination=upload` metadata because it requires `export`; that failure is preserved. The supplemental inspection is not relabeled as a passed canonical export gate. Details and digests are indexed in `resumed-staging/external-staging-uploaded-observation-20260907.json` and `resumed-staging/independent-organizer-package-20260906-235039/`.

Two native Organizer privacy-report exports each produced an 807-byte blank, zero-sized-page PDF, including a retry after successful validation. Independent PDF reviews failed on absent report content; receipts `SRC-REL-09-PREP-PDF-FAIL-20260906-234522.json` and `SRC-REL-09-PREP-PDF2-FAIL-20260906-234851.json` preserve both results. The four truthful manifests declare no collected data or tracking, while required-reason API declarations are separately checked. Apple's documentation describes the report's collected-data/tracking purpose, but does not establish that this zero-sized PDF is expected. Retain a report-content limitation; no synthetic report, privacy-declaration change or product-privacy defect is inferred. Existing source/compiled-manifest audits and Apple validation remain separate passed observations.

A read-only DOM check established that review-contact phone/email were empty in both versions. The owner subsequently supplied both explicitly for saving; personal values are not recorded in Git. Saving them remains pending while the Mac is locked. A fresh independent live-draft audit was also blocked by that lock, recorded in `EXT-REL-09-PREP-VERIFY-BLOCKED-20260906-235942.json`. The successful release-steward observations above remain valid observations of their earlier session; they do not become independent verification merely because local package checks pass.

The owner also reported specific physical complication, Smart Stack and iPhone icon passes. Their exact scope and Debug installation channel are recorded separately in WAT-34. Neither those results nor Apple's processing closes the remaining physical matrix, actual distribution/upgrade checks or Watch-aware public-copy publication. Next steps are contact save, independent saved-draft verification, applicable physical acceptance and public-copy publication under separate authority; the blank-PDF and upload-mode canonical-gate limitations above remain recorded and are not closed by this list. App Review has not been requested.

## Owner-confirmed review progress — September 6 local / September 7 UTC

The owner reported: “It's been added for review” and explicitly requested a project-status update. This records **0.2.0 (9) added for review** based on the current candidate and owner's statement. It supersedes the earlier current-status claim that Add for Review had not occurred; those earlier session observations remain true at their recorded times. The operator did not perform another submission action in this follow-up.

The exact App Store Connect queue label and review submission identifier have not been independently read since this report. Do not translate “added for review” into an observed Waiting for Review, In Review or approved state. No Apple approval, public availability, manual-release completion or public-binary smoke is established by this message. The supplied review-contact values were not written or verified by the agent after the prior locked-Mac interruption. The user's progress report does not separately attest to public-copy publication, remaining physical acceptance or disposition of the retained PDF/upload-mode gate limitations.

At the owner's request, dated updates were posted to both Linear projects: [Billable Hours iPhone App](https://linear.app/idkmanicomehere/project/billable-hours-iphone-app-502d12cbf4a3/activity#project-update-8fe571ec) and [WellSpent for Apple Watch](https://linear.app/idkmanicomehere/project/wellspent-for-apple-watch-501d6fb11400/activity#project-update-9a7b2eb9). The Watch project's stale Backlog status was moved to In Progress; the phone project remains In Progress. Composite release/physical issues were not marked done. The updates contain a concise product/review checkpoint and no private contact, device identifiers or internal raw diagnostics.

This is the user's directly authorized small, bounded status reconciliation under the AGENTS.md starting-task exception. In addition to REL-09's release ledgers, it refreshes only the summary checkpoint in PROJECT_PLAN.md and WAT-EXECUTION-STATUS.md; it does not expand or rewrite the frozen implementation contract. Binary source remains `31538cee04c3bf1ddddc3be152ae5fa0da56cef1`, tree `a954ab56b998f62c61c536f042207c8d89b94d0f`. All earlier receipt files remain append-only. No build, signing, product-code, version or tag change accompanies this status update.
