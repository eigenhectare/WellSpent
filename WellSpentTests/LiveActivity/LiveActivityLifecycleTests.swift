import Foundation
import SwiftData
import WellSpentShared
import XCTest

@testable import WellSpent

@MainActor
final class LiveActivityLifecycleTests: XCTestCase {
    func testReconciliationPlanEndsStaleAndDuplicateActivitiesButKeepsOneExactMatch() {
        let active = LiveActivityProjection(
            sessionID: UUID(uuidString: "AAAAAAAA-AAAA-4AAA-BAAA-AAAAAAAAAAAA")!,
            startedAt: Date(timeIntervalSince1970: 200),
            projectName: "Client",
            showsProjectName: false,
            requestedAt: Date(timeIntervalSince1970: 300)
        )
        let existing = [
            ExistingLiveActivityProjection(
                systemID: "stale-session",
                sessionID: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-BBBB-BBBBBBBBBBBB")!,
                startedAt: active.startedAt
            ),
            ExistingLiveActivityProjection(
                systemID: "duplicate-z",
                sessionID: active.sessionID,
                startedAt: active.startedAt
            ),
            ExistingLiveActivityProjection(
                systemID: "duplicate-a",
                sessionID: active.sessionID,
                startedAt: active.startedAt
            ),
            ExistingLiveActivityProjection(
                systemID: "stale-start",
                sessionID: active.sessionID,
                startedAt: active.startedAt.addingTimeInterval(-1)
            ),
        ]

        let plan = LiveActivityReconciliationPlan.make(active: active, existing: existing)

        XCTAssertEqual(plan.updateSystemID, "duplicate-a")
        XCTAssertEqual(
            plan.endSystemIDs,
            ["duplicate-z", "stale-session", "stale-start"]
        )
        XCTAssertFalse(plan.requestsActivity)
    }

    func testReconciliationPlanRecreatesMissingProjectionAndEndsAllWhenTimerStops() {
        let active = LiveActivityProjection(
            sessionID: UUID(),
            startedAt: Date(timeIntervalSince1970: 200),
            projectName: "Client",
            showsProjectName: false,
            requestedAt: Date(timeIntervalSince1970: 300)
        )
        let stale = ExistingLiveActivityProjection(
            systemID: "stale",
            sessionID: UUID(),
            startedAt: active.startedAt
        )

        let recreation = LiveActivityReconciliationPlan.make(active: active, existing: [stale])
        XCTAssertEqual(recreation.endSystemIDs, ["stale"])
        XCTAssertNil(recreation.updateSystemID)
        XCTAssertTrue(recreation.requestsActivity)

        let stopped = LiveActivityReconciliationPlan.make(active: nil, existing: [stale])
        XCTAssertEqual(stopped.endSystemIDs, ["stale"])
        XCTAssertNil(stopped.updateSystemID)
        XCTAssertFalse(stopped.requestsActivity)
    }

    func testStartProjectionFailureNeverRollsBackThePersistedTimer() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Confidential Client")
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.lifecycle.failure = .start
        let model = fixture.makeModel()

        await model.startOrSwitch(to: project.id)

