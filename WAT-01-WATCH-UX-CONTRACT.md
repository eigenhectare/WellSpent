# WAT-01 — Apple Watch Experience Contract

Status: Frozen for implementation  
Applies to: WellSpent companion app on watchOS 26  
Product owner: iPhone app; the watch owns a durable local working cache and
pending command journal  
Last reviewed: September 1, 2026

## 1. Product boundary

WellSpent for Apple Watch is a companion for immediate time capture. It starts,
monitors, pauses, resumes, switches, and ends billable timer runs without
requiring the paired iPhone to be reachable. Project creation, archival,
destructive editing, complete history, corrections, conflict review, and reports
remain on iPhone.

The app borrows familiar watch interaction grammar, not Workout identity. It
uses a recent-first picker, immediate one-tap start, glanceable live
metrics, horizontally separated controls, an optional time goal, haptics, and
an end summary. It does not use or imitate Apple Workout artwork, Activity
rings, HealthKit metrics, fitness terms, music controls, sensor coaching,
automatic workout detection, or Apple trademarks.

### Frozen platform decisions

- The Watch app ships inside the existing WellSpent iOS product.
- The minimum version is watchOS 26.
- A cached project catalog supports offline use; an empty cache directs setup
  to iPhone.
- An open timer is the default. A duration goal is optional and does not change
  which time is billable.
- Start captures its timestamp when the project is selected. Pause, Resume,
  Switch, and End likewise capture one boundary when invoked.
- A local save is the success boundary. Cross-device acknowledgement can happen
  later and is represented as pending, not failure.
- When divergent histories cannot be merged safely, the Watch blocks timer
  mutation and directs review to iPhone.
- Glanceable and reduced-luminance surfaces redact project names by default.
  An unlocked foreground Watch app may display them.

## 2. Interaction and navigation model

The root is either the recent-project picker or the current run. There is no
Watch dashboard. The Digital Crown scrolls a list or changes the vertical live
metric page. A horizontal swipe moves between live metrics and controls. Crown
presses and hardware button chords remain system-owned.

```text
No active run
  Project picker -> immediate persisted Start -> Live metrics <-> Controls
       |                                         |              |
       +-- goal setup ----------------------------+              +-- End -> Confirm -> Summary
                                                                +-- Pause/Resume
                                                                +-- New -> Project picker -> Switch

Any state + irreconcilable divergence -> Review on iPhone (mutations blocked)
```

Primary controls use at least a 44-point activation region, a text label, a
symbol, and a state-independent shape. Color reinforces meaning but never
carries it alone. Destructive End remains visually separate from Pause/Resume
and New.

## 3. State contract

Every state below has one defined entry, action, feedback, and exit. A state not
listed here requires a contract amendment before implementation.

