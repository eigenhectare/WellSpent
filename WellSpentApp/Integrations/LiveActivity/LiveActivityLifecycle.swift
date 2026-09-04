import Foundation
import WellSpentShared

struct LiveActivityProjection: Equatable, Sendable {
    /// Compatibility name; this is always a TimerRun UUID, never an open segment.
    let sessionID: UUID
    let startedAt: Date
    let projectName: String
    let showsProjectName: Bool
    let requestedAt: Date
    let phase: TimerRunState
    let countedSeconds: TimeInterval
    let currentSegmentStartedAt: Date?
    let revision: Int64
    let endedAt: Date?
    let requiresReview: Bool
    let watchConfirmationPending: Bool

    init(
        sessionID: UUID, startedAt: Date, projectName: String,
        showsProjectName: Bool, requestedAt: Date,
        phase: TimerRunState = .running, countedSeconds: TimeInterval? = nil,
        currentSegmentStartedAt: Date? = nil, revision: Int64 = 1,
        endedAt: Date? = nil, requiresReview: Bool = false,
        watchConfirmationPending: Bool = false
    ) {
        self.sessionID = sessionID
        self.startedAt = startedAt
        self.projectName = showsProjectName && !requiresReview ? projectName : ""
        self.showsProjectName = showsProjectName && !requiresReview
        self.requestedAt = requestedAt
        self.phase = phase
        self.countedSeconds = countedSeconds ?? max(0, requestedAt.timeIntervalSince(startedAt))
        self.currentSegmentStartedAt = currentSegmentStartedAt ?? (phase == .running ? startedAt : nil)
        self.revision = revision
        self.endedAt = endedAt
        self.requiresReview = requiresReview
        self.watchConfirmationPending = watchConfirmationPending
    }

    var contentState: WellSpentActivityAttributes.ContentState {
        let accumulatedBeforeCurrent: TimeInterval
        if phase == .running, !requiresReview, let currentSegmentStartedAt {
            accumulatedBeforeCurrent = max(
                0, countedSeconds - requestedAt.timeIntervalSince(currentSegmentStartedAt)
            )
        } else {
            accumulatedBeforeCurrent = countedSeconds
        }
        let contentPhase: WellSpentActivityAttributes.ContentState.Phase
        switch phase {
        case .running: contentPhase = .running
        case .paused: contentPhase = .paused
        case .ended: contentPhase = .stopped
        }
        return WellSpentActivityAttributes.ContentState(
            phase: contentPhase, endedAt: endedAt,
            projectName: projectName, showsProjectName: showsProjectName,
            countedSeconds: accumulatedBeforeCurrent,
            currentSegmentStartedAt: phase == .running && !requiresReview ? currentSegmentStartedAt : nil,
            revision: revision, requiresReview: requiresReview,
            watchConfirmationPending: watchConfirmationPending
        )
    }
}

struct LiveActivityDesiredState: Equatable, Sendable {
    var active: LiveActivityProjection?
    var completed: [LiveActivityProjection] = []
    var isCanonicalStateAvailable = true
}

struct ExistingLiveActivityProjection: Equatable, Sendable {
    let systemID: String
    let sessionID: UUID
    let startedAt: Date
    var isEnded = false
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
                updateSystemID: nil, requestsActivity: false
            )
        }
        let matching = ordered.filter {
            $0.sessionID == active.sessionID && $0.startedAt == active.startedAt
                && !$0.isEnded
        }
        let kept = matching.first
        return LiveActivityReconciliationPlan(
            endSystemIDs: ordered.filter { $0.systemID != kept?.systemID }.map(\.systemID),
            updateSystemID: kept?.systemID, requestsActivity: kept == nil
        )
    }
}

@MainActor
protocol LiveActivityLifecycle: AnyObject {
    var activitiesEnabled: Bool { get }

    /// Synchronous publication fences old work at the canonical commit boundary,
    /// even if the task which drains ActivityKit has not started yet.
    func setDesiredState(_ state: LiveActivityDesiredState)
    func reconcile() async throws
}

