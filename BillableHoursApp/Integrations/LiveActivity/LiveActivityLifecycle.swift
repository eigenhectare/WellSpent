@preconcurrency import ActivityKit
import BillableHoursShared
import Foundation

struct LiveActivityProjection: Equatable, Sendable {
    let sessionID: UUID
    let startedAt: Date
    let projectName: String
    let showsProjectName: Bool
    let requestedAt: Date

    var runningState: BillableHoursActivityAttributes.ContentState {
        BillableHoursActivityAttributes.ContentState(
            phase: .running,
            projectName: projectName,
            showsProjectName: showsProjectName
        )
    }
}

struct ExistingLiveActivityProjection: Equatable, Sendable {
    let systemID: String
    let sessionID: UUID
    let startedAt: Date
}

struct LiveActivityReconciliationPlan: Equatable, Sendable {
    let endSystemIDs: [String]
    let updateSystemID: String?
    let requestsActivity: Bool

    static func make(
        active: LiveActivityProjection?,
        existing: [ExistingLiveActivityProjection]
    ) -> LiveActivityReconciliationPlan {
        let ordered = existing.sorted { $0.systemID < $1.systemID }
        guard let active else {
            return LiveActivityReconciliationPlan(
                endSystemIDs: ordered.map(\.systemID),
                updateSystemID: nil,
                requestsActivity: false
            )
        }

        let matching = ordered.filter {
            $0.sessionID == active.sessionID && $0.startedAt == active.startedAt
        }
        let kept = matching.first
        return LiveActivityReconciliationPlan(
            endSystemIDs: ordered.filter { $0.systemID != kept?.systemID }.map(\.systemID),
            updateSystemID: kept?.systemID,
            requestsActivity: kept == nil
        )
    }
}

@MainActor
protocol LiveActivityLifecycle: AnyObject {
    var activitiesEnabled: Bool { get }

    func start(_ projection: LiveActivityProjection) async throws
    func switchActivity(
        from previous: LiveActivityProjection,
        to active: LiveActivityProjection
    ) async throws
    func stop(_ projection: LiveActivityProjection, endedAt: Date) async throws
    func reconcile(with active: LiveActivityProjection?) async throws
}

enum LiveActivityLifecycleError: LocalizedError, Equatable {
    case activitiesDisabled
    case forcedTestFailure

    var errorDescription: String? {
        switch self {
        case .activitiesDisabled:
            "Live Activities are disabled."
        case .forcedTestFailure:
            "The Live Activity projection could not be updated."
        }
    }
}

@MainActor
final class ActivityKitLiveActivityLifecycle: LiveActivityLifecycle {
    static let systemActiveLifetime: TimeInterval = 8 * 60 * 60

    private let arguments: [String]

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        self.arguments = arguments
    }

    var activitiesEnabled: Bool {
        if arguments.contains("UITEST_LIVE_ACTIVITIES_DISABLED") { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(_ projection: LiveActivityProjection) async throws {
        try throwForcedFailureIfRequested()
        guard activitiesEnabled else {
            throw LiveActivityLifecycleError.activitiesDisabled
        }

        if let existing = activities.first(where: {
            $0.attributes.activityID == projection.sessionID
                && $0.attributes.startedAt == projection.startedAt
        }) {
            await existing.update(runningContent(for: projection))
            return
        }

        for stale in activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }
        _ = try Activity.request(
            attributes: BillableHoursActivityAttributes(
                activityID: projection.sessionID,
                startedAt: projection.startedAt
            ),
            content: runningContent(for: projection),
            pushType: nil
        )
    }

    func switchActivity(
        from previous: LiveActivityProjection,
        to active: LiveActivityProjection
    ) async throws {
        try throwForcedFailureIfRequested()
        for activity in activities where activity.attributes.activityID == previous.sessionID {
            let finalState = BillableHoursActivityAttributes.ContentState(
                phase: .stopped,
                endedAt: active.startedAt,
                projectName: previous.projectName,
                showsProjectName: previous.showsProjectName
            )
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .immediate
            )
        }
        try await start(active)
    }

    func stop(_ projection: LiveActivityProjection, endedAt: Date) async throws {
        try throwForcedFailureIfRequested()
        let finalState = BillableHoursActivityAttributes.ContentState(
            phase: .stopped,
            endedAt: endedAt,
            projectName: projection.projectName,
            showsProjectName: projection.showsProjectName
        )
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        for activity in activities where activity.attributes.activityID == projection.sessionID {
            await activity.end(finalContent, dismissalPolicy: .default)
        }
    }

    func reconcile(with active: LiveActivityProjection?) async throws {
        try throwForcedFailureIfRequested()
        let currentActivities = activities
        let plan = LiveActivityReconciliationPlan.make(
            active: active,
            existing: currentActivities.map {
                ExistingLiveActivityProjection(
                    systemID: $0.id,
                    sessionID: $0.attributes.activityID,
                    startedAt: $0.attributes.startedAt
                )
            }
        )

        for activity in currentActivities where plan.endSystemIDs.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        guard let active else { return }
        guard activitiesEnabled else {
            throw LiveActivityLifecycleError.activitiesDisabled
        }

        if let updateSystemID = plan.updateSystemID,
            let matchingActivity = currentActivities.first(where: { $0.id == updateSystemID })
        {
            await matchingActivity.update(runningContent(for: active))
        } else if plan.requestsActivity {
            try await start(active)
        }
    }

    private var activities: [Activity<BillableHoursActivityAttributes>] {
        Activity<BillableHoursActivityAttributes>.activities
    }

    private func runningContent(
        for projection: LiveActivityProjection
    ) -> ActivityContent<BillableHoursActivityAttributes.ContentState> {
        ActivityContent(
            state: projection.runningState,
            staleDate: projection.requestedAt.addingTimeInterval(Self.systemActiveLifetime)
        )
    }

    private func throwForcedFailureIfRequested() throws {
        #if DEBUG
            if arguments.contains("UITEST_FORCE_ACTIVITY_ERROR") {
                throw LiveActivityLifecycleError.forcedTestFailure
            }
        #endif
    }
}
