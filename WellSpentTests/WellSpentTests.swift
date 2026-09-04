import Foundation
import WellSpentShared
import XCTest

final class WellSpentTests: XCTestCase {
    func testSharedLiveActivityStateCanBeCreated() {
        let state = WellSpentActivityAttributes.ContentState(phase: .running)

        XCTAssertEqual(state.statusText, "Running")
        XCTAssertNil(state.endedAt)
        XCTAssertEqual(state.displayLabel, "WellSpent timer")
    }

    func testLiveActivityPrivacyRequiresExplicitOptIn() {
        let hidden = WellSpentActivityAttributes.ContentState(
            phase: .running,
            projectName: "Confidential Client",
            showsProjectName: false
        )
        let visible = WellSpentActivityAttributes.ContentState(
            phase: .running,
            projectName: "Confidential Client",
            showsProjectName: true
        )

        XCTAssertEqual(hidden.displayLabel, "WellSpent timer")
        XCTAssertEqual(hidden.stopAccessibilityLabel, "Stop WellSpent timer")
        XCTAssertEqual(visible.displayLabel, "Confidential Client")
        XCTAssertEqual(visible.stopAccessibilityLabel, "Stop Confidential Client timer")
    }

    func testStopPersistsTheExactCapturedEndTimeAndFirstStopWins() throws {
        let suiteName = "WellSpentTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let activityID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000.125)
        let exactEndTime = Date(timeIntervalSince1970: 1_700_003_600.875)
        let laterDuplicateStop = exactEndTime.addingTimeInterval(60)

        try WellSpentSpikeStorage.begin(
            activityID: activityID,
            at: startedAt,
            suiteName: suiteName
        )
        let firstResult = try WellSpentSpikeStorage.stop(
            activityID: activityID,
            at: exactEndTime,
            suiteName: suiteName
        )
        let duplicateResult = try WellSpentSpikeStorage.stop(
            activityID: activityID,
            at: laterDuplicateStop,
            suiteName: suiteName
        )

        XCTAssertEqual(firstResult.endedAt, exactEndTime)
        XCTAssertEqual(duplicateResult.endedAt, exactEndTime)
        XCTAssertEqual(
            try WellSpentSpikeStorage.record(activityID: activityID, suiteName: suiteName)?.endedAt,
            exactEndTime
        )
    }

    func testClearingEmptySpikeStorageIsAlreadySuccessful() throws {
        let suiteName = "WellSpentTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        XCTAssertNoThrow(try WellSpentSpikeStorage.clearSpikeData(suiteName: suiteName))
    }

    func testClearingSpikeStorageRemovesOnlySpikeKeys() throws {
        let suiteName = "WellSpentTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let activityID = UUID()
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.set("keep", forKey: "unrelated")
        try WellSpentSpikeStorage.begin(activityID: activityID, at: .now, suiteName: suiteName)

        try WellSpentSpikeStorage.clearSpikeData(suiteName: suiteName)

        XCTAssertNil(try WellSpentSpikeStorage.record(activityID: activityID, suiteName: suiteName))
        XCTAssertEqual(defaults.string(forKey: "unrelated"), "keep")
    }

    func testCompletionDeepLinkRoundTripsActivityID() {
        let activityID = UUID()
        let url = WellSpentDeepLink.completionURL(for: activityID)

        XCTAssertEqual(WellSpentDeepLink.completionActivityID(from: url), activityID)
    }

    func testTrackerDeepLinkOnlyMatchesTrackerRoute() {
        XCTAssertTrue(WellSpentDeepLink.isTrackerURL(WellSpentDeepLink.trackerURL))
        XCTAssertFalse(
            WellSpentDeepLink.isTrackerURL(
                WellSpentDeepLink.completionURL(for: UUID())
            )
        )
        XCTAssertFalse(
            WellSpentDeepLink.isTrackerURL(URL(string: "wellspent://track/extra")!)
        )
    }