| State | Entry | Available action | Immediate feedback | Exit |
| --- | --- | --- | --- | --- |
| Loading cache | App launches before the local snapshot is read | None | Neutral progress view; no stale control is tappable | Cache read produces setup, picker, active, paused, or conflict state |
| Finish setup on iPhone | No usable project catalog has ever been stored | Dismiss app; open WellSpent on iPhone | `Finish setup on iPhone`; paired-device symbol | A later valid snapshot replaces the empty state |
| Project picker, reachable | Valid active projects, no active run | Tap tile for open timer; tap `…` for goal; scroll with touch/Crown | Recent-first cards; play symbol; last project first | Open timer captures the boundary and attempts one atomic local save; goal choice enters goal setup |
| Project picker, offline | Cached active projects, phone unreachable | Same as reachable picker | Small `Offline` status; all cached projects remain enabled | Start persists locally immediately; connectivity silently clears the badge after delivery |
| Goal setup | Secondary project action selected | Choose `Open`, a preset, or custom duration; cancel | Selected duration is stated in time units; no fitness vocabulary | Choice captures the boundary and attempts one atomic local save; cancel returns to the picker |
| Start save failed | Atomic run/segment/outbox save fails | Retry; cancel | `Couldn’t start`; no running UI or success haptic | Retry re-enters save; cancel returns to picker |
| Running, acknowledged | Local running run has no pending mutation | Swipe to controls; Crown through metrics | Large exact billable elapsed; project identity; optional goal; green status word `Running` | Pause, Switch, End, pending sync, or conflict |
| Running, pending sync | Local running run has unacknowledged command(s) | All normal controls remain available | Subtle `Pending sync` with bidirectional-arrow symbol; never styled as an error | Ack clears marker; divergence enters conflict |
| Paused | Run is paused and owns no open counted segment | Resume, End, New/Switch | Frozen billable elapsed; `Paused`; accumulated paused duration; amber styling plus pause symbol | Resume opens a segment; End ends run; New switches at one boundary |
| Goal reached | Counted elapsed crosses optional goal | Continue, Pause, End, New | One local haptic/alert when permitted; `Goal reached`; elapsed continues | User action changes run state; dismissing alert keeps run active |
| Controls | Horizontal swipe from live metrics | End, Pause/Resume, New | Three large labeled controls; current pause state determines label | Swipe back, choose action, or system dismissal |
| End confirmation | End selected while confirmation preference is enabled | End Run; Cancel | Material-action copy includes current exact duration | Confirm atomically saves End and opens summary; cancel returns to controls |
| Switch picker | New selected, or Start requested while another run exists | Choose a different project; cancel | Current project remains identified; destination list is recent-first | Choice saves old end/new start at one boundary; cancel returns to active run |
| Switch save failed | Atomic old-run/new-run/outbox save fails | Retry; cancel | `Couldn’t switch`; original run remains authoritative and visibly active | Retry reattempts; cancel returns to original run |
| End summary, pending sync | End is durable locally | Add/edit one note; select active tags; Done | Project, billable duration, paused duration, start/end, goal result, segment count, `Pending sync` | Annotation save updates summary; Done returns to picker |
| End summary, acknowledged | End and annotation mutations are acknowledged | Same as pending summary | Same content with `Synced` | Done returns to picker |
| Annotation save failed | Note/tag atomic update fails | Retry; discard edit | Run remains ended; unsaved edit is clearly identified | Retry returns to summary on success; discard restores saved summary |
| Conflict / review required | Snapshot or command processing detects divergent mutation of one base | Dismiss app; review on iPhone | `Review on iPhone`; warning symbol; project names redacted on glanceable presentation | Only a resolved authoritative snapshot exits this state |
| Unsupported protocol | Counterpart snapshot/command version is newer than supported | Update app; dismiss | `Update WellSpent on iPhone and Apple Watch`; no mutation controls | Compatible app versions and a valid snapshot restore normal state |
| Corrupt cache recovered | Cache cannot be decoded but durable outbox remains readable | Continue to restricted state | Content-free recovery message; pending commands are not discarded | Valid snapshot restores state; otherwise setup/conflict remains |

## 4. Screen contracts

### Project tile

- Leading: project emoji when present, otherwise a filled folder symbol.
- Identity: project name in the unlocked foreground app and a project-color
  swatch. Color is never the only identifier.
- Primary action: the whole tile starts an open timer. The trailing
  `play.fill` reinforces that action.
- Secondary action: `ellipsis` opens Open/Time Goal choices and has its own
  accessibility label.
- Order: currently active destination when applicable, then watch-local recent
  use, then the stable iPhone-provided project order.

### Live metric pages

1. **Elapsed** — billable elapsed is largest; then project, Running/Paused, goal
   progress, and sync marker.
2. **Run** — billable elapsed, paused duration, start time, and segment count.
3. **Totals** — cached Today and This Week totals, each marked with the snapshot
   update time when stale or offline.

Metric pages never imply that a cached total is live. Project color may tint a
small accent or page background at low opacity; the elapsed number maintains
system contrast.

### Controls

- **End** — `xmark`, destructive crimson, always asks for confirmation by
  default.
- **Pause / Resume** — `pause.fill` / `play.fill`, amber when paused and green
  when resume is available.
- **New** — `arrow.triangle.2.circlepath`, blue; opens the Switch picker.

