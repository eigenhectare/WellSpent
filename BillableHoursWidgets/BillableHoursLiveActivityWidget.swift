import ActivityKit
import BillableHoursShared
import SwiftUI
import WidgetKit

struct BillableHoursLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BillableHoursActivityAttributes.self) { context in
            LockScreenActivityView(context: context)
                .widgetURL(destinationURL(for: context))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    ExpandedDynamicIslandPresentation(
                        activityID: context.attributes.activityID,
                        startedAt: context.attributes.startedAt,
                        state: context.state
                    )
                }
            } compactLeading: {
                Image(systemName: context.state.phase == .running ? "stopwatch.fill" : "checkmark.circle.fill")
                    .accessibilityLabel(context.state.displayLabel)
            } compactTrailing: {
                if context.state.phase == .running {
                    ActivityStopButton(
                        activityID: context.attributes.activityID,
                        state: context.state,
                        compact: true
                    )
                } else {
                    Image(systemName: "checkmark.circle.fill")
                }
            } minimal: {
                if context.state.phase == .running {
                    ActivityStopButton(
                        activityID: context.attributes.activityID,
                        state: context.state,
                        compact: true
                    )
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityLabel("Stopped")
                }
            }
            .keylineTint(.red)
            .widgetURL(destinationURL(for: context))
        }
    }

    private func destinationURL(
        for context: ActivityViewContext<BillableHoursActivityAttributes>
    ) -> URL {
        switch context.state.phase {
        case .running:
            BillableHoursDeepLink.trackerURL
        case .stopped:
            BillableHoursDeepLink.completionURL(for: context.attributes.activityID)
        }
    }
}

private struct ExpandedDynamicIslandPresentation: View {
    let activityID: UUID
    let startedAt: Date
    let state: BillableHoursActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: state.phase == .running ? "stopwatch.fill" : "checkmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(state.phase == .running ? .blue : .green)
                .frame(width: 52, height: 52)
                .background(.quaternary, in: Circle())
                .accessibilityHidden(true)

            if state.phase == .running {
                ExpandedActivityStopButton(activityID: activityID, state: state)
            }

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 1) {
                ActivityElapsedView(startedAt: startedAt, state: state)
                    .font(.system(size: 34, weight: .medium, design: .rounded))

                Text(state.displayLabel)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if state.phase == .stopped {
                    Text("Tap to add notes")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}

private struct ExpandedActivityStopButton: View {
    let activityID: UUID
    let state: BillableHoursActivityAttributes.ContentState

    var body: some View {
        Button(intent: StopBillableTimerIntent(activityID: activityID)) {
            Image(systemName: "stop.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.red, in: Circle())
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .accessibilityLabel(state.stopAccessibilityLabel)
        .accessibilityHint("Ends the timer after saving its exact stop time")
    }
}

private struct LockScreenActivityView: View {
    let context: ActivityViewContext<BillableHoursActivityAttributes>

    var body: some View {
        LockScreenActivityPresentation(
            activityID: context.attributes.activityID,
            startedAt: context.attributes.startedAt,
            state: context.state
        )
    }
}

private struct LockScreenActivityPresentation: View {
    let activityID: UUID
    let startedAt: Date
    let state: BillableHoursActivityAttributes.ContentState
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.phase == .running ? "stopwatch.fill" : "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(state.phase == .running ? .blue : .green)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.displayLabel)
                    .font(.headline)
                    .lineLimit(1)
                ActivityElapsedView(startedAt: startedAt, state: state)
            }
            Spacer(minLength: 8)
            if state.phase == .running {
                ActivityStopButton(activityID: activityID, state: state, compact: false)
            }
        }
        .padding()
        .activityBackgroundTint(isLuminanceReduced ? Color.black : Color.black.opacity(0.08))
        .activitySystemActionForegroundColor(.primary)
        .accessibilityElement(children: .contain)
    }
}

private struct ActivityElapsedView: View {
    let startedAt: Date
    let state: BillableHoursActivityAttributes.ContentState

    var body: some View {
        if state.phase == .running {
            Text(startedAt, style: .timer)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .accessibilityLabel("Elapsed time")
        } else if let endedAt = state.endedAt {
            Text(
                Duration.seconds(max(0, endedAt.timeIntervalSince(startedAt))),
                format: .time(pattern: .hourMinuteSecond)
            )
            .monospacedDigit()
            .accessibilityLabel("Final elapsed time")
        } else {
            Text("Stopped")
        }
    }
}

private struct ActivityStopButton: View {
    let activityID: UUID
    let state: BillableHoursActivityAttributes.ContentState
    let compact: Bool

    var body: some View {
        Button(intent: StopBillableTimerIntent(activityID: activityID)) {
            if compact {
                Image(systemName: "stop.fill")
                    .frame(minWidth: 28, minHeight: 28)
            } else {
                Label("Stop", systemImage: "stop.fill")
                    .frame(minWidth: 64, minHeight: 44)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .accessibilityLabel(state.stopAccessibilityLabel)
        .accessibilityHint("Ends the timer after saving its exact stop time")
    }
}

#if DEBUG
    private let previewAttributes = BillableHoursActivityAttributes(
        activityID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        startedAt: Date.now.addingTimeInterval(-5_025)
    )

    private let privatePreviewState = BillableHoursActivityAttributes.ContentState(
        phase: .running,
        projectName: "Confidential Client",
        showsProjectName: false
    )

    private let namedPreviewState = BillableHoursActivityAttributes.ContentState(
        phase: .running,
        projectName: "Confidential Client",
        showsProjectName: true
    )

    #Preview("Lock Screen — Private", as: .content, using: previewAttributes) {
        BillableHoursLiveActivityWidget()
    } contentStates: {
        privatePreviewState
        namedPreviewState
    }

    #Preview("Dynamic Island — Compact", as: .dynamicIsland(.compact), using: previewAttributes) {
        BillableHoursLiveActivityWidget()
    } contentStates: {
        privatePreviewState
        namedPreviewState
    }

    #Preview("Dynamic Island — Minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
        BillableHoursLiveActivityWidget()
    } contentStates: {
        privatePreviewState
    }

    #Preview("Dynamic Island — Expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
        BillableHoursLiveActivityWidget()
    } contentStates: {
        privatePreviewState
        namedPreviewState
    }

    #Preview("Lock Screen — Dark, Accessibility") {
        LockScreenActivityPresentation(
            activityID: previewAttributes.activityID,
            startedAt: previewAttributes.startedAt,
            state: namedPreviewState
        )
        .padding()
        .background(.black)
        .environment(\.colorScheme, .dark)
        .environment(\.dynamicTypeSize, .accessibility3)
    }
#endif
