import Foundation
import UserNotifications
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatch
@testable import WellSpentWatchStore

@MainActor
final class WatchGoalAlertTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 2_000_000_000)
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let otherProjectID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!

    func testNotificationPermissionFailureFixtureRequiresExplicitRetry() throws {
        let center = WatchGoalFixtureNotifications(denied: false, permissionFailsOnce: true)
        XCTAssertThrowsError(try center.requestAuthorization())
        XCTAssertEqual(center.authorization(), .notDetermined)
        XCTAssertNil(center.pendingGoal())
        XCTAssertTrue(try center.requestAuthorization())
        XCTAssertEqual(center.authorization(), .authorized)
        let denied = WatchGoalFixtureNotifications(denied: true)
        XCTAssertFalse(try denied.requestAuthorization())
        XCTAssertEqual(denied.authorization(), .denied)
    }

    func testNotificationSchedulingFailureFixtureDoesNotSaveBeforeRetry() throws {
        let center = WatchGoalFixtureNotifications(denied: false, schedulingFailsOnce: true)
        let plan = WatchGoalAlertPlan(
            runID: UUID(), goalSeconds: 900, deadline: epoch.addingTimeInterval(900),
            title: "Time goal reached", body: "Your billable time goal is complete.")
        XCTAssertThrowsError(try center.add(plan, now: epoch))
        XCTAssertNil(center.pendingGoal())
        try center.add(plan, now: epoch)
        XCTAssertEqual(center.pendingGoal(), plan)
        center.removeGoalAlerts()
        XCTAssertNil(center.pendingGoal())
    }

    func testOnlyExplicitEnableRequestsPermissionAndSubsequentChangesDoNotReprompt() async throws {
        let store = try makeStore()
        let center = GoalFakeCenter()
        let preferences = WatchGoalMemoryPreferences()
        let coordinator = makeCoordinator(center, preferences)
        coordinator.update(state: try store.state())
        coordinator.refreshAuthorization()
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.permissionRequests, 0)
        XCTAssertNil(center.pending)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.permissionRequests, 1)
        XCTAssertNotNil(center.pending)
        await coordinator.setEnabled(false)
        await coordinator.waitForReconciliation()
        XCTAssertNil(center.pending)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.permissionRequests, 1)
        XCTAssertNotNil(center.pending)
    }

    func testDeniedPermissionNeverBlocksTrackingOrReprompts() async throws {
        let store = try makeStore()
        let before = try store.state()
        let center = GoalFakeCenter()
        center.status = .denied
        let coordinator = makeCoordinator(center)
        coordinator.update(state: before)
        for _ in 0..<3 {
            await coordinator.setEnabled(true)
            coordinator.refreshAuthorization()
            await coordinator.waitForReconciliation()
        }
        XCTAssertEqual(center.permissionRequests, 0)
        XCTAssertNil(center.pending)
        XCTAssertTrue(coordinator.explanation.contains("Time goals still work"))
        XCTAssertEqual(try store.state(), before)
        _ = try WatchSystemCommandBoundary(now: { self.epoch.addingTimeInterval(30) })
            .perform(.init(action: .pause), store: store)
        XCTAssertEqual(try store.state().projection.activeRun?.state, .paused)
    }

    func testFirstPromptDenialAndRequestFailureHaveDistinctRecoverableStates() async throws {
        let center = GoalFakeCenter()
        center.grantsPermission = false
        let coordinator = makeCoordinator(center)
        coordinator.update(state: try makeStore().state())
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.permissionRequests, 1)
        XCTAssertEqual(coordinator.authorization, .denied)
        await coordinator.setEnabled(false)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.permissionRequests, 1)
        center.status = .notDetermined
        center.failPermission = true
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertTrue(coordinator.permissionRequestFailed)
        XCTAssertFalse(coordinator.explanation.contains("Notifications are off"))
        XCTAssertNil(center.pending)
    }

    func testSystemRequestIsOneShotMinimalAndUsesAbsoluteDurationAcrossDST() throws {
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: "2033-11-06T05:30:00Z"))
        let deadline = start.addingTimeInterval(3_600)
        let plan = WatchGoalAlertPlan(
            runID: UUID(), goalSeconds: 3_600, deadline: deadline,
            title: "Time goal reached", body: "Your billable time goal is complete.")
        let request = try XCTUnwrap(WatchGoalSystemNotifications.request(for: plan, now: start))
        let trigger = try XCTUnwrap(request.trigger as? UNTimeIntervalNotificationTrigger)
        XCTAssertEqual(trigger.timeInterval, 3_600)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(request.identifier, WatchGoalAlertPlan.identifier)
        XCTAssertEqual(Set(request.content.userInfo.keys.compactMap { $0 as? String }), ["run", "goal", "deadline"])
        XCTAssertNil(WatchGoalSystemNotifications.request(for: plan, now: deadline))
        XCTAssertNil(WatchGoalSystemNotifications.request(for: plan, now: deadline.addingTimeInterval(10)))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        XCTAssertEqual(calendar.component(.hour, from: start), calendar.component(.hour, from: deadline))
        XCTAssertEqual(deadline.timeIntervalSince(start), 3_600)
    }

    func testDeadlineExcludesEveryPauseAndReschedulesAfterGoalEditAndResume() async throws {
        let store = try makeStore(goal: 900)
        var time = epoch
        let center = GoalFakeCenter()
        center.status = .authorized
        let coordinator = WatchGoalAlertCoordinator(
            center: center, preferenceStore: WatchGoalMemoryPreferences(), now: { time }, haptic: {})
        let boundary = WatchSystemCommandBoundary(now: { time }, timeZoneID: { "America/New_York" })
        coordinator.update(state: try store.state())
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.pending?.deadline, epoch.addingTimeInterval(900))
        for cycle in 0..<3 {
            time = time.addingTimeInterval(100)
            _ = try boundary.perform(.init(action: .pause), store: store)
            coordinator.update(state: try store.state())
            await coordinator.waitForReconciliation()
            XCTAssertNil(center.pending)
            time = time.addingTimeInterval(200)
            _ = try boundary.perform(.init(action: .resume), store: store)
            coordinator.update(state: try store.state())
            await coordinator.waitForReconciliation()
            XCTAssertEqual(center.pending?.deadline, epoch.addingTimeInterval(900 + Double(cycle + 1) * 200))
        }
        let run = try XCTUnwrap(store.state().projection.activeRun)
        _ = try WatchTimerGoalBoundary(now: { time }, timeZoneID: { "Pacific/Auckland" })
            .setGoal(1_800, runID: run.id, store: store)
        coordinator.update(state: try store.state())
        await coordinator.waitForReconciliation()
        XCTAssertEqual(center.pending?.deadline, epoch.addingTimeInterval(2_400))
        XCTAssertEqual(center.pending?.goalSeconds, 1_800)
        XCTAssertTrue(try store.state().isPendingSync)
        time = time.addingTimeInterval(10)
        _ = try boundary.perform(.init(action: .end), store: store)
        coordinator.update(state: try store.state())
        await coordinator.waitForReconciliation()
        XCTAssertNil(center.pending)
    }

    func testRetryAndProcessRestartDoNotDuplicateOrMoveAnUnchangedAlert() async throws {
        let store = try makeStore()
        let center = GoalFakeCenter()
        center.status = .authorized
        let preferences = WatchGoalMemoryPreferences()
        let first = makeCoordinator(center, preferences)
        first.update(state: try store.state())
        await first.setEnabled(true)
        await first.waitForReconciliation()
        let scheduled = center.pending
        for _ in 0..<5 {
            first.update(state: try store.state())
            first.refreshAuthorization()
            await first.waitForReconciliation()
        }
        let restarted = makeCoordinator(center, preferences)
        restarted.update(state: try store.state())
        await restarted.waitForReconciliation()
        XCTAssertEqual(center.addCount, 1)
        XCTAssertEqual(center.pending, scheduled)
        XCTAssertEqual(center.permissionRequests, 0)
    }

    func testEndOrSwitchDuringInFlightAddCannotResurrectTheOldAlert() async throws {
        for action in [WatchSystemAction.end, .switchProject] {
            let store = try makeStore()
            let center = GoalFakeCenter()
            center.status = .authorized
            let coordinator = makeCoordinator(center)
            coordinator.update(state: try store.state())
            center.beforeAddCompletes = {
                _ = try! WatchSystemCommandBoundary(now: { self.epoch.addingTimeInterval(10) })
                    .perform(.init(action: action, projectID: self.otherProjectID), store: store)
                coordinator.update(state: try! store.state())
            }
            await coordinator.setEnabled(true)
            await coordinator.waitForReconciliation()
            XCTAssertNil(center.pending)
            XCTAssertNil(WatchGoalAlertPlan.make(state: try store.state()))
        }
    }

    func testScheduleFailureDoesNotRollbackTimeAndExplicitRetryRecovers() async throws {
        let store = try makeStore()
        let before = try store.state()
        let center = GoalFakeCenter()
        center.status = .authorized
        center.failAdd = true
        let coordinator = makeCoordinator(center)
        coordinator.update(state: before)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertTrue(coordinator.schedulingFailed)
        XCTAssertNil(center.pending)
        XCTAssertEqual(try store.state(), before)
        center.failAdd = false
        coordinator.refreshAuthorization()
        await coordinator.waitForReconciliation()
        XCTAssertFalse(coordinator.schedulingFailed)
        XCTAssertNotNil(center.pending)
        XCTAssertEqual(center.addCount, 2)
    }

    func testPrivacyOptOutReplacesNamedContentAndRemovesOldDeliveredAlert() async throws {
        let store = try makeStore()
        let state = try store.state()
        XCTAssertFalse(WatchGoalAlertPlan.make(state: state)!.body.contains("Client Launch"))
        let named = changingPrivacy(state, enabled: true)
        XCTAssertTrue(WatchGoalAlertPlan.make(state: named)!.body.contains("Client Launch"))
        let center = GoalFakeCenter()
        center.status = .authorized
        let coordinator = makeCoordinator(center)
        coordinator.update(state: named)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        center.delivered = center.pending
        coordinator.update(state: state)
        await coordinator.waitForReconciliation()
        XCTAssertFalse(center.pending!.body.contains("Client Launch"))
        XCTAssertEqual(center.pending?.title, "Time goal reached")
        XCTAssertNil(center.delivered)
    }

    func testEraseCancelsAndResetsWatchLocalPreferencesButFailedEraseDoesNot() async throws {
        let store = try makeStore()
        let center = GoalFakeCenter()
        center.status = .authorized
        let coordinator = makeCoordinator(center)
        coordinator.update(state: try store.state())
        coordinator.recordGoal(2_700)
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        store.setBeforeSaveForTesting { throw WatchStoreError.saveFailed }
        XCTAssertThrowsError(try store.eraseAll())
        coordinator.update(state: try store.state())
        await coordinator.waitForReconciliation()
        XCTAssertNotNil(center.pending)
        store.setBeforeSaveForTesting {}
        try store.eraseAll()
        coordinator.update(state: try store.state())
        await coordinator.waitForReconciliation()
        XCTAssertNil(center.pending)
        XCTAssertFalse(coordinator.preferences.alertsEnabled)
        XCTAssertTrue(coordinator.preferences.recentGoalSeconds.isEmpty)
    }

    func testOvertimeNeverSchedulesAnImmediateCatchUpNotification() async throws {
        let store = try makeStore(goal: 300)
        let center = GoalFakeCenter()
        center.status = .authorized
        let coordinator = WatchGoalAlertCoordinator(
            center: center, preferenceStore: WatchGoalMemoryPreferences(),
            now: { self.epoch.addingTimeInterval(301) }, haptic: {})
        coordinator.update(state: try store.state())
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertNil(center.pending)
        XCTAssertEqual(center.addCount, 0)
    }

    func testBlockedUnsupportedPausedOpenAndUnavailableNeverSchedule() async throws {
        for fixture in [WatchUITestFixture.conflict, .unsupported, .paused, .activeNoGoal, .setup] {
            let (store, _) = try fixture.makeRuntime()
            XCTAssertNil(WatchGoalAlertPlan.make(state: try store.state()))
        }
        XCTAssertNil(WatchGoalAlertPlan.make(state: nil))
    }

    func testForegroundHapticOnlyOnceForAVisibleThresholdCrossing() {
        let preferences = WatchGoalMemoryPreferences()
        let center = GoalFakeCenter()
        var haptics = 0
        let coordinator = WatchGoalAlertCoordinator(
            center: center, preferenceStore: preferences, haptic: { haptics += 1 })
        let runID = UUID()
        let under = WatchGoalProgress(runID: runID, goalSeconds: 900, reached: false, visible: true)
        let reached = WatchGoalProgress(runID: runID, goalSeconds: 900, reached: true, visible: true)
        coordinator.observe(under)
        coordinator.observe(reached)
        coordinator.observe(reached)
        coordinator.leaveForeground()
        coordinator.observe(reached)
        XCTAssertEqual(haptics, 1)
        let restarted = WatchGoalAlertCoordinator(
            center: center, preferenceStore: preferences, haptic: { haptics += 1 })
        restarted.observe(under)
        restarted.observe(reached)
        XCTAssertEqual(haptics, 1)
        let otherRun = UUID()
        restarted.observe(.init(runID: otherRun, goalSeconds: 900, reached: false, visible: false))
        restarted.observe(.init(runID: otherRun, goalSeconds: 900, reached: true, visible: true))
        XCTAssertEqual(haptics, 1)
    }

    func testSettingsFailureDoesNotRequestPermissionOrOptIn() async {
        let center = GoalFakeCenter()
        let coordinator = WatchGoalAlertCoordinator(
            center: center, preferenceStore: WatchGoalUnavailablePreferences(), haptic: {})
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertTrue(coordinator.settingsFailed)
        XCTAssertFalse(coordinator.preferences.alertsEnabled)
        XCTAssertEqual(center.permissionRequests, 0)
    }

    func testTurningAlertsOffCancelsImmediatelyEvenWhenSavingSettingsFails() async throws {
        let center = GoalFakeCenter()
        center.status = .authorized
        let storage = GoalFailingPreferences()
        let coordinator = WatchGoalAlertCoordinator(
            center: center, preferenceStore: storage, now: { self.epoch }, haptic: {})
        coordinator.update(state: try makeStore().state())
        await coordinator.setEnabled(true)
        await coordinator.waitForReconciliation()
        XCTAssertNotNil(center.pending)
        storage.failSaves = true
        await coordinator.setEnabled(false)
        XCTAssertNil(center.pending)
        await coordinator.waitForReconciliation()
        XCTAssertFalse(coordinator.preferences.alertsEnabled)
        XCTAssertTrue(coordinator.settingsFailed)
    }

    func testRecentGoalsAreBoundedDeduplicatedAndSettingsFileIsExcludedFromBackup() throws {
        var preferences = WatchGoalPreferences()
        for goal in [2_700, 3_300, 2_700, 5, 90_000, 5_400, 7_200] { preferences.recordGoal(goal) }
        XCTAssertEqual(preferences.recentGoalSeconds, [7_200, 5_400, 2_700])
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("preferences.json")
        let storage = try WatchGoalFilePreferences(url: url)
        try storage.save(preferences)
        XCTAssertEqual(try storage.load(), preferences)
        XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        XCTAssertEqual(try directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        preferences.recentGoalSeconds = [5, 2_700, 2_700, 4_500, 90_000]
        try storage.save(preferences)
        XCTAssertEqual(try storage.load().recentGoalSeconds, [2_700, 4_500])
    }

    func testGoalEditsAreDurableIdempotentAndRejectStaleRunsOrFailedSave() throws {
        let store = try makeStore()
        let initial = try store.state()
        let runID = try XCTUnwrap(initial.projection.activeRun?.id)
        let boundary = WatchTimerGoalBoundary(now: { self.epoch.addingTimeInterval(20) })
        _ = try boundary.setGoal(1_800, runID: runID, store: store)
        let saved = try store.state()
        XCTAssertEqual(saved.projection.activeRunSegments, initial.projection.activeRunSegments)
        XCTAssertEqual(saved.pendingMutationCount, initial.pendingMutationCount + 1)
        XCTAssertNil(try boundary.setGoal(1_800, runID: runID, store: store))
        XCTAssertThrowsError(try boundary.setGoal(0, runID: runID, store: store))
        XCTAssertThrowsError(try boundary.setGoal(300, runID: UUID(), store: store))
        store.setBeforeSaveForTesting { throw WatchStoreError.saveFailed }
        XCTAssertThrowsError(try boundary.setGoal(300, runID: runID, store: store))
        XCTAssertEqual(try store.state(), saved)
        store.setBeforeSaveForTesting {}
        _ = try boundary.setGoal(nil, runID: runID, store: store)
        XCTAssertNil(WatchGoalAlertPlan.make(state: try store.state()))
    }

    private func makeStore(goal: Int = 900) throws -> WellSpentWatchStore {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        _ = try store.performLocalCommand(
            .start(StartTimerAction(runID: UUID(), segmentID: UUID(), projectID: projectID, durationGoalSeconds: goal)),
            capturedAt: epoch, timeZoneID: "UTC")
        return store
    }

    private func makeCoordinator(
        _ center: GoalFakeCenter, _ preferences: WatchGoalMemoryPreferences = WatchGoalMemoryPreferences()
    ) -> WatchGoalAlertCoordinator {
        WatchGoalAlertCoordinator(center: center, preferenceStore: preferences, now: { self.epoch }, haptic: {})
    }

    private func changingPrivacy(_ state: WatchStoreState, enabled: Bool) -> WatchStoreState {
        var projection = state.projection
        projection.showProjectNamesOnSystemSurfaces = enabled
        return WatchStoreState(
            originDeviceID: state.originDeviceID, nextOriginSequence: state.nextOriginSequence,
            protocolVersion: state.protocolVersion, schemaVersion: state.schemaVersion, projection: projection,
            pendingMutationCount: state.pendingMutationCount, quarantinedMutationCount: state.quarantinedMutationCount,
            pendingSnapshotReceiptCount: state.pendingSnapshotReceiptCount,
            blockingReasonCode: state.blockingReasonCode, recentProjectIDs: state.recentProjectIDs)
    }
}

