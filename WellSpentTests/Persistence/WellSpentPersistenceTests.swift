import Foundation
import SwiftData
import XCTest

@testable import WellSpent

final class WellSpentPersistenceTests: XCTestCase {
    func testV6SchemaInitializesWithProjectSessionRunOriginTagAndSyncEntities() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
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
        let container = try WellSpentPersistence.makeInMemoryContainer()

        XCTAssertTrue(container.configurations.allSatisfy(\.isStoredInMemoryOnly))
    }

    func testV6SchemaAvoidsUniquenessConstraintsAndRelationships() {
        let entities = WellSpentPersistence.schema.entities

        XCTAssertEqual(entities.count, 16)
        XCTAssertEqual(Schema(versionedSchema: WellSpentSchemaV5.self).entities.count, 15)
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
            let container = try WellSpentPersistence.makePersistentContainer(
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
            let reopenedContainer = try WellSpentPersistence.makePersistentContainer(
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

    func testPersistentStoreIsExcludedFromDeviceBackups() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }

        _ = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)

        XCTAssertTrue(try LocalStoragePrivacy.isExcludedFromBackup(fixture.directoryURL))
        XCTAssertTrue(try LocalStoragePrivacy.isExcludedFromBackup(fixture.storeURL))
    }

    func testV3StoreMigratesThroughV5WithoutChangingDomainData() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }
        let projectID = UUID()
        let v3Schema = Schema(versionedSchema: WellSpentSchemaV3.self)
        let v3Configuration = ModelConfiguration(
            "V3Fixture",
            schema: v3Schema,
            url: fixture.storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: v3Schema,
                configurations: [v3Configuration]
            )
            let context = ModelContext(container)
            context.insert(
                WellSpentSchemaV3.ProjectRecord(id: projectID, name: "Pre-sync project")
            )
            try context.save()
        }

        let migrated = try WellSpentPersistence.makePersistentContainer(
            storeURL: fixture.storeURL
        )
        let context = ModelContext(migrated)

        XCTAssertEqual(try context.fetch(FetchDescriptor<ProjectRecord>()).map(\.id), [projectID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneSyncMetadataRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneMutationInboxRecord>()), 0)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<PhoneAcknowledgementOutboxRecord>()),
            0
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneSnapshotReceiptRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneCanonicalSnapshotRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneTimerConflictRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneConflictMutationRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneEntityTombstoneRecord>()), 0)
    }

    func testV4StoreMigratesToV5WithoutChangingSyncJournal() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }
        let mutationID = UUID()
        let originID = UUID()
        let v4Schema = Schema(versionedSchema: WellSpentSchemaV4.self)
        let configuration = ModelConfiguration(
            "V4Fixture",
            schema: v4Schema,
            url: fixture.storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(for: v4Schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(
                WellSpentSchemaV4.PhoneMutationInboxRecord(
                    mutationID: mutationID,
                    originDeviceID: originID,
                    originSequence: 7,
                    payloadDigestHex: "fixture",
                    envelopeData: Data([1, 2, 3]),
                    receivedAt: Date(timeIntervalSince1970: 1_900_000_000)
                )
            )
            try context.save()
        }

        let migrated = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let context = ModelContext(migrated)
        let inbox = try XCTUnwrap(
            context.fetch(FetchDescriptor<PhoneMutationInboxRecord>()).first
        )
        XCTAssertEqual(inbox.mutationID, mutationID)
        XCTAssertEqual(inbox.originDeviceID, originID)
        XCTAssertEqual(inbox.originSequence, 7)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneTimerConflictRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneEntityTombstoneRecord>()), 0)
    }

    @MainActor
    func testV5MigratesToV6AndResetFenceSurvivesRelaunch() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }
        let schema = Schema(versionedSchema: WellSpentSchemaV5.self)
        let configuration = ModelConfiguration(
            "V5Fixture", schema: schema, url: fixture.storeURL, cloudKitDatabase: .none)
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)
            let metadata = PhoneSyncMetadataRecord(snapshotID: UUID(), updatedAt: .now)
            metadata.canonicalGeneration = 42
            context.insert(metadata)
            context.insert(ProjectRecord(name: "Erase me"))
            try context.save()
        }
        do {
            let container = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
            let context = ModelContext(container)
            XCTAssertEqual(try context.fetch(FetchDescriptor<PhoneSyncMetadataRecord>()).first?.canonicalGeneration, 42)
            try WellSpentLocalDataResetService(context: context).deleteAllUserData()
        }
        let container = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PhoneDataResetRecord>()).first?.minimumAcceptedGeneration, 43)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectRecord>()), 0)
    }

    @MainActor
    func testLocalDataResetDeletesEveryPersistentEntity() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Confidential client")
        let originID = UUID()
        let run = TimerRunRecord(
            projectID: project.id,
            state: .ended,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            originDeviceID: originID,
            revision: 1,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_800_003_600),
            updatedTimeZoneID: "UTC"
        )
        let session = TimeSessionRecord(
            projectID: project.id,
            source: .manual,
            timerRunID: run.id,
            startAt: Date(timeIntervalSince1970: 1_800_000_000),
            endAt: Date(timeIntervalSince1970: 1_800_003_600),
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            note: "Privileged work note"
        )
        let tag = SessionTagRecord(name: "private", normalizedName: "private")
        let assignment = SessionTagAssignmentRecord(
            sessionID: session.id,
            tagID: tag.id,
            nameSnapshot: tag.name
        )
        let runAssignment = TimerRunTagAssignmentRecord(
            timerRunID: run.id,
            tagID: tag.id,
            nameSnapshot: tag.name,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000)
        )
        context.insert(project)
        context.insert(TimerOriginRecord(id: originID, createdAt: run.createdAt))
        context.insert(run)
        context.insert(session)
        context.insert(tag)
        context.insert(assignment)
        context.insert(runAssignment)
        let mutationID = UUID()
        context.insert(
            PhoneSyncMetadataRecord(snapshotID: UUID(), updatedAt: run.updatedAt)
        )
        context.insert(
            PhoneMutationInboxRecord(
                mutationID: mutationID,
                originDeviceID: originID,
                originSequence: 1,
                payloadDigestHex: "digest",
                envelopeData: Data([1]),
                receivedAt: run.updatedAt
            )
        )
        context.insert(
            PhoneAcknowledgementOutboxRecord(
                acknowledgementID: UUID(),
                mutationID: mutationID,
                originDeviceID: originID,
                canonicalGeneration: 1,
                acknowledgementData: Data([2]),
                createdAt: run.updatedAt
            )
        )
        context.insert(
            PhoneSnapshotReceiptRecord(
                receiptID: UUID(),
                originDeviceID: originID,
                snapshotID: UUID(),
                canonicalGeneration: 1,
                receiptData: Data([3]),
                receivedAt: run.updatedAt
            )
        )
        context.insert(
            PhoneCanonicalSnapshotRecord(
                snapshotID: UUID(),
                canonicalGeneration: 1,
                snapshotData: Data([4]),
                createdAt: run.updatedAt
            )
        )
        let conflictID = UUID()
        context.insert(
            PhoneTimerConflictRecord(
                conflictID: conflictID,
                stateRawValue: PhoneTimerConflictStatus.awaitingPhoneReview.rawValue,
                reasonCodeRawValue: "stale_causal_base",
                canonicalHeadData: Data([5]),
                canonicalSnapshotData: nil,
                involvedRunIDsData: Data([6]),
                involvedSegmentIDsData: Data([7]),
                createdAt: run.updatedAt
            )
        )
        context.insert(
            PhoneConflictMutationRecord(
                recordID: UUID(),
                conflictID: conflictID,
                mutationID: mutationID,
                originDeviceID: originID,
                originSequence: 1,
                envelopeData: Data([8]),
                reconstructedBranchData: nil,
                receivedAt: run.updatedAt
            )
        )
        context.insert(
            PhoneEntityTombstoneRecord(
                tombstoneID: UUID(),
                entityTypeRawValue: "run",
                entityID: run.id,
                canonicalGeneration: 1,
                deletedAt: run.updatedAt,
                conflictID: conflictID
            )
        )
        try context.save()

        try WellSpentLocalDataResetService(context: context).deleteAllUserData()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ProjectRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SessionTagRecord>()), 0)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<SessionTagAssignmentRecord>()),
            0
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<TimerRunTagAssignmentRecord>()),
            0
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerOriginRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneSyncMetadataRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneMutationInboxRecord>()), 0)
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<PhoneAcknowledgementOutboxRecord>()),
            0
        )
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneSnapshotReceiptRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneCanonicalSnapshotRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneTimerConflictRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneConflictMutationRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PhoneEntityTombstoneRecord>()), 0)
    }

    func testOldestShippedFixtureOpensThroughMigrationHarness() throws {
        let fixture = try TemporaryStoreFixture()
        defer { fixture.remove() }

        let fixtureProjectID = UUID()
        let fixtureSessionID = UUID()
        let fixtureSchema = Schema(versionedSchema: WellSpentSchemaV1.self)
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
                WellSpentSchemaV1.ProjectRecord(
                    id: fixtureProjectID,
                    name: "V1 fixture"
                )
            )
            context.insert(
                WellSpentSchemaV1.TimeSessionRecord(
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

        let migratedContainer = try WellSpentPersistence.makePersistentContainer(
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
            .appendingPathComponent("WellSpentPersistenceTests-\(UUID().uuidString)", isDirectory: true)
        storeURL = directoryURL.appendingPathComponent("WellSpent.store")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
