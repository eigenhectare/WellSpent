import Foundation
import WellSpentShared
import XCTest

@testable import WellSpent

@MainActor
final class LiveActivitySerializationTests: XCTestCase {
    func testSwitchDuringSuspendedCleanupNeverRequestsSupersededRun() async throws {
        let driver = SuspensibleActivityDriver()
        driver.activities = [existing("old", projection: projection())]
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        let first = projection()
        let latest = projection()
        let entered = expectation(description: "cleanup entered")
        let gate = ActivityTestGate()
        driver.onEnd = {
            entered.fulfill()
            await gate.wait()
        }
        lifecycle.setDesiredState(.init(active: first))
        let task = Task { try await lifecycle.reconcile() }
        await fulfillment(of: [entered], timeout: 2)

        // Publication alone must invalidate old work, before another drain task
        // has a chance to run.
        lifecycle.setDesiredState(.init(active: latest))
        gate.resume()
        try await task.value

        XCTAssertEqual(driver.requests.map(\.sessionID), [latest.sessionID])
        XCTAssertEqual(driver.maximumInFlight, 1)
        XCTAssertFalse(driver.requests.contains(first))
    }

    func testConcurrentReconcileSerializesRevisionsAndDrainsNewestPrivacyState() async throws {
        let driver = SuspensibleActivityDriver()
        let first = projection(revision: 1, name: true)
        let next = projection(id: first.sessionID, revision: 2)
        driver.activities = [existing("current", projection: first)]
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        let entered = expectation(description: "update entered")
        let gate = ActivityTestGate()
        driver.onUpdate = {
            driver.onUpdate = nil
            entered.fulfill()
            await gate.wait()
        }
        lifecycle.setDesiredState(.init(active: first))
        let task = Task { try await lifecycle.reconcile() }
        await fulfillment(of: [entered], timeout: 2)
        lifecycle.setDesiredState(.init(active: next))
        let other = Task { try await lifecycle.reconcile() }
        gate.resume()
        try await task.value
        try await other.value

        XCTAssertEqual(driver.updates.last?.revision, 2)
        XCTAssertNil(driver.updates.last?.contentState.projectName)
        XCTAssertEqual(driver.maximumInFlight, 1)
        XCTAssertTrue(driver.requests.isEmpty)
    }

    func testEraseWhileCleanupSuspendedCannotResurrectTimer() async throws {
        let driver = SuspensibleActivityDriver()
        driver.activities = [existing("old", projection: projection())]
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        let entered = expectation(description: "cleanup entered")
        let gate = ActivityTestGate()
        driver.onEnd = {
            entered.fulfill()
            await gate.wait()
        }
        lifecycle.setDesiredState(.init(active: projection()))
        let task = Task { try await lifecycle.reconcile() }
        await fulfillment(of: [entered], timeout: 2)
        lifecycle.setDesiredState(.init(active: nil))
        gate.resume()
        try await task.value
        XCTAssertTrue(driver.requests.isEmpty)
        XCTAssertTrue(driver.activities.isEmpty)
    }

    func testWatchReceiptWhileBackgroundedDefersOnlyCreationThenRecovers() async throws {
        let driver = SuspensibleActivityDriver()
        let run = projection(revision: 4)
        driver.canRequestActivity = false
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        lifecycle.setDesiredState(.init(active: run))
        do {
            try await lifecycle.reconcile()
            XCTFail("Background creation must defer")
        } catch {
            XCTAssertEqual(error as? LiveActivityLifecycleError, .foregroundRequired)
        }
        XCTAssertTrue(driver.requests.isEmpty)
        driver.canRequestActivity = true
        try await lifecycle.reconcile()
        XCTAssertEqual(driver.requests, [run])

        driver.canRequestActivity = false
        let paused = projection(id: run.sessionID, phase: .paused, revision: 5)
        lifecycle.setDesiredState(.init(active: paused))
        try await lifecycle.reconcile()
        XCTAssertEqual(driver.updates.last, paused)
        XCTAssertEqual(driver.requests.count, 1)
    }