@MainActor
protocol LiveActivityDriver: AnyObject {
    var activitiesEnabled: Bool { get }
    var canRequestActivity: Bool { get }
    var activities: [ExistingLiveActivityProjection] { get }
    func request(_ projection: LiveActivityProjection) throws
    func update(systemID: String, projection: LiveActivityProjection) async throws
    func end(systemID: String, final: LiveActivityProjection?) async throws
}

enum LiveActivityLifecycleError: LocalizedError, Equatable {
    case activitiesDisabled
    case foregroundRequired
    case canonicalStateUnavailable
    case projectionDisappeared
    case forcedTestFailure

    var errorDescription: String? {
        switch self {
        case .activitiesDisabled: "Live Activities are disabled."
        case .foregroundRequired: "Open WellSpent on iPhone to show its saved timer on the Lock Screen."
        case .canonicalStateUnavailable: "Saved timer state could not be read."
        case .projectionDisappeared: "The Live Activity disappeared before it could be updated."
        case .forcedTestFailure: "The Live Activity projection could not be updated."
        }
    }
}

/// The sole ActivityKit writer. No command carries a captured pre-save projection.
/// At most one driver call is in flight, and every suspension point is followed
/// by a generation check before another side effect can be submitted.
@MainActor
final class ActivityKitLiveActivityLifecycle: LiveActivityLifecycle {
    static let systemActiveLifetime: TimeInterval = 8 * 60 * 60

    private let driver: any LiveActivityDriver
    private var desired = LiveActivityDesiredState(active: nil)
    private var generation: UInt64 = 0
    private var appliedGeneration: UInt64?
    private var drainTask: Task<Void, Error>?

    init(driver: (any LiveActivityDriver)? = nil) {
        self.driver = driver ?? ActivityKitLiveActivityDriver()
    }

    var activitiesEnabled: Bool { driver.activitiesEnabled }

    func setDesiredState(_ state: LiveActivityDesiredState) {
        guard state != desired else { return }
        desired = state
        generation &+= 1
    }

    func reconcile() async throws {
        while true {
            let task: Task<Void, Error>
            if let existing = drainTask {
                task = existing
            } else {
                task = Task { @MainActor in
                    defer { self.drainTask = nil }
                    try await self.drain()
                }
                drainTask = task
            }
            try await task.value
            if appliedGeneration == generation { return }
        }
    }

    private func drain() async throws {
        while true {
            let capturedGeneration = generation
            let snapshot = desired
            do {
                try await apply(snapshot, generation: capturedGeneration)
            } catch {
                // A failure for superseded work must not hide or prevent the
                // next canonical projection (including erasure/privacy changes).
                if capturedGeneration == generation { throw error }
            }
            if capturedGeneration == generation {
                appliedGeneration = capturedGeneration
                return
            }
        }
    }

    private func apply(_ snapshot: LiveActivityDesiredState, generation captured: UInt64) async throws {
        guard snapshot.isCanonicalStateAvailable else {
            throw LiveActivityLifecycleError.canonicalStateUnavailable
        }
        let existing = driver.activities
        let plan = LiveActivityReconciliationPlan.make(active: snapshot.active, existing: existing)
        for item in existing where plan.endSystemIDs.contains(item.systemID) {
            guard captured == generation else { return }
            let final =
                snapshot.active == nil
                ? snapshot.completed.first {
                    $0.sessionID == item.sessionID && $0.startedAt == item.startedAt
                } : nil
            try await driver.end(systemID: item.systemID, final: final)
        }
        guard captured == generation, let active = snapshot.active else { return }
        guard driver.activitiesEnabled else { throw LiveActivityLifecycleError.activitiesDisabled }
        if let systemID = plan.updateSystemID {
            try await driver.update(systemID: systemID, projection: active)
        } else if plan.requestsActivity {
            // WatchConnectivity delivery may update/end an existing card while
            // backgrounded. It does not confer permission to create a new one.
            guard driver.canRequestActivity else { throw LiveActivityLifecycleError.foregroundRequired }
            try driver.request(active)
        }
    }
}
