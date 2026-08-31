import Foundation
import SwiftData
import XCTest

@testable import BillableHours

final class BillableHoursPersistenceTests: XCTestCase {
    func testV2SchemaInitializesWithProjectSessionAndTagEntities() throws {
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let context = ModelContext(container)

        let project = ProjectRecord(name: "Schema fixture")
        let session = TimeSessionRecord(
            projectID: project.id,
            source: .manual,
            startAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            endAt: Date(timeIntervalSince1970: 1_700_003_600.875),
            startTimeZoneID: "America/New_York",
            endTimeZoneID: "America/New_York",
            note: "Fixture note"
        )

        context.insert(project)
        context.insert(session)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectRecord>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
        let duration = try XCTUnwrap(session.duration)
        XCTAssertEqual(duration, 3_600.75, accuracy: 0.000_001)
    }

    func testInMemoryStoreDoesNotCreateTheConfiguredDiskStore() throws {
        let container = try BillableHoursPersistence.makeInMemoryContainer()

        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }

    func testV2SchemaAvoidsUniquenessConstraintsAndRelationships() {
        let entities = BillableHoursPersistence.schema.entities

        XCTAssertEqual(entities.count, 4)
        XCTAssertTrue(entities.allSatisfy { $0.uniquenessConstraints.isEmpty })
        XCTAssertTrue(entities.allSatisfy { $0.relationships.isEmpty })
    }

    func testProjectAndSessionPersistAcrossContainerRecreation() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }

        let projectID = UUID()
        let sessionID = UUID()
        let startAt = Date(timeIntervalSince1970: 1_710_000_000.25)
        let endAt = Date(timeIntervalSince1970: 1_710_001_800.75)

        do {
            let container = try BillableHoursPersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let context = ModelContext(container)
            context.insert(ProjectRecord(id: projectID, name: "Persistent project"))
            context.insert(
                TimeSessionRecord(
                    id: sessionID,
                    projectID: projectID,
                    source: .timer,
                    startAt: startAt,
                    endAt: endAt,
                    startTimeZoneID: "UTC",
                    endTimeZoneID: "UTC"
                )
            )
            try context.save()
        }

        do {
            let reopenedContainer = try BillableHoursPersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let reopenedContext = ModelContext(reopenedContainer)
            let projects = try reopenedContext.fetch(FetchDescriptor<ProjectRecord>())
            let sessions = try reopenedContext.fetch(FetchDescriptor<TimeSessionRecord>())

            XCTAssertEqual(projects.map(\.id), [projectID])
            XCTAssertEqual(sessions.map(\.id), [sessionID])
            XCTAssertEqual(sessions.first?.projectID, projectID)
            XCTAssertEqual(sessions.first?.startAt, startAt)
            XCTAssertEqual(sessions.first?.endAt, endAt)
        }
    }

    func testOldestShippedFixtureOpensThroughMigrationHarness() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }

        let fixtureProjectID = UUID()
        let fixtureSessionID = UUID()
        let fixtureSchema = Schema(versionedSchema: BillableHoursSchemaV1.self)
        let fixtureConfiguration = ModelConfiguration(
            "V1Fixture",
            schema: fixtureSchema,
            url: fixture.storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            // Simulates a store produced by the oldest shipped app, before a
            // future release adds an actual migration stage to the harness.
            let fixtureContainer = try ModelContainer(
                for: fixtureSchema,
                configurations: [fixtureConfiguration]
            )
            let context = ModelContext(fixtureContainer)
            context.insert(
                BillableHoursSchemaV1.ProjectRecord(
                    id: fixtureProjectID,
                    name: "V1 fixture"
                )
            )
            context.insert(
                BillableHoursSchemaV1.TimeSessionRecord(
                    id: fixtureSessionID,
                    projectID: fixtureProjectID,
                    source: .manual,
                    startAt: Date(timeIntervalSince1970: 1_720_000_000),
                    endAt: Date(timeIntervalSince1970: 1_720_000_900),
                    startTimeZoneID: "Europe/London",
                    endTimeZoneID: "Europe/London",
                    note: "Oldest schema fixture"
                )
            )
            try context.save()
        }

        let migratedContainer = try BillableHoursPersistence.makePersistentContainer(
            storeURL: fixture.storeURL
        )
        let migratedContext = ModelContext(migratedContainer)
        let projects = try migratedContext.fetch(FetchDescriptor<ProjectRecord>())
        let sessions = try migratedContext.fetch(FetchDescriptor<TimeSessionRecord>())

        XCTAssertEqual(projects.first?.id, fixtureProjectID)
        XCTAssertNil(projects.first?.emoji)
        XCTAssertEqual(sessions.first?.id, fixtureSessionID)
        XCTAssertEqual(sessions.first?.note, "Oldest schema fixture")
        XCTAssertEqual(try migratedContext.fetchCount(FetchDescriptor<SessionTagRecord>()), 0)
        XCTAssertEqual(
            try migratedContext.fetchCount(FetchDescriptor<SessionTagAssignmentRecord>()),
            0
        )
    }
}

private struct TemporaryStoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BillableHoursPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        storeURL = directoryURL.appendingPathComponent("BillableHours.store")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
