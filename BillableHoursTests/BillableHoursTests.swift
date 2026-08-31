import BillableHoursShared
import Foundation
import XCTest

final class BillableHoursTests: XCTestCase {
    func testSharedLiveActivityStateCanBeCreated() {
        let state = BillableHoursActivityAttributes.ContentState(phase: .running)

        XCTAssertEqual(state.statusText, "Running")
        XCTAssertNil(state.endedAt)
        XCTAssertEqual(state.displayLabel, "Billable timer")
    }

    func testLiveActivityPrivacyRequiresExplicitOptIn() {
        let hidden = BillableHoursActivityAttributes.ContentState(
            phase: .running,
            projectName: "Confidential Client",
            showsProjectName: false
        )
        let visible = BillableHoursActivityAttributes.ContentState(
            phase: .running,
            projectName: "Confidential Client",
            showsProjectName: true
        )

        XCTAssertEqual(hidden.displayLabel, "Billable timer")
        XCTAssertEqual(hidden.stopAccessibilityLabel, "Stop billable timer")
        XCTAssertEqual(visible.displayLabel, "Confidential Client")
        XCTAssertEqual(visible.stopAccessibilityLabel, "Stop Confidential Client timer")
    }

    func testStopPersistsTheExactCapturedEndTimeAndFirstStopWins() throws {
        let suiteName = "BillableHoursTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }

        let activityID = UUID()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000.125)
        let exactEndTime = Date(timeIntervalSince1970: 1_700_003_600.875)
        let laterDuplicateStop = exactEndTime.addingTimeInterval(60)

        try BillableHoursSpikeStorage.begin(
            activityID: activityID,
            at: startedAt,
            suiteName: suiteName
        )
        let firstResult = try BillableHoursSpikeStorage.stop(
            activityID: activityID,
            at: exactEndTime,
            suiteName: suiteName
        )
        let duplicateResult = try BillableHoursSpikeStorage.stop(
            activityID: activityID,
            at: laterDuplicateStop,
            suiteName: suiteName
        )

        XCTAssertEqual(firstResult.endedAt, exactEndTime)
        XCTAssertEqual(duplicateResult.endedAt, exactEndTime)
        XCTAssertEqual(
            try BillableHoursSpikeStorage.record(activityID: activityID, suiteName: suiteName)?.endedAt,
            exactEndTime
        )
    }

    func testCompletionDeepLinkRoundTripsActivityID() {
        let activityID = UUID()
        let url = BillableHoursDeepLink.completionURL(for: activityID)

        XCTAssertEqual(BillableHoursDeepLink.completionActivityID(from: url), activityID)
    }

    func testTrackerDeepLinkOnlyMatchesTrackerRoute() {
        XCTAssertTrue(BillableHoursDeepLink.isTrackerURL(BillableHoursDeepLink.trackerURL))
        XCTAssertFalse(
            BillableHoursDeepLink.isTrackerURL(
                BillableHoursDeepLink.completionURL(for: UUID())
            )
        )
        XCTAssertFalse(
            BillableHoursDeepLink.isTrackerURL(URL(string: "billablehours://track/extra")!)
        )
    }

    func testProductionStopHandoffKeepsFirstTimestampUntilAcknowledged() throws {
        let suiteName = "BillableHoursStopHandoffTests.\(UUID().uuidString)"
        defer { try? BillableHoursStopHandoff.clear(suiteName: suiteName) }
        let sessionID = UUID()
        let firstEnd = Date(timeIntervalSince1970: 1_900_000_000.125)

        let first = try BillableHoursStopHandoff.persist(
            sessionID: sessionID,
            endedAt: firstEnd,
            endTimeZoneID: "America/New_York",
            suiteName: suiteName
        )
        let retry = try BillableHoursStopHandoff.persist(
            sessionID: sessionID,
            endedAt: firstEnd.addingTimeInterval(30),
            endTimeZoneID: "UTC",
            suiteName: suiteName
        )

        XCTAssertEqual(first, retry)
        XCTAssertEqual(try BillableHoursStopHandoff.pendingRequests(suiteName: suiteName), [first])
        try BillableHoursStopHandoff.acknowledge(sessionID: sessionID, suiteName: suiteName)
        XCTAssertTrue(try BillableHoursStopHandoff.pendingRequests(suiteName: suiteName).isEmpty)
    }

    func testConcurrentStopHandoffConsumptionDoesNotRacePersistenceVerification() async throws {
        let suiteName = "BillableHoursStopHandoffRaceTests.\(UUID().uuidString)"
        defer { try? BillableHoursStopHandoff.clear(suiteName: suiteName) }

        for index in 0..<50 {
            let sessionID = UUID()
            let producer = Task.detached {
                try BillableHoursStopHandoff.persist(
                    sessionID: sessionID,
                    endedAt: Date(timeIntervalSince1970: 1_900_000_000 + Double(index)),
                    endTimeZoneID: "UTC",
                    suiteName: suiteName
                )
            }
            let consumer = Task.detached { () throws -> Bool in
                for _ in 0..<1_000 {
                    if try BillableHoursStopHandoff.pendingRequests(suiteName: suiteName)
                        .contains(where: { $0.sessionID == sessionID })
                    {
                        try BillableHoursStopHandoff.acknowledge(
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
                try BillableHoursStopHandoff.pendingRequests(suiteName: suiteName)
                    .contains(where: { $0.sessionID == sessionID })
            )
        }
    }

    func testProductionAppGroupStopHandoffRoundTripsAtomically() throws {
        let sessionID = UUID()
        defer { try? BillableHoursStopHandoff.acknowledge(sessionID: sessionID) }
        let endedAt = Date(timeIntervalSince1970: 1_900_000_123.456)

        let request = try BillableHoursStopHandoff.persist(
            sessionID: sessionID,
            endedAt: endedAt,
            endTimeZoneID: "America/New_York"
        )

        XCTAssertEqual(request.sessionID, sessionID)
        XCTAssertEqual(request.endedAt, endedAt)
        XCTAssertTrue(
            try BillableHoursStopHandoff.pendingRequests()
                .contains(where: { $0 == request })
        )
        try BillableHoursStopHandoff.acknowledge(sessionID: sessionID)
        XCTAssertFalse(
            try BillableHoursStopHandoff.pendingRequests()
                .contains(where: { $0.sessionID == sessionID })
        )
    }

    func testProductionStopHandoffContainsNoProjectOrNoteContent() throws {
        let request = BillableHoursStopRequest(
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