@MainActor
private final class GoalFailingPreferences: WatchGoalPreferenceStore {
    private var value = WatchGoalPreferences()
    var failSaves = false
    func load() -> WatchGoalPreferences { value }
    func save(_ preferences: WatchGoalPreferences) throws {
        if failSaves { throw WatchStoreError.saveFailed }
        value = preferences
    }
}

@MainActor
private final class GoalFakeCenter: WatchGoalNotificationCenter {
    var status = WatchGoalAuthorization.notDetermined
    var permissionRequests = 0
    var addCount = 0
    var failAdd = false
    var failPermission = false
    var grantsPermission = true
    var pending: WatchGoalAlertPlan?
    var delivered: WatchGoalAlertPlan?
    var beforeAddCompletes: (() -> Void)?

    func authorization() async -> WatchGoalAuthorization { status }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if failPermission { throw WatchStoreError.saveFailed }
        status = grantsPermission ? .authorized : .denied
        return grantsPermission
    }
    func pendingGoal() async -> WatchGoalAlertPlan? { pending }
    func removeGoalAlerts() {
        pending = nil
        delivered = nil
    }
    func add(_ plan: WatchGoalAlertPlan, now: Date) async throws {
        addCount += 1
        await Task.yield()
        if failAdd { throw WatchStoreError.saveFailed }
        let callback = beforeAddCompletes
        beforeAddCompletes = nil
        callback?()
        pending = plan
    }
}
