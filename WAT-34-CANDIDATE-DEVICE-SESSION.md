# WAT-34 — Build 9 physical session

September 6, 2026. Task: `REL-11-DEVICE`. This session resumes after the owner reported a connected, ready iPhone and restored website sign-in. It records installation and feasible observations; the full physical acceptance matrix remains open.

## Exact source and installation channel

WellSpent **0.2.0 (9)** was built from commit `31538cee04c3bf1ddddc3be152ae5fa0da56cef1`, tree `a954ab56b998f62c61c536f042207c8d89b94d0f`. The 143-file production-source manifest SHA-256 is `5ed43d1afa5cf4e7b94ac94f2e81b76a481df1a645c84faac1287463532ba429`.

The isolated `WellSpent-build-9-devices` checkout was used for Xcode. The frozen release checkout and retained archive/IPA were not modified. Xcode temporarily normalized three shared schemes and four stale localization extraction annotations. Patches were retained, localized keys and payloads were independently confirmed identical, and the generated changes were restored after closing the project. Source receipts before run, after build and after deployment identify the clean exact candidate.

This installation uses **Debug / Apple Development**, not the Release archive, distribution IPA or TestFlight. All four components are version 0.2.0 build 9 and pass strict signature inspection. The independent complete 47-file product manifest, including three debug implementation libraries, has SHA-256 `59d50509e41d8cfe3febb4f771658bb3ae86a915dfc861f664954d52a80d5b64`. Compiled default/dark phone and default Watch icon rendition digests match the approved Release export. Matching source and version do not establish distribution-binary equivalence.

## Observed deployment

- The paired iPhone 17 Pro Max runs iOS 26.6.1; the Apple Watch Ultra 2 runs watchOS 26.6. Developer Mode is enabled. Read-only lock-state checks reported both unlocked before deployment. Device identifiers and personal names remain in ignored/private diagnostics only.
- Initial canonical preflight reported both product apps absent. Separate exact-bundle queries including default/distribution apps also returned zero results. Thus this session does not establish an upgrade from an existing installed public build.
- Xcode built the production Watch scheme. A signed Debug phone build, including the embedded Watch app and both widget extensions, then succeeded using the same Xcode DerivedData location.
- Xcode Run Without Building installed and launched the Watch app. The intermediate preflight correctly failed because the phone app was still absent. The phone production scheme was then installed and launched through Xcode Run Without Building. No independent bundle-install command was used.
- The phone's first startup reported counterpart registration not ready. The Watch app was subsequently relaunched after the phone companion installation. Both apps then launched successfully with normal CoreDevice foreground launches, without test arguments, fixture flags or an attached debugger. This sequence alone does not establish successful paired message exchange.
- No app was uninstalled, erased, unpaired or restored. No production-reset XCTest suite ran. No personal project/session data was inspected or changed by the operator.

The installation sequence is Xcode-owned deployment through both production schemes. It is not presented as proof of automatic companion installation from an App Store/TestFlight download.

An independent canonical preflight passed at **23:09:49 UTC**, reporting both production bundles installed as **0.2.0 (9)**, all five readiness checks true and no reason codes. Receipt: `AgentControl/evidence/REL-11-DEVICE/PHY-REL-11-DEVICE-20260906-231132.json`. The verifier also reconfirmed the clean source and unchanged local development-product manifest. Device version queries do not hash the installed binaries or prove data preservation or transport.

## Icon observations and interaction limit

CoreDevice retrieved each installed app's native default icon with placeholders disabled. The approved abstract hourglass fits the iPhone rounded-square and Watch circular masks without clipping. Retained 1024 × 1024 PNGs and their hashes are indexed by `device-session/installed-icon-observation.json`.

These are device-rendered default icon results, not Home Screen screenshots. Light, dark and Automatic Home Screen appearance changes remain unobserved. iPhone Mirroring reports **“iCloud Isn't Syncing”** on this Mac, so remote visual interaction is unavailable. No iCloud settings or credentials were changed. The owner can complete the visual walkthrough directly on the devices.

## Next hands-on observations

Before manipulating timers, confirm no real work is running and use clearly fictitious projects. Record actual observations rather than assuming a successful launch proves behavior.

1. Open WellSpent on the phone and Watch. Create a new uniquely named test project on the phone and confirm it arrives on the Watch. A new exchange distinguishes current transport from cached state.
2. Add WellSpent to an actual compatible watch-face complication. With no timer, tapping it should open Projects; navigation must not start a timer. Select the test project and deliberately start.
3. Return to the watch face and tap the running complication: the existing timer should reopen. Pause, record elapsed time, return to the face, wait briefly, and tap again: the same paused timer should reopen with elapsed time unchanged and no automatic resume.
4. Repeat idle and paused entry through the actual Smart Stack widget. Resume, switch to another fictitious project and end; verify one corresponding result on the phone, paused time excluded, and a single shared switch boundary.
5. Check the phone Home Screen icon in light, dark and Automatic appearance, and inspect the Watch app icon on its app screen.