        let active = try XCTUnwrap(model.activeSession)
        XCTAssertEqual(active.projectID, project.id)
        XCTAssertNil(active.endAt)
        XCTAssertEqual(fixture.lifecycle.calls, [.start(active.id)])
        XCTAssertNotNil(model.liveActivityRecoveryMessage)
    }

    func testSwitchProjectionFailureLeavesTheAtomicNewTimerPersisted() async throws {
        let fixture = try LiveActivityModelFixture()
        let first = ProjectRecord(id: fixture.firstProjectID, name: "First")
        let second = ProjectRecord(id: fixture.secondProjectID, name: "Second")
        let oldSession = fixture.activeSession(
            id: fixture.oldSessionID,
            projectID: first.id,
            startAt: fixture.now.addingTimeInterval(-600)
        )
        fixture.context.insert(first)
        fixture.context.insert(second)
        fixture.context.insert(oldSession)
        try fixture.context.save()
        fixture.lifecycle.failure = .switchActivity
        let model = fixture.makeModel()

        await model.startOrSwitch(to: second.id)

        XCTAssertEqual(model.activeSession?.projectID, second.id)
        XCTAssertEqual(model.completionRoute?.sessionID, oldSession.id)
        XCTAssertEqual(fixture.lifecycle.calls.count, 1)
        let records = try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(records.count, 2)
        XCTAssertEqual(records.first { $0.id == oldSession.id }?.endAt, fixture.now)
        XCTAssertNotNil(model.liveActivityRecoveryMessage)
    }

    func testStopProjectionFailureLeavesTheExactCompletedSessionPersisted() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Client")
        let session = fixture.activeSession(
            id: fixture.oldSessionID,
            projectID: project.id,
            startAt: fixture.now.addingTimeInterval(-600)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()
        fixture.lifecycle.failure = .stop
        let model = fixture.makeModel()

        await model.stopActiveTimer()

        XCTAssertNil(model.activeSession)
        XCTAssertEqual(model.session(id: session.id)?.endAt, fixture.now)
        XCTAssertEqual(model.completionRoute?.sessionID, session.id)
        XCTAssertNotNil(model.liveActivityRecoveryMessage)
    }

    func testForegroundAppliesAndAcknowledgesDurableIntentStopBeforeRouting() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Client")
        let session = fixture.activeSession(
            id: fixture.oldSessionID,
            projectID: project.id,
            startAt: fixture.now.addingTimeInterval(-600)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()
        let capturedEnd = fixture.now.addingTimeInterval(-10)
        try WellSpentStopHandoff.persist(
            sessionID: session.id,
            endedAt: capturedEnd,
            endTimeZoneID: "America/New_York",
            suiteName: fixture.handoffSuiteName
        )
        let model = fixture.makeModel()

        await model.applicationBecameActive()

        XCTAssertEqual(model.session(id: session.id)?.endAt, capturedEnd)
        XCTAssertEqual(model.session(id: session.id)?.endTimeZoneID, "America/New_York")
        XCTAssertEqual(model.completionRoute?.sessionID, session.id)
        XCTAssertTrue(
            try WellSpentStopHandoff.pendingRequests(
                suiteName: fixture.handoffSuiteName
            ).isEmpty
        )
        XCTAssertEqual(fixture.lifecycle.calls.last, .reconcile(nil))
    }

    func testFailedAuthoritativeStopLeavesHandoffQueuedUntilSuccessfulRetry() throws {
        let fixture = try LiveActivityModelFixture()
        let request = try WellSpentStopHandoff.persist(
            sessionID: fixture.oldSessionID,
            endedAt: fixture.now,
            endTimeZoneID: "UTC",
            suiteName: fixture.handoffSuiteName
        )
        let reconciler = LiveActivityStopHandoffReconciler(
            suiteName: fixture.handoffSuiteName
        )

        let failed = try reconciler.applyPending { _ in
            throw HandoffInjectedFailure.save
        }
        XCTAssertEqual(failed.failedSessionIDs, [request.sessionID])
        XCTAssertEqual(
            try WellSpentStopHandoff.pendingRequests(suiteName: fixture.handoffSuiteName),
            [request]
        )

        let stoppedSnapshot = TimeSessionSnapshot(
            id: request.sessionID,
            projectID: fixture.firstProjectID,
            source: .timer,
            startAt: request.endedAt.addingTimeInterval(-60),
            endAt: request.endedAt,
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            createdAt: request.endedAt.addingTimeInterval(-60),
            updatedAt: request.endedAt
        )
        let retried = try reconciler.applyPending { _ in
            TimerStopResult(session: stoppedSnapshot, disposition: .stopped)
        }

        XCTAssertEqual(retried.appliedStops.map(\.session.id), [request.sessionID])
        XCTAssertTrue(
            try WellSpentStopHandoff.pendingRequests(
                suiteName: fixture.handoffSuiteName
            ).isEmpty
        )
    }

    func testForegroundReconcilesAContinuingTimerAndFlagsEightHourState() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Client")
        let session = fixture.activeSession(
            id: fixture.oldSessionID,
            projectID: project.id,
            startAt: fixture.now.addingTimeInterval(-9 * 3_600)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()
        let model = fixture.makeModel()

        await model.applicationBecameActive()

        XCTAssertTrue(model.isLongRunningSession)
        XCTAssertEqual(fixture.lifecycle.calls.last, .reconcile(session.id))
    }

    func testRetryClearsProjectionRecoveryAfterTheDatabaseAlreadySucceeded() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Client")
        fixture.context.insert(project)
        try fixture.context.save()
        fixture.lifecycle.failure = .start
        let model = fixture.makeModel()
        await model.startOrSwitch(to: project.id)
        XCTAssertNotNil(model.liveActivityRecoveryMessage)

        fixture.lifecycle.failure = nil
        await model.retryLiveActivityProjection()

        XCTAssertNotNil(model.activeSession)
        XCTAssertNil(model.liveActivityRecoveryMessage)
        XCTAssertEqual(fixture.lifecycle.calls.last, .reconcile(model.activeSession?.id))
    }

    func testDeleteAllLocalDataClearsRecordsPreferencesAndHandoffs() async throws {
        let fixture = try LiveActivityModelFixture()
        let project = ProjectRecord(id: fixture.firstProjectID, name: "Confidential Client")
        let session = fixture.activeSession(
            id: fixture.oldSessionID,
            projectID: project.id,
            startAt: fixture.now.addingTimeInterval(-600)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()
        try WellSpentStopHandoff.persist(
            sessionID: session.id,
            endedAt: fixture.now,
            endTimeZoneID: "UTC",
            suiteName: fixture.handoffSuiteName
        )
        UserDefaults.standard.set(true, forKey: AppPreferenceKeys.completedOnboarding)
        UserDefaults.standard.set(
            true,
            forKey: AppPreferenceKeys.showProjectNamesOnLockScreen
        )
        defer {
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.completedOnboarding)
            UserDefaults.standard.removeObject(
                forKey: AppPreferenceKeys.showProjectNamesOnLockScreen
            )
        }
        let model = fixture.makeModel()
        XCTAssertTrue(model.addSessionTag(name: "private"))

        let didDelete = await model.deleteAllLocalData()

        XCTAssertTrue(didDelete)

        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertTrue(model.sessions.isEmpty)
        XCTAssertFalse(model.sessionTags.contains { $0.name == "private" })
        XCTAssertFalse(UserDefaults.standard.bool(forKey: AppPreferenceKeys.completedOnboarding))
        XCTAssertFalse(
            UserDefaults.standard.bool(forKey: AppPreferenceKeys.showProjectNamesOnLockScreen)
        )
        XCTAssertTrue(
            try WellSpentStopHandoff.pendingRequests(
                suiteName: fixture.handoffSuiteName
            ).isEmpty
        )
        XCTAssertEqual(fixture.lifecycle.calls.last, .reconcile(nil))
    }
}