The words End, Pause/Resume, and New are always visible. Symbols are not used
alone, and no Activity-ring or Workout glyph is used.

### Summary

The summary is readable before any optional edit. Its fixed order is project,
billable duration, paused duration, start/end, goal result when applicable,
segment count, sync state, note, tags, and Done. Dictation, Scribble, and the
system keyboard are standard text-entry routes; the product does not implement
a custom keyboard.

## 5. Low-fidelity layout flows

These layouts specify hierarchy, not pixel styling. Implementations may adapt
spacing, but must preserve order, actions, and readable labels.

### Small display — Series 6 / SE class (368 × 448 captures)

```text
PICKER                 RUN                    CONTROLS
┌──────────────┐       ┌──────────────┐       ┌──────────────┐
│ Projects  ◌  │       │ Running   ↔  │       │ [X]   [Ⅱ]   │
│ ┌──────────┐ │       │              │ swipe │  End  Pause │
│ │ 🧾 Acme ▶│ │  ->   │   01:24:16   │ <-->  │              │
│ └──────────┘ │       │ 🧾 Acme      │       │   [↻] New   │
│ ┌──────────┐ │       │ Goal 62%     │       │              │
│ │ 📚 Tax  ▶│ │       │      • • •   │       │              │
└──────────────┘       └──────────────┘       └──────────────┘
```

Show two project tiles when possible and rely on Crown scrolling. On the live
page, elapsed and state outrank all decoration; hide the project color wash
before scaling elapsed below a readable size.

### Standard display — Series 10 / 11 class (416 × 496 captures)

```text
PICKER                 RUN / GOAL             SUMMARY
┌────────────────┐     ┌────────────────┐      ┌────────────────┐
│ Projects       │     │ 🧾 Acme        │      │ Done           │
│ ┌────────────┐ │     │ Running    ↔   │      │ 🧾 Acme        │
│ │ 🧾 Acme  ▶ │ │ ->  │                │  ->  │ 02:16:42       │
│ └────────────┘ │     │   01:24:16     │      │ Paused 08:03   │
│ ┌────────────┐ │     │ 1:30 goal 62%  │      │ 9:02–11:27     │
│ │ 📚 Tax   ▶ │ │     │       • • •    │      │ 3 segments     │
└────────────────┘     └────────────────┘      └────────────────┘
```

The standard layout may show one additional secondary line but keeps the same
semantic order as small displays.

### Ultra display — Ultra class (422 × 514 captures)

```text
RUN DETAIL                         SWITCH PICKER
┌─────────────────┐                ┌─────────────────┐
│ 🧾 Acme         │                │ New project     │
│ Paused          │                │ Current: Acme   │
│                 │     New        │ ┌─────────────┐ │
│    01:24:16     │ -------------> │ │ 📚 Tax     ▶│ │
│ paused 00:08:03 │                │ └─────────────┘ │
│ since 09:02     │                │ ┌─────────────┐ │
│ 3 segments      │                │ │ ✏️ Writing ▶│ │
│       • • •     │                │ └─────────────┘ │
└─────────────────┘                └─────────────────┘
```

Ultra gains breathing room and an extra visible row, not extra product
capability. Controls, order, and copy remain identical across sizes.

## 6. WellSpent visual and copy language

### Color roles

- Project identity: the existing iPhone project palette.
- Primary/navigation action: system blue.
- Running/success: system green with the text `Running` or `Synced`.
- Paused/attention: system amber with the text `Paused`.
- End/destructive: the iPhone app's deep crimson (`0.62, 0.02, 0.06`) with the
  text `End`.
- Conflict/error: system red or orange with a warning symbol and corrective
  text.

Colors adapt to contrast settings. Decorative gradients, rings, segmented
fitness progress, and Apple-red Workout styling are excluded. Goal progress is
a linear bar, fraction, or text percentage.

### Canonical copy

