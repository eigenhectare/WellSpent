# ACT-01 Live Activity presentations

## Presentation contract

`BillableHoursActivityAttributes.ContentState` now carries the presentation
phase, optional final timestamp, optional project name, and explicit privacy
choice. `displayLabel` returns `Billable timer` unless the user has opted in
and a nonempty project name is available. Accessibility Stop labels follow the
same privacy rule.

The WidgetKit extension provides:

- A Lock Screen presentation with privacy-appropriate context, system-derived
  elapsed time, and a red square Stop action.
- Expanded, compact, and minimal Dynamic Island families with an actual
  `StopBillableTimerIntent`, never a pause affordance.
- A final stopped state and tap-to-add-notes widget URL.
- Scalable/monospaced duration text, descriptive accessibility labels, Dark
  Mode support, and reduced-luminance background handling.

The source includes Xcode previews for Lock Screen private/named states and
compact, minimal, and expanded Dynamic Island states, plus a Dark Mode
accessibility-Dynamic-Type presentation preview. The extension is compiled in
both Debug and Release verification.

## Deliberate boundary

ACT-01 built presentations only. The later production lifecycle, durable
intent handoff, completion routing, and foreground/eight-hour reconciliation
are documented in `LIVE-ACTIVITY-LIFECYCLE.md`.

Physical Lock Screen authentication, real process transitions, Dynamic Island
hardware behavior, Always-On reduced luminance, and the ended-card fallback
remain assigned to `IDK-323` / `QA-03`. Simulator and compile results must not
be described as physical-device evidence.