    func testFinalCardUsesPersistedRevisionBoundaryAndCountedSegments() async throws {
        let driver = SuspensibleActivityDriver()
        let run = projection()
        driver.activities = [existing("current", projection: run)]
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        let finished = projection(id: run.sessionID, phase: .ended, revision: 8)
        lifecycle.setDesiredState(.init(active: nil, completed: [finished]))
        try await lifecycle.reconcile()
        let state = try XCTUnwrap(driver.finalStates.first)
        XCTAssertEqual(state.phase, .stopped)
        XCTAssertEqual(state.revision, 8)
        XCTAssertEqual(state.countedSeconds, 150)
        XCTAssertEqual(state.endedAt, Date(timeIntervalSince1970: 300))
        XCTAssertNil(state.currentSegmentStartedAt)
        XCTAssertFalse(state.canStop)
    }

    func testUnavailableCanonicalReadInvalidatesWorkWithoutDiscardingCard() async throws {
        let driver = SuspensibleActivityDriver()
        driver.activities = [existing("current", projection: projection())]
        let lifecycle = ActivityKitLiveActivityLifecycle(driver: driver)
        lifecycle.setDesiredState(.init(active: nil, isCanonicalStateAvailable: false))
        do {
            try await lifecycle.reconcile()
            XCTFail("Unknown state is not an empty database")
        } catch {
            XCTAssertEqual(error as? LiveActivityLifecycleError, .canonicalStateUnavailable)
        }
        XCTAssertEqual(driver.activities.count, 1)
        XCTAssertTrue(driver.requests.isEmpty)
    }

    func testConflictFreezesCountHidesNamesAndDisablesStop() throws {
        let state = LiveActivityProjection(
            sessionID: UUID(), startedAt: Date(timeIntervalSince1970: 100),
            projectName: "Private client", showsProjectName: true,
            requestedAt: Date(timeIntervalSince1970: 300), countedSeconds: 150,
            currentSegmentStartedAt: Date(timeIntervalSince1970: 250),
            revision: 4, requiresReview: true, watchConfirmationPending: true
        ).contentState
        XCTAssertEqual(state.elapsed(at: .distantFuture, legacyStartedAt: .distantPast), 150)
        XCTAssertFalse(state.canStop)
        XCTAssertNil(state.projectName)
        XCTAssertEqual(state.statusText, "Review required")
        XCTAssertEqual(state.syncStatusText, "Review on iPhone")
    }

    func testPrivacyPayloadAndLegacyDecoding() throws {
        let hidden = projection().contentState
        XCTAssertNil(hidden.projectName)
        let encoded = try JSONEncoder().encode(hidden)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("Private client"))
        let legacy = Data(#"{"phase":"running","showsProjectName":false}"#.utf8)
        let decoded = try JSONDecoder().decode(WellSpentActivityAttributes.ContentState.self, from: legacy)
        XCTAssertNil(decoded.revision)
        XCTAssertTrue(decoded.canStop)
        XCTAssertNil(decoded.requiresReview)
    }

    func testElapsedAnchorAndDeepLinksFollowRunState() {
        let active = projection()
        let running = active.contentState
        XCTAssertEqual(running.timerAnchor(legacyStartedAt: active.startedAt), Date(timeIntervalSince1970: 150))
        XCTAssertEqual(running.destinationURL(runID: active.sessionID), WellSpentDeepLink.trackerURL)
        let stopped = projection(id: active.sessionID, phase: .ended).contentState
        XCTAssertNil(stopped.timerAnchor(legacyStartedAt: active.startedAt))
        XCTAssertEqual(
            stopped.destinationURL(runID: active.sessionID), WellSpentDeepLink.completionURL(for: active.sessionID))
        let paused = projection(phase: .paused).contentState
        XCTAssertNil(paused.timerAnchor(legacyStartedAt: active.startedAt))
        XCTAssertEqual(paused.destinationURL(runID: active.sessionID), WellSpentDeepLink.trackerURL)
    }