- `Projects`, `Open Timer`, `Time Goal`
- `Running`, `Paused`, `Pending sync`, `Offline`, `Synced`
- `End`, `Pause`, `Resume`, `New`, `End Run`, `Cancel`, `Done`
- `Finish setup on iPhone`, `Review on iPhone`
- `Couldn't start`, `Couldn't switch`, `Couldn't save changes`

Use `run` for the user-facing paused/resumable aggregate and `segment` only in
technical detail or the summary count. Use `billable duration`, never calories,
pace, workout, exercise, activity rings, or coaching.

## 7. Accessibility, privacy, and system behavior

- VoiceOver reads state, project identity, exact elapsed, goal state, sync state,
  then action. It does not announce decorative color or page dots.
- A project tile's label describes the result: `Start Acme timer` or `Switch
  timer to Acme`. Its hint states the one-timer or exact-boundary rule.
- Largest supported text may move secondary metrics below the fold. Primary
  state, elapsed, and current action never truncate silently.
- Reduce Motion removes decorative page motion. Timer actions remain immediate
  and use visible state changes in addition to haptics.
- Increase Contrast strengthens borders and text; status remains labeled.
- Always On / reduced luminance freezes decorative updates, dims project color,
  keeps the running/paused state and time legible, and redacts project identity
  according to the privacy preference.
- Project names are hidden by default in complications, Smart Stack, Control
  Widget, notification content, and reduced-luminance presentation. The neutral
  fallback is `Billable timer`.
- Diagnostics contain IDs only when required for support and never project
  names, notes, tags, or durations tied to project identity.

## 8. Pattern differentiation ledger

| Familiar pattern | Billable-time purpose | WellSpent differentiation |
| --- | --- | --- |
| Recent-first large choices | Start the right client/project quickly | Project emoji, project palette, iPhone-owned catalog |
| Immediate one-tap start | Capture billable time without ceremony or delay | The selection timestamp becomes the exact persisted billing boundary |
| Large live metric | Check elapsed billable time at a glance | Exact segment-derived time; no sensor or health data |
| Horizontal controls page | Separate monitoring from material mutations | End confirmation, Pause/Resume segments, exact Switch |
| Optional goal | Time-box a work session | Duration only; goal never changes billed time |
| Haptic milestones | Confirm local command and goal boundary | Success means durable local persistence, not cross-device delivery |
| End summary | Verify a material billing record | Paused duration, timestamps, notes, tags, segments, sync state |
| Crown navigation | Traverse recent projects or metric pages | No workout views, pace zones, media, or rings |

Explicitly excluded from all future interpretation of this contract: HealthKit,
`HKWorkoutSession`, Workout Processing, `WKExtendedRuntimeSession`, Activity
rings, heart rate, calories, distance, pace, route, coaching, media controls,
automatic detection, and Apple Workout names or artwork.

## 9. Implementation citations and change control

- WAT-02 owns run/segment and migration semantics behind these states.
- WAT-03 owns pending sync, offline, unsupported protocol, and conflict rules.
- WAT-05 owns the evidence matrices for displays, accessibility, privacy,
  install/upgrade, and release.
- WAT-12 through WAT-20 implement the screens and system surfaces defined here.

Changes to primary actions, timestamp capture, offline availability, conflict
blocking, privacy defaults, canonical copy, or excluded capabilities require an
explicit update to this contract and the dependent Linear issues. Spacing,
animation polish, and platform-standard component substitutions do not require
a contract change when hierarchy and behavior are preserved.

## 10. Review checklist

- [x] Primary, error, offline, conflict, privacy, and unsupported-version states
  have entry, action, feedback, and exit behavior.
- [x] Touch, swipe, and Digital Crown responsibilities are explicit.
- [x] Small, standard, and Ultra hierarchy is documented.
- [x] WellSpent copy, symbols, colors, and excluded fitness concepts are frozen.
- [x] Companion ownership, watchOS 26 baseline, and iPhone project management
  are confirmed.
- [ ] Walk through on a physical Series/SE-class watch.
- [ ] Walk through on an Ultra-class simulator.
- [ ] Record implementation evidence for VoiceOver, largest text, Increase
  Contrast, Reduce Motion, and Always On in WAT-05.
