# WellSpent feasibility sources

This is the project-specific source map for the global `assess-feasibility` skill. Revalidate platform behavior against the current SDK and documentation before relying on a dated conclusion.

## Apple Watch surfaces and actions

- [WidgetKit controls](https://developer.apple.com/documentation/widgetkit/controls-collection): establishes that controls from a watchOS app can appear in Apple Watch Control Center and the Smart Stack and perform actions through App Intents.
- [Creating controls to perform actions across the system](https://developer.apple.com/documentation/widgetkit/creating-controls-to-perform-actions-across-the-system): control value providers, button/toggle actions, and the requirement to save state before `perform()` returns.
- [Updating controls locally and remotely](https://developer.apple.com/documentation/widgetkit/updating-controls-locally-and-remotely): documents when a control reloads, including the automatic reload after its intent finishes.
- [Adding interactivity to widgets and Live Activities](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities): supported widget and Live Activity interaction primitives and intent requirements.
- [AppIntent `supportedModes`](https://developer.apple.com/documentation/appintents/appintent/supportedmodes): foreground/background execution choices. Confirm the exact installed SDK spelling and semantics before choosing a mode.
- [Developing a WidgetKit strategy](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy): distinguishes widgets, controls, complications, and paired-iPhone Live Activities.

## Live Activities on Apple Watch

- [Live Activities design guidance](https://developer.apple.com/design/human-interface-guidelines/live-activities): Apple Watch presentation and interaction guidance.
- [ActivityFamily](https://developer.apple.com/documentation/widgetkit/activityfamily): supplemental Watch layout for an iPhone-originated Live Activity.
- [Launching an app from a Live Activity](https://developer.apple.com/documentation/activitykit/launching-your-app-from-a-live-activity): links and launch behavior; do not assume a link is a direct command primitive.
- [ActivityKit](https://developer.apple.com/documentation/activitykit): authoritative lifecycle API and system ownership boundaries.

## Cross-device state

- [Watch Connectivity](https://developer.apple.com/documentation/watchconnectivity): transport APIs and reachability/background-delivery constraints.
- Local durable Watch state is shared by the Watch app and its WidgetKit extension through App Group `group.com.drewreilly.wellspent.watch`. Relevant code: `WellSpentWatchStore/WatchStorePersistence.swift` and the two Watch entitlements files.
- The native Watch status widget is `WellSpentWatchWidgets/WellSpentWatchStatusWidget.swift`. The separate native control is `WellSpentWatchWidgets/WellSpentWatchTimerControl.swift`. The iPhone-originated mirrored Live Activity is implemented under `WellSpentWidgets/`.

## Current dated findings

### 2026-09-07 — native Watch Stop versus mirrored Live Activity Stop

- **Supported:** a Watch-native WidgetKit control can perform a Stop action through an App Intent. Apple explicitly documents timer start/stop as a control use case.
- **Supported with an architecture requirement:** an interactive Watch widget can also use a button intent, but the mutation must be available in the process where the intent executes. An in-memory dispatcher installed only by the Watch app is not a durable extension boundary.
- **Conditional:** an iPhone Live Activity mirrored into the Watch Smart Stack can expose interaction, but its execution and presentation refresh cross an OS-owned device/process boundary. Do not promise immediate mirrored refresh without physical evidence.
- **No public mechanism found (Xcode 26.5):** neither the installed Watch SDK nor Apple’s ActivityKit and WidgetKit documentation exposes an API for WellSpent to change the user's per-app “Mirror Live Activity from iPhone” Watch setting. Treat it as user-owned configuration and recheck future SDKs before calling it permanently unsupported.

## Local verification aids

- Inspect the installed SDK declarations when web documentation is ambiguous: `xcrun --sdk watchos --show-sdk-path`, then search the relevant `.swiftinterface` files.
- Regenerate from `project.yml` after target membership or Info.plist changes and run `scripts/xcodegen-drift-check.sh`.
- Use Watch unit tests for durable command semantics, simulator/UI tests for layout and routing, and a paired physical Phone/Watch test for cross-device delivery or system-managed Smart Stack behavior. These evidence classes are not interchangeable.
