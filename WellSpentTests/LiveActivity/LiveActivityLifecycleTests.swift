import Foundation
import SwiftData
import WellSpentShared
import XCTest

@testable import WellSpent

@MainActor
final class LiveActivityLifecycleTests: XCTestCase {
    func testTimerRunProjectionCarriesRevisionAndFreezesCountedTimeWhilePaused() {
        let runID = UUID()
        let startedAt = Date(timeIntervalSince1970: 100)
        let requestedAt = Date(timeIntervalSince1970: 300)
        let running = LiveActivityProjection(
            sessionID: runID,
            startedAt: startedAt,
            projectName: "Client",
            showsProjectName: true,
            requestedAt: requestedAt,
            phase: .running,
            countedSeconds: 150,
            currentSegmentStartedAt: Date(timeIntervalSince1970: 250),
            revision: 4
        ).contentState
        XCTAssertEqual(running.phase, .running)
        XCTAssertEqual(running.countedSeconds, 100)
        XCTAssertEqual(running.revision, 4)
        XCTAssertEqual(running.elapsed(at: Date(timeIntervalSince1970: 350), legacyStartedAt: startedAt), 200)

        let paused = LiveActivityProjection(
            sessionID: runID,
            startedAt: startedAt,
            projectName: "Client",
            showsProjectName: true,
            requestedAt: requestedAt,
            phase: .paused,
            countedSeconds: 150,
            revision: 5
        ).contentState
        XCTAssertEqual(paused.phase, .paused)
        XCTAssertEqual(paused.countedSeconds, 150)
        XCTAssertNil(paused.currentSegmentStartedAt)
        XCTAssertEqual(paused.revision, 5)
        XCTAssertEqual(paused.elapsed(at: Date(timeIntervalSince1970: 999), legacyStartedAt: startedAt), 150)
    }

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
        fixture.lifecycle.failure = .reconcile
        let model = fixture.makeModel()

        await model.startOrSwitch(to: project.id)