    func testProductionStopHandoffKeepsFirstTimestampUntilAcknowledged() throws {
        let suiteName = "WellSpentStopHandoffTests.\(UUID().uuidString)"
        defer { try? WellSpentStopHandoff.clear(suiteName: suiteName) }
        let sessionID = UUID()
        let firstEnd = Date(timeIntervalSince1970: 1_900_000_000.125)

        let first = try WellSpentStopHandoff.persist(
            sessionID: sessionID,
            endedAt: firstEnd,
            endTimeZoneID: "America/New_York",
            suiteName: suiteName
        )
        let retry = try WellSpentStopHandoff.persist(
            sessionID: sessionID,
            endedAt: firstEnd.addingTimeInterval(30),
            endTimeZoneID: "UTC",
            suiteName: suiteName
        )

        XCTAssertEqual(first, retry)
        XCTAssertEqual(try WellSpentStopHandoff.pendingRequests(suiteName: suiteName), [first])
        try WellSpentStopHandoff.acknowledge(sessionID: sessionID, suiteName: suiteName)
        XCTAssertTrue(try WellSpentStopHandoff.pendingRequests(suiteName: suiteName).isEmpty)
    }

    func testConcurrentStopHandoffConsumptionDoesNotRacePersistenceVerification() async throws {
        let suiteName = "WellSpentStopHandoffRaceTests.\(UUID().uuidString)"
        defer { try? WellSpentStopHandoff.clear(suiteName: suiteName) }

        for index in 0..<50 {
            let sessionID = UUID()
            let producer = Task.detached {
                try WellSpentStopHandoff.persist(
                    sessionID: sessionID,
                    endedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(index)),
                    endTimeZoneID: "UTC",
                    suiteName: suiteName
                )
            }
            let consumer = Task.detached { () throws -> Bool in
                for _ in 0..<1_000 {
                    if try WellSpentStopHandoff.pendingRequests(suiteName: suiteName)
                        .contains(where: { $0.sessionID == sessionID })
                    {
                        try WellSpentStopHandoff.acknowledge(
                            sessionID: sessionID,
                            suiteName: suiteName
                        )
                        return true
                    }
                    await Task.yield()
                }
                return false
            }

            let persistedRequest = try await producer.value
            let didConsume = try await consumer.value
            XCTAssertEqual(persistedRequest.sessionID, sessionID)
            XCTAssertTrue(didConsume)
            XCTAssertFalse(
                try WellSpentStopHandoff.pendingRequests(suiteName: suiteName)
                    .contains(where: { $0.sessionID == sessionID })
            )
        }
    }

    func testProductionAppGroupStopHandoffRoundTripsAtomically() throws {
        let sessionID = UUID()
        defer { try? WellSpentStopHandoff.acknowledge(sessionID: sessionID) }
        let endedAt = Date(timeIntervalSince1970: 1_900_000_123.456)

        let request = try WellSpentStopHandoff.persist(
            sessionID: sessionID,
            endedAt: endedAt,
            endTimeZoneID: "America/New_York"
        )

        XCTAssertEqual(request.sessionID, sessionID)
        XCTAssertEqual(request.endedAt, endedAt)
        XCTAssertTrue(
            try WellSpentStopHandoff.pendingRequests()
                .contains(where: { $0 == request })
        )
        try WellSpentStopHandoff.acknowledge(sessionID: sessionID)
        XCTAssertFalse(
            try WellSpentStopHandoff.pendingRequests()
                .contains(where: { $0.sessionID == sessionID })
        )
    }

    func testProductionStopHandoffContainsNoProjectOrNoteContent() throws {
        let request = WellSpentStopRequest(
            sessionID: UUID(),
            endedAt: Date(timeIntervalSince1970: 1_900_000_000),
            endTimeZoneID: "UTC"
        )
        let encoded = try XCTUnwrap(String(data: JSONEncoder().encode(request), encoding: .utf8))

        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("project"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("note"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("client"))
    }
}
