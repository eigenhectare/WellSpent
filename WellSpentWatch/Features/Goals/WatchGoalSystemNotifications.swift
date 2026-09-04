import Foundation
import UserNotifications

@MainActor
final class WatchGoalSystemNotifications: NSObject, WatchGoalNotificationCenter, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private var foregroundGoalVisible = false

    override init() {
        center = .current()
        super.init()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: "wellspent.goal", actions: [], intentIdentifiers: [], options: [])
        ])
    }

    func authorization() async -> WatchGoalAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized, .provisional, .ephemeral:
            return settings.alertSetting == .disabled ? .denied : .authorized
        @unknown default: return .denied
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func pendingGoal() async -> WatchGoalAlertPlan? {
        guard
            let request = await center.pendingNotificationRequests().first(where: {
                $0.identifier == WatchGoalAlertPlan.identifier
            }),
            let runString = request.content.userInfo["run"] as? String,
            let runID = UUID(uuidString: runString),
            let goal = request.content.userInfo["goal"] as? Int,
            let deadline = request.content.userInfo["deadline"] as? Double
        else { return nil }
        return WatchGoalAlertPlan(
            runID: runID, goalSeconds: goal, deadline: Date(timeIntervalSince1970: deadline),
            title: request.content.title, body: request.content.body)
    }

    func removeGoalAlerts() {
        center.removePendingNotificationRequests(withIdentifiers: [WatchGoalAlertPlan.identifier])
        center.removeDeliveredNotifications(withIdentifiers: [WatchGoalAlertPlan.identifier])
    }

    func add(_ plan: WatchGoalAlertPlan, now: Date) async throws {
        guard let request = Self.request(for: plan, now: now) else { return }
        try await center.add(request)
    }

    static func request(for plan: WatchGoalAlertPlan, now: Date) -> UNNotificationRequest? {
        let interval = plan.deadline.timeIntervalSince(now)
        guard interval > 0 else { return nil }
        let content = UNMutableNotificationContent()
        content.title = plan.title
        content.body = plan.body
        content.sound = .default
        content.categoryIdentifier = "wellspent.goal"
        content.userInfo = [
            "run": plan.runID.uuidString, "goal": plan.goalSeconds,
            "deadline": plan.deadline.timeIntervalSince1970,
        ]
        return UNNotificationRequest(
            identifier: WatchGoalAlertPlan.identifier, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false))
    }

    func setForegroundGoalVisible(_ visible: Bool) { foregroundGoalVisible = visible }

    // The visible goal supplies progress and one threshold haptic. Elsewhere
    // (including controls or a dimmed display), allow normal system delivery.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await MainActor.run { foregroundGoalVisible ? [] : [.banner, .sound] }
    }
}

#if DEBUG
    @MainActor
    final class WatchGoalFixtureNotifications: WatchGoalNotificationCenter {
        private var status: WatchGoalAuthorization
        private var pending: WatchGoalAlertPlan?
        private var permissionFailureRemaining: Bool
        private var schedulingFailureRemaining: Bool

        init(denied: Bool, permissionFailsOnce: Bool = false, schedulingFailsOnce: Bool = false) {
            status = denied ? .denied : .notDetermined
            permissionFailureRemaining = permissionFailsOnce
            schedulingFailureRemaining = schedulingFailsOnce
        }

        func authorization() -> WatchGoalAuthorization { status }
        func requestAuthorization() throws -> Bool {
            if permissionFailureRemaining {
                permissionFailureRemaining = false
                throw CocoaError(.fileReadNoPermission)
            }
            if status == .notDetermined { status = .authorized }
            return status == .authorized
        }
        func pendingGoal() -> WatchGoalAlertPlan? { pending }
        func removeGoalAlerts() { pending = nil }
        func add(_ plan: WatchGoalAlertPlan, now: Date) throws {
            if schedulingFailureRemaining {
                schedulingFailureRemaining = false
                throw CocoaError(.fileWriteNoPermission)
            }
            pending = plan
        }
    }
#endif
