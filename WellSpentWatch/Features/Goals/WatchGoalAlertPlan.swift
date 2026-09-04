import Foundation
import WellSpentWatchStore

struct WatchGoalAlertPlan: Equatable, Sendable {
    static let identifier = "wellspent.duration-goal"
    let runID: UUID
    let goalSeconds: Int
    let deadline: Date
    let title: String
    let body: String

    var goalKey: String { "\(runID.uuidString):\(goalSeconds)" }

    static func make(state: WatchStoreState?) -> WatchGoalAlertPlan? {
        guard let state else { return nil }
        let presentation = WatchWidgetState.make(
            projection: state.projection, pendingSync: state.isPendingSync,
            isBlocked: state.isBlocked, recentProjectIDs: [])
        guard presentation.timerState == .running,
            let runID = presentation.runID,
            let seconds = presentation.durationGoalSeconds, seconds > 0,
            let deadline = presentation.goalDeadline, deadline.timeIntervalSince1970.isFinite
        else { return nil }
        return WatchGoalAlertPlan(
            runID: runID, goalSeconds: seconds, deadline: deadline,
            title: String(localized: "Time goal reached"),
            body: presentation.projectName.map {
                String(localized: "\($0): your billable time goal is complete. Your timer is still running.")
            }
                ?? String(localized: "Your billable time goal is complete. Your timer is still running."))
    }
}

enum WatchGoalAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

@MainActor
protocol WatchGoalNotificationCenter {
    func authorization() async -> WatchGoalAuthorization
    func requestAuthorization() async throws -> Bool
    func pendingGoal() async -> WatchGoalAlertPlan?
    func removeGoalAlerts()
    func add(_ plan: WatchGoalAlertPlan, now: Date) async throws
    func setForegroundGoalVisible(_ visible: Bool)
}

extension WatchGoalNotificationCenter {
    func setForegroundGoalVisible(_ visible: Bool) {}
}

struct WatchGoalProgress: Equatable {
    let runID: UUID
    let goalSeconds: Int?
    let reached: Bool
    let visible: Bool

    var key: String? { goalSeconds.map { "\(runID.uuidString):\($0)" } }
}
