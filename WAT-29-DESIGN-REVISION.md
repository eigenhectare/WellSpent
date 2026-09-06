# Native design revision — WellSpent 0.2.0 (5)

This revision ports the approved iPhone timer and Watch concepts into native
SwiftUI. The iPhone timer adapts between warm light and navy dark appearance.
The Watch uses a black canvas, navy panels, amber controls and teal status,
with native scrolling, Crown paging and accessibility text-size fallbacks.

## Complication and Smart Stack entry

- Idle: every status complication and the Smart Stack status widget opens
  Projects. Opening the app does not start time; tapping a project starts its
  open timer. Options still offers an optional time goal.
- Running: opening the complication returns to the current elapsed screen.
- Paused: opening returns to the same paused run. Time remains frozen until
  Resume is selected.
- A stale idle or prior-run link resolves against the current persisted state.
  It cannot replace a newer running or paused timer.
- Conflict, update-required and setup states retain their existing recovery
  screens. Widget project names remain private by default; reduced luminance
  hides identity even after the optional name-display setting is enabled.

The distinct Control Center control retains its established start/pause/resume
semantics. The status complication is a navigation entry point.

## Validation boundaries

The engineering source at `53ec2e2bf462c70906ccd462791e022eb69c136a`
passed all 13 stages of `scripts/ci.sh`: 306 unit/contract cases, 62 Watch UI
cases and 18 iPhone UI cases, with no failures or skipped cases. Independent
review also checked the native light/dark iPhone captures, ordinary Watch
screens, five focused 40 mm accessibility cases and both iPhone appearances
at the largest text size.

That engineering run used the prior version/build values, `0.1.0 (4)`. The
subsequent `0.2.0 (5)` allocation changes no app behavior; its source delta and
signed archive are inspected separately. CI evidence remains bound to the
engineering commit rather than being relabeled as an archive-commit test run.

Engineering and simulator evidence is retained under
`AgentControl/evidence/DESIGN-00-INTEGRATION/`. The exact source and signed
archive identities are retained separately under
`AgentControl/evidence/DESIGN-05-BUILD/`. Archive evidence must not be relabeled
as App Review approval, public release, or physical-device smoke.

The release allocation changes only version/build values and the generated
Xcode project after engineering validation. No persistence model, wire
contract, signing identity, bundle identifier or privacy declaration changes.

The warm navigation regression invokes the production URL handler from a
Debug-only app-hosted control. Xcode's Watch URL launch API failed to obtain a
process ID on the simulator, so that API attempt is not a passed URL-delivery
observation. Actual WidgetKit tap delivery, face tint and Smart Stack placement
need observation on the installed Watch.

## Build tooling

Project generation uses [XcodeGen 2.46.0](https://github.com/yonaskolb/XcodeGen/releases/tag/2.46.0), matching the checked-in project. This Mac had 2.45.4 globally, so validation used a task-local 2.46.0 binary whose download digest matched the official release metadata.

## Try the installed build

To add the complication, hold the Watch face, choose Edit, swipe to the
complication slots, then select WellSpent in a supported slot. Press the Crown
to save. [Apple's complication guide](https://support.apple.com/en-au/guide/watch/apd8d0b9c582/watchos)
shows the face-editing controls.

To add the Smart Stack widget, turn the Crown upward from the face, scroll to
the bottom and choose Edit, then use Add Widget and select WellSpent. Pin it
for easier repeat testing. See [Apple's Smart Stack guide](https://support.apple.com/en-au/guide/watch/apdecf142fb9/watchos).

1. Open WellSpent on both devices and confirm the project you want to test is
   available on the Watch.
2. With no timer active, tap either surface. Confirm Projects appears, then tap
   a project and confirm time starts for that project.
3. Pause the run, return to the face, and tap the complication. Confirm the
   same project and frozen elapsed time appear. Swipe right to Controls and
   choose Resume to continue.
4. With a timer running, leave the app on Controls or a metrics page and reopen
   from the complication. Confirm it returns to elapsed without changing the
   timer.
5. Check the iPhone timer in light and dark appearance and with larger text.
   On Watch, check that wrist-down presentation hides private project names.

Device installation and these physical checks are separate from creating the
signed archive. This revision does not submit or release an App Store version.
