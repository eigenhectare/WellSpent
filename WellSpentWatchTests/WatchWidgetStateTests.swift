import Foundation
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatchStore

final class WatchWidgetStateTests: XCTestCase {
    private let epoch = Date(timeIntervalSince1970: 1_800_000_000)
    private let projectID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!

    func testNamesAreRemovedBeforeEnteringWidgetByDefaultAndOnOptOut() {
        for preference in [nil, false] as [Bool?] {
            var projection = makeProjection()
            projection.showProjectNamesOnSystemSurfaces = preference
            let running = state(projection)
            XCTAssertNil(running.projectName)
            projection.activeRun = nil
            projection.activeRunSegments = []
            XCTAssertNil(state(projection).recentProjects.first?.name)
        }
    }

    func testExplicitOptInAllowsNamesWithoutNotesTagsOrHistoryInWidgetState() {
        var projection = makeProjection()
        projection.showProjectNamesOnSystemSurfaces = true
        XCTAssertEqual(state(projection).projectName, "Fictitious Client")
        projection.activeRun = nil
        projection.activeRunSegments = []
        XCTAssertEqual(state(projection).recentProjects.first?.name, "Fictitious Client")
    }

    func testElapsedIncludesClosedSegmentsAndExcludesPause() {
        let widget = state(makeProjection())
        XCTAssertEqual(widget.elapsed(at: epoch.addingTimeInterval(1_200)), 900)
        XCTAssertEqual(widget.elapsed(at: epoch.addingTimeInterval(1_237)), 937)
        XCTAssertEqual(widget.elapsedTimerStart, epoch.addingTimeInterval(300))
        XCTAssertEqual(widget.goalDeadline, epoch.addingTimeInterval(1_300))
        XCTAssertTrue(widget.pendingSync)
    }

    func testPausedElapsedIsFrozenAndHasNoRunningDeadline() {
        let widget = state(makeProjection(paused: true))
        XCTAssertEqual(widget.timerState, .paused)
        XCTAssertEqual(widget.elapsed(at: epoch.addingTimeInterval(1_200)), 900)
        XCTAssertEqual(widget.elapsed(at: epoch.addingTimeInterval(90_000)), 900)
        XCTAssertNil(widget.elapsedTimerStart)
        XCTAssertNil(widget.goalDeadline)
    }

    func testTimelineOnlyAddsFutureGoalBoundaryWithinRefreshWindow() {
        let widget = state(makeProjection())
        let now = epoch.addingTimeInterval(1_200)
        XCTAssertEqual(widget.timelineDates(from: now), [now, epoch.addingTimeInterval(1_300)])
        let overtime = epoch.addingTimeInterval(1_400)
        XCTAssertEqual(widget.timelineDates(from: overtime), [overtime])
        XCTAssertEqual(widget.timelineDates(from: epoch.addingTimeInterval(-1_000)), [epoch.addingTimeInterval(-1_000)])
        XCTAssertEqual(state(makeProjection(paused: true)).timelineDates(from: now), [now])
    }

    func testBlockedAndUpdateRequiredSuppressActiveTimerAndProjectIdentity() {
        var projection = makeProjection()
        projection.showProjectNamesOnSystemSurfaces = true
        let blocked = state(projection, blocked: true)
        XCTAssertEqual(blocked.timerState, .blocked)
        XCTAssertNil(blocked.runID)
        XCTAssertNil(blocked.projectName)
        XCTAssertTrue(blocked.recentProjects.isEmpty)
        projection.updateGuidance = MinimumAppVersionGuidance(
            minimumPhoneBuild: nil, minimumWatchBuild: nil, updateRequired: true)
        XCTAssertEqual(state(projection, blocked: true).timerState, .updateRequired)
    }

    func testRecentProjectSelectionIsBoundedDeduplicatedAndSkipsMissingIDs() {
        var projection = WatchCachedProjection()
        projection.projects = (0..<10).map { index in
            ProjectSnapshot(id: UUID(), workspaceID: nil, name: "Fixture \(index)", colorToken: nil, symbolName: nil)
        }
        let recentID = projection.projects[4].id
        let widget = WatchWidgetState.make(
            projection: projection, pendingSync: false, isBlocked: false,
            recentProjectIDs: [UUID(), recentID, recentID])
        XCTAssertEqual(widget.recentProjects.count, 3)
        XCTAssertEqual(widget.recentProjects.first?.id, recentID)
        XCTAssertEqual(Set(widget.recentProjects.map(\.id)).count, 3)
        XCTAssertTrue(widget.recentProjects.allSatisfy { $0.name == nil })
    }

