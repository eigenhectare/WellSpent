import Foundation
import SwiftData
import XCTest

@testable import WellSpent

@MainActor
final class TimerRunMigrationTests: XCTestCase {
    func testEmptyV1AndV2StoresMigrateAndReopenWithoutCreatingRows() throws {
        for version in [1, 2] {
            let fixture = try MigrationStoreFixture()
            defer { fixture.remove() }
            if version == 1 {
                try fixture.createV1 { _ in }
            } else {
                try fixture.createV2 { _ in }
            }

            for _ in 0..<2 {
                let container = try WellSpentPersistence.makePersistentContainer(
                    storeURL: fixture.storeURL
                )
                let context = ModelContext(container)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)
                XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
                XCTAssertEqual(
                    try context.fetchCount(FetchDescriptor<TimerRunTagAssignmentRecord>()),
                    0
                )
            }
        }
    }

    func testV1TimedAndManualRowsKeepExactIdentityBoundariesAndSource() throws {
        let fixture = try MigrationStoreFixture()
        defer { fixture.remove() }
        let projectID = UUID(uuidString: "10101010-1010-4010-8010-101010101010")!
        let endedID = UUID(uuidString: "20202020-2020-4020-8020-202020202020")!
        let activeID = UUID(uuidString: "30303030-3030-4030-8030-303030303030")!
        let manualID = UUID(uuidString: "40404040-4040-4040-8040-404040404040")!
        let start = Date(timeIntervalSince1970: 1_699_164_000.125)
        let end = Date(timeIntervalSince1970: 1_699_167_600.875)

        try fixture.createV1 { context in
            context.insert(WellSpentSchemaV1.ProjectRecord(id: projectID, name: "Legacy"))
            context.insert(
                WellSpentSchemaV1.TimeSessionRecord(
                    id: endedID,
                    projectID: projectID,
                    source: .timer,
                    startAt: start,
                    endAt: end,
                    startTimeZoneID: "America/New_York",
                    endTimeZoneID: "America/Chicago",
                    note: "Exact legacy note",
                    createdAt: start,
                    updatedAt: end
                )
            )
            context.insert(
                WellSpentSchemaV1.TimeSessionRecord(
                    id: activeID,
                    projectID: projectID,
                    source: .timer,
                    startAt: end,
                    startTimeZoneID: "America/Chicago",
                    createdAt: end,
                    updatedAt: end
                )
            )
            context.insert(
                WellSpentSchemaV1.TimeSessionRecord(
                    id: manualID,
                    projectID: projectID,
                    source: .manual,
                    startAt: start,
                    endAt: end,
                    startTimeZoneID: "UTC",
                    endTimeZoneID: "UTC"
                )
            )
        }

        let container = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let context = ModelContext(container)
        let sessions = try context.fetch(FetchDescriptor<TimeSessionRecord>())
        let runs = try context.fetch(FetchDescriptor<TimerRunRecord>())

        XCTAssertEqual(Set(sessions.map(\.id)), Set([endedID, activeID, manualID]))
        XCTAssertNil(sessions.first(where: { $0.id == manualID })?.timerRunID)
        XCTAssertEqual(
            sessions.first(where: { $0.id == endedID })?.timerRunID,
            LegacyTimerRunIdentity.runID(for: endedID)
        )
        let endedRun = try XCTUnwrap(
            runs.first { $0.id == LegacyTimerRunIdentity.runID(for: endedID) }
        )
        XCTAssertEqual(endedRun.state, .ended)
        XCTAssertEqual(endedRun.startAt, start)
        XCTAssertEqual(endedRun.endAt, end)
        XCTAssertEqual(endedRun.startTimeZoneID, "America/New_York")
        XCTAssertEqual(endedRun.endTimeZoneID, "America/Chicago")
        XCTAssertEqual(endedRun.note, "Exact legacy note")
        XCTAssertEqual(endedRun.originDeviceID, LegacyTimerRunIdentity.legacyImportOriginDeviceID)
        XCTAssertEqual(endedRun.revision, 0)
        XCTAssertEqual(end.timeIntervalSince(start), 3_600.75, accuracy: 0.000_001)
        XCTAssertEqual(
            endedRun.startAt.timeIntervalSinceReferenceDate.bitPattern,
            start.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            endedRun.endAt?.timeIntervalSinceReferenceDate.bitPattern,
            end.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(runs.first(where: { $0.id == LegacyTimerRunIdentity.runID(for: activeID) })?.state, .running)

        let reopened = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let reopenedRepository = SwiftDataTimerRunRepository(context: ModelContext(reopened))
        let activeRun = try XCTUnwrap(
            reopenedRepository.fetchRun(id: LegacyTimerRunIdentity.runID(for: activeID))
        )
        let activeSnapshot = try reopenedRepository.snapshot(activeRun)
        XCTAssertEqual(activeSnapshot.startAt, end)
        XCTAssertEqual(activeSnapshot.countedDuration(at: end.addingTimeInterval(9 * 3_600)), 9 * 3_600)
    }

    func testV2TagsArchivedRecordsAndReportInputsSurviveMigrationAndReopen() throws {
        let fixture = try MigrationStoreFixture()
        defer { fixture.remove() }
        let projectID = UUID(uuidString: "51515151-5151-4151-8151-515151515151")!
        let tagID = UUID(uuidString: "52525252-5252-4252-8252-525252525252")!
        let timedID = UUID(uuidString: "53535353-5353-4353-8353-535353535353")!
        let manualID = UUID(uuidString: "54545454-5454-4454-8454-545454545454")!
        let assignmentID = UUID(uuidString: "55555555-5555-4555-8555-555555555555")!
        let start = Date(timeIntervalSince1970: 1_750_000_000.25)
        let end = start.addingTimeInterval(7_200.5)

        try fixture.createV2 { context in
            context.insert(
                WellSpentSchemaV2.ProjectRecord(
                    id: projectID,
                    name: "Archived client",
                    status: .archived
                )
            )
            context.insert(
                WellSpentSchemaV2.SessionTagRecord(
                    id: tagID,
                    name: "legacy",
                    normalizedName: "legacy",
                    status: .archived
                )
            )
            context.insert(
                WellSpentSchemaV2.TimeSessionRecord(
                    id: timedID,
                    projectID: projectID,
                    source: .timer,
                    startAt: start,
                    endAt: end,
                    startTimeZoneID: "Australia/Lord_Howe",
                    endTimeZoneID: "Australia/Lord_Howe",
                    note: "Tagged"
                )
            )
            context.insert(
                WellSpentSchemaV2.TimeSessionRecord(
                    id: manualID,
                    projectID: projectID,
                    source: .manual,
                    startAt: start.addingTimeInterval(3_600),
                    endAt: end.addingTimeInterval(60),
                    startTimeZoneID: "UTC",
                    endTimeZoneID: "UTC"
                )
            )
            context.insert(
                WellSpentSchemaV2.SessionTagAssignmentRecord(
                    id: assignmentID,
                    sessionID: timedID,
                    tagID: tagID,
                    nameSnapshot: "legacy",
                    createdAt: start
                )
            )
        }

        for _ in 0..<2 {
            let container = try WellSpentPersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let context = ModelContext(container)
            let sessions = try context.fetch(FetchDescriptor<TimeSessionRecord>())
            let run = try XCTUnwrap(context.fetch(FetchDescriptor<TimerRunRecord>()).first)
            let runTags = try context.fetch(FetchDescriptor<TimerRunTagAssignmentRecord>())
            XCTAssertEqual(sessions.count, 2)
            XCTAssertEqual(run.id, LegacyTimerRunIdentity.runID(for: timedID))
            XCTAssertEqual(run.projectID, projectID)
            XCTAssertEqual(run.note, "Tagged")
            XCTAssertEqual(runTags.count, 1)
            XCTAssertEqual(
                runTags.first?.id,
                LegacyTimerRunIdentity.runTagAssignmentID(for: assignmentID)
            )
            XCTAssertEqual(runTags.first?.tagID, tagID)
            XCTAssertEqual(runTags.first?.nameSnapshot, "legacy")
            XCTAssertEqual(
                sessions.compactMap(\.duration).reduce(0, +),
                10_861,
                accuracy: 0.000_001
            )

            let sessionAssignments = try context.fetch(
                FetchDescriptor<SessionTagAssignmentRecord>()
            )
            let assignmentsBySession = Dictionary(
                grouping: sessionAssignments,
                by: \.sessionID
            )
            let snapshots = sessions.map { session in
                TimeSessionSnapshot(
                    record: session,
                    tags: (assignmentsBySession[session.id] ?? []).map(
                        SessionTagAssignmentSnapshot.init(record:)
                    )
                )
            }
            let reportSegments = ReportingEngine().segments(
                for: snapshots,
                selection: ReportSelection(
                    interval: DateInterval(
                        start: start.addingTimeInterval(-1),
                        end: end.addingTimeInterval(61)
                    )
                ),
                calendar: Calendar(identifier: .gregorian),
                now: end.addingTimeInterval(61)
            )
            XCTAssertEqual(Set(reportSegments.map(\.sessionID)), Set([timedID, manualID]))
            XCTAssertEqual(ReportingEngine().total(of: reportSegments), 10_861, accuracy: 0.000_001)
            XCTAssertTrue(reportSegments.allSatisfy(\.overlapsAnotherSession))
        }
    }

    func testV2MultipleActiveRowsArePreservedAndBlockCommands() throws {
        let fixture = try MigrationStoreFixture()
        defer { fixture.remove() }
        let projectID = UUID()
        let firstID = UUID(uuidString: "61616161-6161-4161-8161-616161616161")!
        let secondID = UUID(uuidString: "62626262-6262-4262-8262-626262626262")!
        try fixture.createV2 { context in
            context.insert(WellSpentSchemaV2.ProjectRecord(id: projectID, name: "Conflict"))
            for (id, start) in [(firstID, 100.0), (secondID, 200.0)] {
                context.insert(
                    WellSpentSchemaV2.TimeSessionRecord(
                        id: id,
                        projectID: projectID,
                        source: .timer,
                        startAt: Date(timeIntervalSince1970: start),
                        startTimeZoneID: "UTC"
                    )
                )
            }
        }

        let container = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let context = ModelContext(container)
        let repository = SwiftDataTimerRunRepository(context: context)
        let commands = TimerRunCommandService(
            repository: repository,
            dependencies: .live
        )
        guard
            case .reviewRequired(let runIDs, let segmentIDs, let reasons) =
                try commands.reconcileActiveState()
        else { return XCTFail("Expected review-required state") }
        XCTAssertEqual(Set(runIDs), Set([firstID, secondID].map(LegacyTimerRunIdentity.runID)))
        XCTAssertEqual(Set(segmentIDs), Set([firstID, secondID]))
        XCTAssertTrue(reasons.contains(.multipleNonEndedRuns))
        XCTAssertThrowsError(try commands.start(projectID: projectID))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 2)
    }
}

private struct MigrationStoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TimerRunMigrationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = directoryURL.appendingPathComponent("WellSpent.store")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func createV1(_ populate: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: WellSpentSchemaV1.self)
        let configuration = ModelConfiguration(
            "V1Fixture",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        try populate(context)
        try context.save()
    }

    func createV2(_ populate: (ModelContext) throws -> Void) throws {
        let schema = Schema(versionedSchema: WellSpentSchemaV2.self)
        let configuration = ModelConfiguration(
            "V2Fixture",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)
        try populate(context)
        try context.save()
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
