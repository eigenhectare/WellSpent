# QA-03 physical-device results

This document is the release-gate evidence for `IDK-323`. A row is marked Pass
only after observation on the physical device; simulator evidence is not
substituted for a pending device result.

## Test environment

- Run started: August 30, 2026
- Device: Drew's iPhone 17 Pro Max (`iPhone18,2`)
- OS: iOS 26.6.1
- Connection: USB, CoreDevice `7F366023-DE4F-5550-B092-DFF48B5871C3`
- App: `com.drewreilly.billablehours`
- Widget: `com.drewreilly.billablehours.widgets`
- App Group: `group.com.drewreilly.billablehours`
- Development team: `68LEY459MW`

## Short matrix

| Scenario | Expected result | Result | Evidence / notes |
| --- | --- | --- | --- |
| Lock Screen Stop, app process available, first cycle | Authentication precedes Stop; app opens Complete | Pass | Observed August 29. Console recorded successful intent completion and no shortcut error. |
| Lock Screen Stop, app process available, restarted timer | A second authenticated Stop also opens Complete | Pass | Observed August 29 at 18:04:22 local; the Complete screen remained open. |
| Dynamic Island Stop, app backgrounded and unlocked | Expanded presentation is legible; Stop routes to Complete | Pass | Workout-style expanded layout verified without clipping; running-card tap opens Track, and red Stop routes to completion. Physical findings fixed in `IDK-351` and `IDK-352`. |
| Lock Screen Stop, app suspended | Authentication precedes Stop; first persisted end time wins | Pass | After 45 seconds backgrounded, authentication preceded execution; completion opened and remained stable. First-end-time persistence is verified separately below. |
| Lock Screen Stop, app terminated | Intent succeeds without the app process; completion route or ended-card fallback remains available | Pass | The main PID was confirmed absent. Authenticated Stop foregrounded the app automatically; completion remained open with no error. Ended-card fallback is verified separately below. |
| Relaunch after Stop | The persisted session and ended Live Activity show the same first end time | Pass | Forced fallback cold-launched the correct persisted completion from the ended card. The intent uses the first durable handoff `endedAt` for the ended Activity state, and the production App Group first-write/round-trip device tests passed. |
| Live Activity dismissed while timer runs | Authoritative timer continues and the projection recovers on restart | Pass | After manual dismissal, the original timer continued. Opening the app recreated the Live Activity with continuous elapsed time rather than restarting. |
| Live Activities disabled | Timer remains usable and Settings explains the unavailable projection | Pass | Disabling removed the projection without stopping or resetting the timer. Re-enabling and reopening recreated the Live Activity with continuous elapsed time and no error. Follow-up discoverability issue: `IDK-353`. |
| Lock Screen / Dynamic Island presentation | Compact, expanded, Lock Screen, Dark Mode, and Always-On states remain legible | Pass | User confirmed compact Dynamic Island, expanded presentation, and the dimmed Always-On Lock Screen were readable and unclipped; the elapsed time and red Stop control remained distinguishable. |
| Ended-card fallback | If automatic foregrounding is unavailable, the ended card opens completion | Pass | Forced with a temporary signed build that disabled automatic foregrounding. Authenticated Stop left the ended card visible; tapping it cold-launched the correct completion with no error. Production behavior was restored afterward. |

## Eight-hour soak

- Start time: August 30, 2026 at 08:39:03 EDT
- Eight-hour mark: August 30, 2026 at 16:39:03 EDT
- End time: August 30, 2026 at 19:10:09 EDT
- Exact duration: 10:31:06
- Result: Pass

The timer must remain authoritative across normal use. At eight hours the Live
Activity may expire, but opening the app must recover the active timer and show
the long-running warning without losing or duplicating the session.

Physical evidence captured after the timer had run for more than ten hours:

- At 19:08, the phone was on the Home Screen and no Live Activity was visible,
  consistent with ActivityKit expiration.
- Foregrounding the already-installed app, without terminating it or installing
  a replacement build, recovered one active Client Redesign timer and displayed
  the long-running warning. The running card showed continuous elapsed time.
- Stopping once opened Complete with the persisted start `08:39:03`, first end
  `19:10:09`, and exact duration `10:31:06`.
- The Day report showed the same single chronological source row,
  `08:39:03–19:10:09`, with duration `10:31:06`. Existing shorter sessions
  remained separate, and no duplicate soak session or active timer appeared.

The previously noted `08:53:19` start was an observation-note error. The
completion and source-linked report screens independently confirmed the exact
persisted `08:39:03` start.

## Release decision

Every short-matrix row and the long-running soak now have physical-device
evidence. `IDK-323` / QA-03 passes its release gate.
