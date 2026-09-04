@preconcurrency import ActivityKit
import Foundation
import UIKit
import WellSpentShared

@MainActor
final class ActivityKitLiveActivityDriver: LiveActivityDriver {
    var activitiesEnabled: Bool {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_LIVE_ACTIVITIES_DISABLED") { return false }
        #endif
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    var canRequestActivity: Bool { UIApplication.shared.applicationState == .active }

    var activities: [ExistingLiveActivityProjection] {
        Activity<WellSpentActivityAttributes>.activities
            .filter { $0.activityState != .dismissed }
            .map {
                ExistingLiveActivityProjection(
                    systemID: $0.id, sessionID: $0.attributes.runID, startedAt: $0.attributes.startedAt,
                    isEnded: $0.activityState == .ended
                )
            }
    }

    func request(_ projection: LiveActivityProjection) throws {
        try throwForcedFailureIfRequested()
        _ = try Activity.request(
            attributes: WellSpentActivityAttributes(
                activityID: projection.sessionID, startedAt: projection.startedAt
            ),
            content: content(for: projection), pushType: nil
        )
    }

    func update(systemID: String, projection: LiveActivityProjection) async throws {
        try throwForcedFailureIfRequested()
        guard let activity = activity(systemID), activity.activityState != .ended,
            activity.activityState != .dismissed
        else {
            throw LiveActivityLifecycleError.projectionDisappeared
        }
        guard activity.content.state != projection.contentState else { return }
        await activity.update(content(for: projection))
    }

    func end(systemID: String, final: LiveActivityProjection?) async throws {
        try throwForcedFailureIfRequested()
        guard let activity = activity(systemID) else { return }
        await activity.end(
            final.map { ActivityContent(state: $0.contentState, staleDate: nil) },
            dismissalPolicy: final == nil ? .immediate : .default
        )
    }

    private func activity(_ systemID: String) -> Activity<WellSpentActivityAttributes>? {
        Activity<WellSpentActivityAttributes>.activities.first { $0.id == systemID }
    }

    private func content(
        for projection: LiveActivityProjection
    ) -> ActivityContent<WellSpentActivityAttributes.ContentState> {
        ActivityContent(
            state: projection.contentState,
            staleDate: projection.requestedAt.addingTimeInterval(ActivityKitLiveActivityLifecycle.systemActiveLifetime)
        )
    }

    private func throwForcedFailureIfRequested() throws {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_ACTIVITY_ERROR") {
                throw LiveActivityLifecycleError.forcedTestFailure
            }
        #endif
    }
}