@MainActor
private final class LiveActivityModelFixture {
    let now = Date(timeIntervalSince1970: 1_900_000_000)
    let firstProjectID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    let secondProjectID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    let oldSessionID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-BAAA-AAAAAAAAAAAA")!
    let handoffSuiteName = "WellSpentLiveActivityTests.\(UUID().uuidString)"
    let container: ModelContainer
    let context: ModelContext
    let lifecycle = FakeLiveActivityLifecycle()

    init() throws {
        container = try WellSpentPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        try? WellSpentStopHandoff.clear(suiteName: handoffSuiteName)
    }

    deinit {
        try? WellSpentStopHandoff.clear(suiteName: handoffSuiteName)
    }

    func makeModel() -> WellSpentAppModel {
        WellSpentAppModel(
            modelContainer: container,
            dependencies: DependencyFixtures.fixed(
                now: now,
                uuid: UUID(uuidString: "BBBBBBBB-BBBB-4BBB-BBBB-BBBBBBBBBBBB")!
            ),
            startupReconciliation: .noActiveSession,
            liveActivityLifecycle: lifecycle,
            stopHandoffSuiteName: handoffSuiteName,
            foregroundHandoffPollDelays: [],
            showsProjectNameOnLockScreen: { false }
        )
    }

    func activeSession(id: UUID, projectID: UUID, startAt: Date) -> TimeSessionRecord {
        TimeSessionRecord(
            id: id,
            projectID: projectID,
            source: .timer,
            startAt: startAt,
            startTimeZoneID: "UTC",
            createdAt: startAt,
            updatedAt: startAt
        )
    }
}

@MainActor
private final class FakeLiveActivityLifecycle: LiveActivityLifecycle {
    enum Failure {
        case start
        case switchActivity
        case stop
        case reconcile
    }

    enum Call: Equatable {
        case start(UUID)
        case switchActivity(UUID, UUID)
        case stop(UUID)
        case reconcile(UUID?)
    }

    var activitiesEnabled = true
    var failure: Failure?
    private(set) var calls: [Call] = []

    func start(_ projection: LiveActivityProjection) async throws {
        calls.append(.start(projection.sessionID))
        if failure == .start { throw LiveActivityLifecycleError.forcedTestFailure }
    }

    func switchActivity(
        from previous: LiveActivityProjection,
        to active: LiveActivityProjection
    ) async throws {
        calls.append(.switchActivity(previous.sessionID, active.sessionID))
        if failure == .switchActivity { throw LiveActivityLifecycleError.forcedTestFailure }
    }

    func stop(_ projection: LiveActivityProjection, endedAt: Date) async throws {
        calls.append(.stop(projection.sessionID))
        if failure == .stop { throw LiveActivityLifecycleError.forcedTestFailure }
    }

    func reconcile(with active: LiveActivityProjection?) async throws {
        calls.append(.reconcile(active?.sessionID))
        if failure == .reconcile { throw LiveActivityLifecycleError.forcedTestFailure }
    }
}

private enum HandoffInjectedFailure: Error {
    case save
}