        let active = try XCTUnwrap(model.activeSession)
        XCTAssertEqual(active.projectID, project.id)
        XCTAssertNil(active.endAt)
        XCTAssertEqual(fixture.lifecycle.calls, [.reconcile(active.id)])
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
        fixture.lifecycle.failure = .reconcile
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
        fixture.lifecycle.failure = .reconcile
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
        fixture.lifecycle.failure = .reconcile
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
        XCTAssertTrue(model.runs.isEmpty)
        XCTAssertTrue(model.requiresOnboardingAfterReset)
        XCTAssertFalse(model.sessionTags.contains { $0.name == "private" })
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerOriginRecord>()), 0)
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
    func testStopFromOlderRevisionCannotEndPausedRun() async throws {
        let fixture = try LiveActivityModelFixture()
        fixture.context.insert(ProjectRecord(id: fixture.firstProjectID, name: "Client"))
        fixture.context.insert(
            fixture.activeSession(
                id: fixture.oldSessionID, projectID: fixture.firstProjectID,
                startAt: fixture.now.addingTimeInterval(-600)))
        try fixture.context.save()
        let model = fixture.makeModel()
        try WellSpentStopHandoff.persist(
            sessionID: fixture.oldSessionID, endedAt: fixture.now,
            endTimeZoneID: "UTC", expectedRevision: 1, suiteName: fixture.handoffSuiteName)

        await model.pauseActiveTimer()
        let paused = try XCTUnwrap(model.activeRun)
        XCTAssertEqual(paused.revision, 2)
        await model.retryLiveActivityProjection()

        XCTAssertEqual(model.activeRun, paused)
        XCTAssertTrue(try WellSpentStopHandoff.pendingRequests(suiteName: fixture.handoffSuiteName).isEmpty)
        XCTAssertTrue(model.message?.contains("older timer state") == true)
        XCTAssertNil(model.completionRoute)
    }

    func testRepeatedOldRunStopCannotEndSwitchedRun() async throws {
        let fixture = try LiveActivityModelFixture()
        fixture.context.insert(ProjectRecord(id: fixture.firstProjectID, name: "First"))
        fixture.context.insert(ProjectRecord(id: fixture.secondProjectID, name: "Second"))
        fixture.context.insert(
            fixture.activeSession(
                id: fixture.oldSessionID, projectID: fixture.firstProjectID,
                startAt: fixture.now.addingTimeInterval(-600)))
        try fixture.context.save()
        let model = fixture.makeModel()
        await model.startOrSwitch(to: fixture.secondProjectID)
        let next = try XCTUnwrap(model.activeRun)
        for _ in 0..<3 {
            try WellSpentStopHandoff.persist(
                sessionID: fixture.oldSessionID, endedAt: fixture.now.addingTimeInterval(30),
                endTimeZoneID: "UTC", expectedRevision: 1, suiteName: fixture.handoffSuiteName)
            await model.retryLiveActivityProjection()
            XCTAssertEqual(model.activeRun, next)
            XCTAssertEqual(model.run(id: fixture.oldSessionID)?.endAt, fixture.now)
            XCTAssertEqual(fixture.lifecycle.desired.active?.sessionID, next.id)
        }
    }

    func testProjectionSuccessCannotHideUnappliedStopRecovery() async throws {
        let fixture = try LiveActivityModelFixture()
        fixture.context.insert(ProjectRecord(id: fixture.firstProjectID, name: "Client"))
        fixture.context.insert(
            fixture.activeSession(
                id: fixture.oldSessionID, projectID: fixture.firstProjectID,
                startAt: fixture.now.addingTimeInterval(-600)))
        try fixture.context.save()
        let model = fixture.makeModel()
        try WellSpentStopHandoff.persist(
            sessionID: fixture.oldSessionID, endedAt: fixture.now.addingTimeInterval(-700),
            endTimeZoneID: "UTC", expectedRevision: 1, suiteName: fixture.handoffSuiteName)

        await model.retryLiveActivityProjection()

        XCTAssertNotNil(model.activeRun)
        XCTAssertEqual(try WellSpentStopHandoff.pendingRequests(suiteName: fixture.handoffSuiteName).count, 1)
        XCTAssertTrue(model.liveActivityRecoveryMessage?.contains("safely queued") == true)
    }

    func testStopProjectsThePostSaveCountAndRevisionEvenWhenProjectionFails() async throws {
        let fixture = try LiveActivityModelFixture()
        fixture.context.insert(ProjectRecord(id: fixture.firstProjectID, name: "Client"))
        fixture.context.insert(
            fixture.activeSession(
                id: fixture.oldSessionID, projectID: fixture.firstProjectID,
                startAt: fixture.now.addingTimeInterval(-600)))
        try fixture.context.save()
        let model = fixture.makeModel()
        fixture.lifecycle.failure = .reconcile
        await model.stopActiveTimer()
        let final = try XCTUnwrap(fixture.lifecycle.desired.completed.first).contentState
        XCTAssertEqual(final.revision, model.run(id: fixture.oldSessionID)?.revision)
        XCTAssertEqual(final.countedSeconds, 600)
        XCTAssertEqual(final.endedAt, fixture.now)
        XCTAssertEqual(final.phase, .stopped)
        XCTAssertNil(model.activeRun)
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
            startupReconciliation: .noActiveRun,
            liveActivityLifecycle: lifecycle,
            stopHandoffSuiteName: handoffSuiteName,
            foregroundHandoffPollDelays: [],
            makeWatchConnectivity: DependencyFixtures.disconnectedWatch,
            showsProjectNameOnLockScreen: { false }
        )
    }

    func activeSession(id: UUID, projectID: UUID, startAt: Date) -> TimeSessionRecord {
        context.insert(
            TimerRunRecord(
                id: id,
                projectID: projectID,
                state: .running,
                startAt: startAt,
                startTimeZoneID: "UTC",
                originDeviceID: UUID(uuidString: "CCCCCCCC-CCCC-4CCC-8CCC-CCCCCCCCCCCC")!,
                revision: 1,
                createdAt: startAt,
                updatedAt: startAt,
                updatedTimeZoneID: "UTC"
            )
        )
        return TimeSessionRecord(
            id: id,
            projectID: projectID,
            source: .timer,
            timerRunID: id,
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
        case reconcile
    }

    enum Call: Equatable {
        case reconcile(UUID?)
    }

    var activitiesEnabled = true
    var failure: Failure?
    private(set) var calls: [Call] = []
    private(set) var desired = LiveActivityDesiredState(active: nil)

    func setDesiredState(_ state: LiveActivityDesiredState) {
        desired = state
    }

    func reconcile() async throws {
        calls.append(.reconcile(desired.active?.sessionID))
        if failure == .reconcile { throw LiveActivityLifecycleError.forcedTestFailure }
    }
}

private enum HandoffInjectedFailure: Error {
    case save
}
