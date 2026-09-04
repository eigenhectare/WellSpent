import AppIntents
import Foundation
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatch
@testable import WellSpentWatchStore

@MainActor
final class WatchSystemCommandTests: XCTestCase {
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let otherProjectID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let epoch = Date(timeIntervalSince1970: 2_000_000_000)

    func testAllSystemActionsUseDurableOutboxAndExactBoundariesOffline() throws {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        var timestamp = epoch
        let boundary = WatchSystemCommandBoundary(now: { timestamp }, timeZoneID: { "UTC" })
        let started = try XCTUnwrap(boundary.perform(.init(action: .start, projectID: projectID), store: store))
        let runID = try XCTUnwrap(started.projection.activeRun?.id)
        timestamp = epoch.addingTimeInterval(10)
        _ = try boundary.perform(.init(action: .pause), store: store)
        XCTAssertNil(try boundary.perform(.init(action: .pause), store: store))
        timestamp = epoch.addingTimeInterval(100)
        _ = try boundary.perform(.init(action: .resume), store: store)
        XCTAssertNil(try boundary.perform(.init(action: .resume), store: store))
        timestamp = epoch.addingTimeInterval(120)
        _ = try boundary.perform(.init(action: .switchProject, projectID: otherProjectID), store: store)
        let switched = try store.state().projection
        XCTAssertEqual(switched.recentlyEndedRun?.id, runID)
        XCTAssertEqual(switched.recentlyEndedRun?.endedAt, timestamp)
        XCTAssertEqual(switched.activeRun?.startedAt, timestamp)
        XCTAssertEqual(switched.activeRun?.projectID, otherProjectID)
        XCTAssertEqual(
            switched.recentlyEndedRunSegments.reduce(0) { $0 + $1.endedAt!.timeIntervalSince($1.startedAt) }, 30)
        timestamp = epoch.addingTimeInterval(150)
        _ = try boundary.perform(.init(action: .end), store: store)
        XCTAssertNil(try boundary.perform(.init(action: .end), store: store))
        XCTAssertEqual(try store.pendingOutbox().count, 5)
        XCTAssertTrue(try store.state().isPendingSync)
        XCTAssertNil(try store.state().projection.activeRun)
    }

    func testDuplicateStartIsNoOpAndCannotSilentlySwitchProjects() throws {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        let boundary = WatchSystemCommandBoundary(now: { self.epoch })
        _ = try boundary.perform(.init(action: .start, projectID: projectID), store: store)
        let before = try store.state()
        XCTAssertNil(try boundary.perform(.init(action: .start, projectID: projectID), store: store))
        XCTAssertThrowsError(try boundary.perform(.init(action: .start, projectID: otherProjectID), store: store))
        XCTAssertEqual(try store.state(), before)
    }

    func testStaleControlCannotAffectNewRunOrReplayAfterEnd() throws {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        var timestamp = epoch
        let boundary = WatchSystemCommandBoundary(now: { timestamp })
        let start = WatchSystemRequest(
            action: .start, projectID: projectID,
            expectedContext: WatchCommandContext.token(for: try store.state()))
        _ = try boundary.perform(start, store: store)
        let end = WatchSystemRequest(action: .end, expectedContext: WatchCommandContext.token(for: try store.state()))
        timestamp = epoch.addingTimeInterval(10)
        _ = try boundary.perform(end, store: store)
        XCTAssertThrowsError(try boundary.perform(start, store: store))
        timestamp = epoch.addingTimeInterval(20)
        _ = try boundary.perform(.init(action: .start, projectID: otherProjectID), store: store)
        let current = try store.state()
        XCTAssertThrowsError(try boundary.perform(end, store: store))
        XCTAssertEqual(try store.state(), current)
    }