Owner results for these steps have not yet been received. Actual complication/Smart Stack rendering, registration, timer correctness and appearance switching are **not run / unverified**, not passed.

The broader gates remain those in WAT-33, WAT-05, WAT-23, WAT-24, WAT-25 and WAT-26/28: accessibility, privacy/redaction, goal notifications, lifecycle and offline reconciliation, repeated and long-duration trials, resource measurements and distribution/upgrade coverage. Destructive and actual public-build-2 upgrade scenarios retain their separate authority requirements. Public-binary smoke remains post-release.

## Authority and evidence

The current readiness message and WAT-OWNER-DECISIONS.md §3 / WAT-24 authorize nondestructive physical testing and in-place Xcode deployment. They do not authorize erasing or replacing devices or personal data. Website sign-in does not establish Xcode account access or legal agreement acceptance.

Artifacts are retained under ignored `AppStore/Abstract-0.2.0-9/device-session/`: initial and intermediate preflights, exact installed-app queries, source receipts, development product build/result bundle, independent product manifest, normalization patches, launch results and installed icon renders. Raw device-bearing logs are not committed. Append-only sanitized independent receipts belong under `AgentControl/evidence/REL-11-DEVICE/`.

App Store staging remains a separate task. The signed-in site currently requests Account Holder acceptance of an updated Apple Developer Program agreement before updates; the owner has been asked to review it. No agreement was accepted by the agent. Physical installation does not close App Store processing, accurate public-copy publication, review or release gates.

## Subsequent owner reports — September 6 local / recorded September 7 UTC

The owner subsequently completed the following on the physical pair using the previously installed **0.2.0 (9), Debug / Apple Development** apps and the deliberately fictitious test project. These reports supersede only the corresponding earlier unobserved items; the earlier observations and receipts remain unchanged.

| Check | Owner-reported result |
| --- | --- |
| New fictitious iPhone project appears on Watch | Pass: project appears on Watch. This is a report of fresh paired exchange, beyond the earlier cached-state/launch evidence. |
| Actual idle watch-face complication | Pass: opens Projects; no timer starts. |
| Actual paused complication after a roughly 20-second wait | Pass: the same timer reopens, remains paused and shows unchanged elapsed time. |
| Actual Smart Stack while paused | Pass: reopens the paused timer without resuming. |
| Actual Smart Stack after ending that test timer | Pass: opens Projects without starting another timer. |
| iPhone Home Screen Light, Dark and Automatic appearances | Pass: the abstract hourglass looks correct in all three settings and switches appropriately. |

These are explicit owner answers to the described checks, not independently witnessed interactions or instrumented measurements. No actual numerical elapsed time, pause duration or start/end timestamps were supplied. Source and installed-version provenance are inherited from the preceding documented development installation, not from a fresh cryptographic installed-binary check. They do not describe the newly uploaded App Store distribution IPA.

The pending owner question asks whether the ended Watch timer appears exactly once in iPhone History/Reports, with the paused interval excluded. No answer has yet been received. Running complication reentry, explicit Resume/Switch with a shared exact boundary and the icon on the actual Watch app screen also remain unreported. The default Watch icon was independently viewed only through the prior CoreDevice render. No broad exact-accounting, duplicate-reconciliation or Watch appearance claim is inferred from these narrower passes.

The sanitized answers and limitations are preserved in ignored `device-session/owner-reports-20260907.json`; the actual project label and private device/contact details are omitted. No additional device query, installation, remote timer manipulation, erasure, uninstall or personal-data inspection accompanied this recording step.

All other mandatory physical acceptance remains open as listed above and in WAT-33: actual system surfaces and privacy controls beyond these entries, accessibility, goal alerts, offline/relaunch/reconciliation, repeated detached and long-duration trials, accepted resource/privacy measurements, actual distribution companion installation and public-build-2 upgrade coverage. The short owner walkthrough does not replace the WAT-05/23/24/25/26/28 gates or their separate destructive-data authority boundaries. Public-binary smoke remains post-release.

Separately, the owner confirmed Apple agreement acceptance and Xcode subsequently validated/uploaded build 9. App Store processing and saved draft attachment are recorded in WAT-33; they do not certify this physical session or complete App Review. REL-11 remains paused at the unanswered short-smoke observations, with the feasible results preserved for the next session.
