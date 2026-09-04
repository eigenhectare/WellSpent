import ActivityKit
import SwiftUI
import WellSpentShared
import WidgetKit

struct WellSpentLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WellSpentActivityAttributes.self) { context in
            LiveActivityContent(context: context)
                .widgetURL(context.state.destinationURL(runID: context.attributes.runID))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom, priority: 1) {
                    presentation(context, family: .expanded)
                }
            } compactLeading: {
                Image(systemName: "stopwatch.fill")
                    .accessibilityLabel("WellSpent")
            } compactTrailing: {
                presentation(context, family: .compact)
            } minimal: {
                presentation(context, family: .minimal)
            }
            .keylineTint(.accentColor)
            .widgetURL(context.state.destinationURL(runID: context.attributes.runID))
        }
        .supplementalActivityFamilies([.small])
    }

    private func presentation(
        _ context: ActivityViewContext<WellSpentActivityAttributes>,
        family: WellSpentActivityPresentation.Family
    ) -> some View {
        WellSpentActivityPresentation(
            runID: context.attributes.runID, startedAt: context.attributes.startedAt,
            state: context.state, family: family, isStale: context.isStale
        )
    }
}

private struct LiveActivityContent: View {
    let context: ActivityViewContext<WellSpentActivityAttributes>
    @Environment(\.activityFamily) private var family
    @Environment(\.isLuminanceReduced) private var dimmed

    var body: some View {
        WellSpentActivityPresentation(
            runID: context.attributes.runID, startedAt: context.attributes.startedAt,
            state: context.state, family: family == .small ? .watchMirror : .lockScreen,
            isStale: context.isStale
        )
        .activityBackgroundTint(dimmed ? .black : .black.opacity(0.08))
        .activitySystemActionForegroundColor(.primary)
    }
}

#if DEBUG
    private let previewAttributes = WellSpentActivityAttributes(
        activityID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        startedAt: Date.now.addingTimeInterval(-5_025)
    )
    private let previewStates: [WellSpentActivityAttributes.ContentState] = [
        .init(phase: .running, projectName: "Design review", showsProjectName: true),
        .init(phase: .paused, countedSeconds: 5025, revision: 2),
        .init(phase: .running, countedSeconds: 5025, revision: 3, requiresReview: true),
        .init(phase: .stopped, endedAt: .now, countedSeconds: 5025, revision: 4),
    ]

    #Preview("Lock Screen and Watch", as: .content, using: previewAttributes) {
        WellSpentLiveActivityWidget()
    } contentStates: {
        previewStates[0]
        previewStates[1]
        previewStates[2]
        previewStates[3]
    }

    #Preview("Dynamic Island compact", as: .dynamicIsland(.compact), using: previewAttributes) {
        WellSpentLiveActivityWidget()
    } contentStates: {
        previewStates[0]
        previewStates[1]
        previewStates[2]
    }

    #Preview("Dynamic Island minimal", as: .dynamicIsland(.minimal), using: previewAttributes) {
        WellSpentLiveActivityWidget()
    } contentStates: {
        previewStates[0]
        previewStates[1]
        previewStates[2]
    }

    #Preview("Dynamic Island expanded", as: .dynamicIsland(.expanded), using: previewAttributes) {
        WellSpentLiveActivityWidget()
    } contentStates: {
        previewStates[0]
        previewStates[1]
        previewStates[2]
        previewStates[3]
    }
#endif