    func testBlockedUnsupportedAndArchivedContextsDoNotWrite() throws {
        for fixture in [WatchUITestFixture.conflict, .unsupported, .setup] {
            let (store, _) = try fixture.makeRuntime()
            let before = try store.state()
            XCTAssertThrowsError(
                try WatchSystemCommandBoundary(now: { self.epoch })
                    .perform(.init(action: .start, projectID: projectID), store: store))
            XCTAssertEqual(try store.state(), before)
        }
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        XCTAssertThrowsError(
            try WatchSystemCommandBoundary(now: { self.epoch })
                .perform(.init(action: .start, projectID: UUID()), store: store))
        XCTAssertTrue(try store.pendingOutbox().isEmpty)
    }

    func testFailedSystemSaveRollsBackAndCanRetry() throws {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        let before = try store.state()
        store.setBeforeSaveForTesting { throw WatchSystemActionError.saveFailed }
        let boundary = WatchSystemCommandBoundary(now: { self.epoch })
        let request = WatchSystemRequest(
            action: .start, projectID: projectID,
            expectedContext: WatchCommandContext.token(for: before))
        XCTAssertThrowsError(try boundary.perform(request, store: store))
        XCTAssertEqual(try store.state(), before)
        store.setBeforeSaveForTesting {}
        XCTAssertNotNil(try boundary.perform(request, store: store))
        XCTAssertEqual(try store.pendingOutbox().count, 1)
    }

    func testControlModelHasSafeRecoveryAndExplicitStateDependentActions() throws {
        for (fixture, expected) in [
            (WatchUITestFixture.populated, WatchSystemAction.start), (.activePending, .pause),
            (.paused, .resume), (.conflict, .open), (.unsupported, .open), (.setup, .open),
        ] {
            let (store, _) = try fixture.makeRuntime()
            let state = try store.state()
            let widget = WatchWidgetState.make(
                projection: state.projection, pendingSync: state.isPendingSync, isBlocked: state.isBlocked,
                recentProjectIDs: state.recentProjectIDs, commandContext: WatchCommandContext.token(for: state))
            let value = WatchSystemControlValue.make(
                state: widget, favoriteID: projectID, availableIDs: Set(state.projection.projects.map(\.id)))
            XCTAssertEqual(value.request.action, expected)
            XCTAssertEqual(value.pendingSync, state.isPendingSync)
            XCTAssertFalse(value.title.contains("Client"))
        }
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        let state = try store.state()
        let widget = WatchWidgetState.make(
            projection: state.projection, pendingSync: false, isBlocked: false,
            recentProjectIDs: [], commandContext: WatchCommandContext.token(for: state))
        let staleFavorite = WatchSystemControlValue.make(
            state: widget, favoriteID: UUID(), availableIDs: Set(state.projection.projects.map(\.id)))
        XCTAssertEqual(staleFavorite.request.action, .open)
    }

    func testControlIntentWithoutValidParametersCanOnlyOpen() {
        let intent = WellSpentWatchControlAction()
        intent.action = "end"
        XCTAssertEqual(intent.systemRequest.action, .open)
        intent.expectedContext = "old-state"
        XCTAssertEqual(intent.systemRequest.action, .end)
        intent.action = "erase"
        XCTAssertEqual(intent.systemRequest.action, .open)
    }

    func testActualAppIntentPerformUsesRegisteredCommandBoundary() async throws {
        let (store, _) = try WatchUITestFixture.populated.makeRuntime()
        let original = WatchSystemActionDispatcher.execute
        defer { WatchSystemActionDispatcher.execute = original }
        WatchSystemActionDispatcher.execute = { request in
            _ = try WatchSystemCommandBoundary(now: { self.epoch }).perform(request, store: store)
            return "Timer saved on Watch."
        }
        let intent = StartWellSpentWatchTimerIntent()
        intent.project = WellSpentWatchProjectEntity(id: projectID, displayName: "Project")
        _ = try await intent.perform()
        XCTAssertEqual(try store.pendingOutbox().count, 1)
        XCTAssertEqual(try store.state().projection.activeRun?.projectID, projectID)
        WatchSystemActionDispatcher.execute = nil
        do {
            _ = try await intent.perform()
            XCTFail("An extension without the app executor must fail safely")
        } catch {}
        XCTAssertEqual(try store.pendingOutbox().count, 1)
    }
}