    func testLegacyCachedProjectionWithoutPreferenceDecodesPrivate() throws {
        let data = try ContractWireCodec.encodeCanonical(makeProjection())
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        json.removeValue(forKey: "showProjectNamesOnSystemSurfaces")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let projection = try ContractWireCodec.decodeCanonical(WatchCachedProjection.self, from: oldData)
        XCTAssertNil(projection.showProjectNamesOnSystemSurfaces)
        XCTAssertNil(state(projection).projectName)
    }

    func testRoutesRoundTripAndRejectParametersOrMutationURLs() {
        for route in [WatchWidgetRoute.projects, .project(projectID), .run(runID)] {
            XCTAssertEqual(WatchWidgetRoute(url: route.url), route)
        }
        for invalid in [
            "https://run/\(runID)", "wellspent-watch://end/\(runID)",
            "wellspent-watch://run/\(runID)/extra", "wellspent-watch://project/not-a-uuid",
            "wellspent-watch://projects?start=true", "wellspent-watch://run/\(runID)#secret",
            "wellspent-watch://name@projects", "wellspent-watch://projects:123",
        ] {
            XCTAssertNil(WatchWidgetRoute(url: URL(string: invalid)!))
        }
    }

    func testStaleLinksResolveToCurrentRunAndNeverMutateIt() {
        let projection = makeProjection()
        for route in [WatchWidgetRoute.project(UUID()), .run(UUID()), .projects] {
            XCTAssertEqual(route.resolved(in: projection, isBlocked: false), .run(runID))
        }
        XCTAssertEqual(WatchWidgetRoute.run(runID).resolved(in: projection, isBlocked: true), .projects)
        var idle = projection
        idle.activeRun = nil
        idle.activeRunSegments = []
        XCTAssertEqual(WatchWidgetRoute.project(projectID).resolved(in: idle, isBlocked: false), .project(projectID))
        XCTAssertEqual(WatchWidgetRoute.project(UUID()).resolved(in: idle, isBlocked: false), .projects)
        XCTAssertEqual(WatchWidgetRoute.run(runID).resolved(in: idle, isBlocked: false), .projects)
    }

    func testMirroredPhoneLinksOpenCurrentWatchRunWithoutMutation() throws {
        let projection = makeProjection()
        for raw in ["wellspent://track", "wellspent://completion/\(UUID())"] {
            let route = try XCTUnwrap(WatchWidgetRoute(url: URL(string: raw)!))
            XCTAssertEqual(route.resolved(in: projection, isBlocked: false), .run(runID))
            XCTAssertEqual(route.resolved(in: projection, isBlocked: true), .projects)
        }
        for invalid in [
            "wellspent://end/\(runID)", "wellspent://track?start=true",
            "wellspent://completion/\(runID)/extra", "wellspent://name@track",
        ] {
            XCTAssertNil(WatchWidgetRoute(url: URL(string: invalid)!))
        }
    }

    func testUnchangedPresentationDoesNotRequirePerSecondReloads() {
        let first = state(makeProjection())
        var projection = makeProjection()
        projection.totals = TimerTotalsSnapshot(
            todaySeconds: 999, weekSeconds: 999, calculatedAt: epoch, calendarTimeZoneID: "UTC")
        XCTAssertEqual(state(projection), first)
        XCTAssertNotEqual(state(makeProjection(paused: true)), first)
    }

    private func state(_ projection: WatchCachedProjection, blocked: Bool = false) -> WatchWidgetState {
        WatchWidgetState.make(projection: projection, pendingSync: true, isBlocked: blocked, recentProjectIDs: [])
    }

    private func makeProjection(paused: Bool = false) -> WatchCachedProjection {
        let run = TimerRunSnapshot(
            id: runID, workspaceID: nil, projectID: projectID, state: paused ? .paused : .running,
            startedAt: epoch, endedAt: nil, startTimeZoneID: "UTC", endTimeZoneID: nil,
            durationGoalSeconds: 1_000, normalizedNote: "Not for widgets", tagIDs: [],
            originDeviceID: projectID, revision: 3, lastAppliedMutationID: nil,
            createdAt: epoch, updatedAt: epoch, updatedTimeZoneID: "UTC")
        return WatchCachedProjection(
            projects: [
                ProjectSnapshot(
                    id: projectID, workspaceID: nil, name: "Fictitious Client", colorToken: nil, symbolName: nil)
            ],
            activeRun: run,
            activeRunSegments: [
                segment(start: 0, end: 600), segment(start: 900, end: paused ? 1_200 : nil),
            ])
    }

    private func segment(start: TimeInterval, end: TimeInterval?) -> TimerSegmentSnapshot {
        TimerSegmentSnapshot(
            id: UUID(), runID: runID, workspaceID: nil, projectID: projectID,
            startedAt: epoch.addingTimeInterval(start), endedAt: end.map { epoch.addingTimeInterval($0) },
            startTimeZoneID: "UTC", endTimeZoneID: end == nil ? nil : "UTC", revision: 3)
    }
}
