import Combine
import Foundation
import WatchKit
import WellSpentWatchStore

@MainActor
final class WatchGoalAlertCoordinator: ObservableObject {
    @Published private(set) var preferences: WatchGoalPreferences
    @Published private(set) var authorization = WatchGoalAuthorization.notDetermined
    @Published private(set) var isRequestingPermission = false
    @Published private(set) var schedulingFailed = false
    @Published private(set) var settingsFailed = false
    @Published private(set) var permissionRequestFailed = false

    private let center: any WatchGoalNotificationCenter
    private let preferenceStore: any WatchGoalPreferenceStore
    private let now: () -> Date
    private let haptic: () -> Void
    private var desiredPlan: WatchGoalAlertPlan?
    private var revision: UInt64 = 0
    private var worker: Task<Void, Never>?
    private var observedProgress: WatchGoalProgress?

    init(
        center: any WatchGoalNotificationCenter,
        preferenceStore: any WatchGoalPreferenceStore,
        now: @escaping () -> Date = Date.init,
        haptic: @escaping () -> Void = { WKInterfaceDevice.current().play(.success) }
    ) {
        self.center = center
        self.preferenceStore = preferenceStore
        self.now = now
        self.haptic = haptic
        do {
            preferences = try preferenceStore.load()
        } catch {
            preferences = WatchGoalPreferences()
            settingsFailed = true
        }
    }

    var explanation: String {
        if settingsFailed { return String(localized: "Couldn’t save alert settings. Time tracking still works.") }
        if !preferences.alertsEnabled { return String(localized: "Optional notification when a time goal is reached.") }
        if permissionRequestFailed {
            return String(
                localized: "Couldn’t request permission. Turn alerts off and on to try again. Time goals still work.")
        }
        if schedulingFailed {
            return String(localized: "Couldn’t schedule this alert. Time tracking still works. Try again.")
        }
        switch authorization {
        case .authorized:
            return String(
                localized:
                    "Alerts follow counted time, not pauses. Delivery depends on your notification and Focus settings.")
        case .denied:
            return
                String(
                    localized:
                        "Notifications are off. Enable WellSpent notifications in your Watch notification settings. Time goals still work."
                )
        case .notDetermined:
            return String(
                localized: "Permission is needed for alerts. Turn alerts off and on to ask. Time goals still work.")
        }
    }

    /// This is the only path that asks the OS for permission, and is called only
    /// by the user's alert toggle. Launch, resume, and scheduling never prompt.
    func setEnabled(_ enabled: Bool) async {
        guard !isRequestingPermission else { return }
        permissionRequestFailed = false
        var next = preferences
        next.alertsEnabled = enabled
        let saved = save(next)
        if !enabled {
            // Turning alerts off takes effect immediately even if persistence
            // fails. The UI still reports that settings could not be saved.
            if !saved { preferences = next }
            center.removeGoalAlerts()
            reconcile()
            return
        }
        guard saved else { return }
        reconcile()
        isRequestingPermission = true
        defer { isRequestingPermission = false }
        let status = await center.authorization()
        if status == .notDetermined {
            do {
                _ = try await center.requestAuthorization()
            } catch {
                permissionRequestFailed = true
            }
        }
        reconcile()
    }

    func update(state: WatchStoreState?) {
        if let originID = state?.originDeviceID, preferences.storeOriginID != originID {
            var next = preferences.storeOriginID == nil ? preferences : WatchGoalPreferences()
            next.storeOriginID = originID
            if !save(next) {
                // A fresh store/erase must never inherit an old alert opt-in,
                // even if the separate preferences file cannot be written.
                preferences = WatchGoalPreferences()
            }
            observedProgress = nil
        }
        let next = WatchGoalAlertPlan.make(state: state)
        if next != desiredPlan {
            // Cancel immediately at a persisted state boundary. The serial worker
            // also handles an older add() that was already in flight.
            if desiredPlan != nil || next == nil { center.removeGoalAlerts() }
            desiredPlan = next
        }
        reconcile()
    }

    func refreshAuthorization() { reconcile() }

    func recordGoal(_ seconds: Int?) {
        var next = preferences
        next.recordGoal(seconds)
        if next != preferences { _ = save(next) }
    }

    func observe(_ progress: WatchGoalProgress) {
        center.setForegroundGoalVisible(progress.visible)
        defer { observedProgress = progress }
        guard progress.visible, let key = progress.key else { return }
        guard progress.reached else { return }
        let crossedWhileVisible =
            observedProgress?.key == key
            && observedProgress?.visible == true && observedProgress?.reached == false
        guard preferences.acknowledgedGoal != key else { return }
        var next = preferences
        next.acknowledgedGoal = key
        // Save before feedback so reopening an already-reached goal is silent.
        guard save(next), crossedWhileVisible else { return }
        haptic()
    }

    func leaveForeground() {
        observedProgress = nil
        center.setForegroundGoalVisible(false)
    }

    /// Used by tests and by finite background work; never starts a timer loop.
    func waitForReconciliation() async {
        while let worker { await worker.value }
    }

    private func save(_ next: WatchGoalPreferences) -> Bool {
        do {
            try preferenceStore.save(next)
            preferences = next
            settingsFailed = false
            return true
        } catch {
            settingsFailed = true
            return false
        }
    }

    private func reconcile() {
        revision &+= 1
        guard worker == nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await drain()
        }
    }

    private func drain() async {
        while true {
            let attempt = revision
            let status = await center.authorization()
            guard attempt == revision else { continue }
            authorization = status
            let plan =
                preferences.alertsEnabled && status == .authorized
                ? desiredPlan.flatMap { $0.deadline > now() ? $0 : nil } : nil
            let pending = await center.pendingGoal()
            guard attempt == revision else { continue }
            schedulingFailed = false
            if plan == nil || pending != plan {
                center.removeGoalAlerts()
                if let plan {
                    do {
                        try await center.add(plan, now: now())
                    } catch {
                        schedulingFailed = true
                    }
                }
            }
            guard attempt == revision else { continue }
            worker = nil
            return
        }
    }
}