    func testRealIntentPersistsRevisionBeforeCallingAppBridge() async throws {
        let id = UUID()
        let previous = WellSpentLiveActivityHandoffDispatcher.reconcile
        defer {
            WellSpentLiveActivityHandoffDispatcher.reconcile = previous
            try? WellSpentStopHandoff.acknowledge(sessionID: id)
        }
        var called = false
        WellSpentLiveActivityHandoffDispatcher.reconcile = {
            called = true
            let request = try? WellSpentStopHandoff.pendingRequests().first { $0.sessionID == id }
            XCTAssertEqual(request?.expectedRevision, 7)
            XCTAssertEqual(request?.sessionID, id)
        }
        _ = try await StopWellSpentTimerIntent(activityID: id, revision: 7).perform()
        XCTAssertTrue(called)
    }

    func testIntentWithoutReadyAppBridgeRemainsDurable() async throws {
        let id = UUID()
        let previous = WellSpentLiveActivityHandoffDispatcher.reconcile
        defer {
            WellSpentLiveActivityHandoffDispatcher.reconcile = previous
            try? WellSpentStopHandoff.acknowledge(sessionID: id)
        }
        WellSpentLiveActivityHandoffDispatcher.reconcile = nil
        _ = try await StopWellSpentTimerIntent(activityID: id, revision: 3).perform()
        let first = try XCTUnwrap(WellSpentStopHandoff.pendingRequests().first { $0.sessionID == id })
        _ = try await StopWellSpentTimerIntent(activityID: id, revision: 3).perform()
        let repeated = try XCTUnwrap(WellSpentStopHandoff.pendingRequests().first { $0.sessionID == id })
        XCTAssertEqual(first, repeated)
        XCTAssertEqual(first.expectedRevision, 3)
    }

    private func projection(
        id: UUID = UUID(), phase: TimerRunState = .running, revision: Int64 = 1, name: Bool = false
    ) -> LiveActivityProjection {
        LiveActivityProjection(
            sessionID: id, startedAt: Date(timeIntervalSince1970: 100),
            projectName: "Private client", showsProjectName: name,
            requestedAt: Date(timeIntervalSince1970: 300), phase: phase,
            countedSeconds: 150, currentSegmentStartedAt: phase == .running ? Date(timeIntervalSince1970: 250) : nil,
            revision: revision, endedAt: phase == .ended ? Date(timeIntervalSince1970: 300) : nil
        )
    }

    private func existing(_ systemID: String, projection: LiveActivityProjection) -> ExistingLiveActivityProjection {
        ExistingLiveActivityProjection(
            systemID: systemID, sessionID: projection.sessionID, startedAt: projection.startedAt)
    }
}

@MainActor
private final class ActivityTestGate {
    private var continuation: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }
    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class SuspensibleActivityDriver: LiveActivityDriver {
    var activitiesEnabled = true
    var canRequestActivity = true
    var activities: [ExistingLiveActivityProjection] = []
    var requests: [LiveActivityProjection] = []
    var updates: [LiveActivityProjection] = []
    var finalStates: [WellSpentActivityAttributes.ContentState] = []
    var onEnd: (() async -> Void)?
    var onUpdate: (() async -> Void)?
    var inFlight = 0
    var maximumInFlight = 0

    func request(_ projection: LiveActivityProjection) throws {
        begin()
        defer { inFlight -= 1 }
        requests.append(projection)
        activities.append(
            .init(systemID: UUID().uuidString, sessionID: projection.sessionID, startedAt: projection.startedAt)
        )
    }

    func update(systemID: String, projection: LiveActivityProjection) async {
        begin()
        defer { inFlight -= 1 }
        await onUpdate?()
        updates.append(projection)
    }

    func end(systemID: String, final: LiveActivityProjection?) async {
        begin()
        defer { inFlight -= 1 }
        await onEnd?()
        if let final { finalStates.append(final.contentState) }
        activities.removeAll { $0.systemID == systemID }
    }

    private func begin() {
        inFlight += 1
        maximumInFlight = max(maximumInFlight, inFlight)
    }
}
