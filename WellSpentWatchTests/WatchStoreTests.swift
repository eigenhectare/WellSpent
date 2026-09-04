import Foundation
import SwiftData
import WellSpentWatchContracts
import XCTest

@testable import WellSpentWatchStore

@MainActor
final class WatchStoreTests: XCTestCase {
    private let originID = UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
    private let projectAID = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
    private let projectBID = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
    private let runID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000001")!
    private let snapshotID = UUID(uuidString: "50000000-0000-0000-0000-000000000001")!
    private let startAt = Date(timeIntervalSince1970: 1_800_000_000)

    func testFreshStorePersistsPrivateOriginAndContractVersion() throws {
        let store = try WellSpentWatchStore.makeInMemory(originDeviceID: originID)

        let state = try store.state()

        XCTAssertEqual(state.originDeviceID, originID)
        XCTAssertEqual(state.nextOriginSequence, 1)
        XCTAssertEqual(state.protocolVersion, WellSpentWatchContract.protocolVersion)
        XCTAssertEqual(state.schemaVersion, WellSpentWatchContract.schemaVersion)
        XCTAssertEqual(state.pendingMutationCount, 0)
        XCTAssertTrue(state.recentProjectIDs.isEmpty)
        XCTAssertFalse(state.isBlocked)
    }

    func testProjectSelectionRecencyIsDurableAndMostRecentFirst() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let store = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL,
                originDeviceID: originID
            )
            try installSetup(on: store)
            try store.recordProjectSelection(projectID: projectAID, selectedAt: startAt)
            try store.recordProjectSelection(
                projectID: projectBID,
                selectedAt: startAt.addingTimeInterval(1)
            )
            try store.recordProjectSelection(
                projectID: projectAID,
                selectedAt: startAt.addingTimeInterval(2)
            )
            XCTAssertEqual(try store.state().recentProjectIDs, [projectAID, projectBID])
        }

        let reopened = try WellSpentWatchStore(
            container: WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            ),
            storeURL: fixture.storeURL
        )
        XCTAssertEqual(try reopened.state().recentProjectIDs, [projectAID, projectBID])
    }

    func testProjectTombstonePrunesRecencyAndPreventsResurrection() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        try store.recordProjectSelection(projectID: projectAID, selectedAt: startAt)

        let tombstone = EntityTombstone(
            entityType: .project,
            entityID: projectAID,
            canonicalGeneration: 11,
            deletedAt: startAt.addingTimeInterval(10)
        )
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(
                fixtureSnapshot(
                    generation: 11,
                    snapshotID: UUID(),
                    tombstones: [tombstone]
                )
            ),
            contradictsPendingMutations: false
        )

        let state = try store.state()
        XCTAssertFalse(state.projection.projects.contains(where: { $0.id == projectAID }))
        XCTAssertFalse(state.recentProjectIDs.contains(projectAID))
        XCTAssertThrowsError(
            try store.recordProjectSelection(
                projectID: projectAID,
                selectedAt: startAt.addingTimeInterval(20)
            )
        ) { error in
            XCTAssertEqual(error as? WatchStoreError, .commandInvalid)
        }
    }

    func testV1StoreMigratesWithAnEmptyRecentProjectList() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }
        let v1Schema = Schema(versionedSchema: WatchStoreSchemaV1.self)

        do {
            let configuration = ModelConfiguration(
                WatchStorePersistence.storeName,
                schema: v1Schema,
                url: fixture.storeURL,
                allowsSave: true,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: v1Schema, configurations: [configuration])
            let context = ModelContext(container)
            context.insert(
                WatchStoreMetadataRecord(
                    originDeviceID: originID,
                    nextOriginSequence: 1,
                    protocolMajor: Int64(WellSpentWatchContract.protocolVersion.major),
                    protocolMinor: Int64(WellSpentWatchContract.protocolVersion.minor),
                    schemaVersion: Int64(WellSpentWatchContract.schemaVersion),
                    projectionData: try ContractWireCodec.encodeCanonical(
                        WatchCachedProjection()
                    ),
                    createdAt: startAt
                )
            )
            try context.save()
        }

        let migrated = try WellSpentWatchStore(
            container: WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            ),
            storeURL: fixture.storeURL
        )
        XCTAssertEqual(try migrated.state().originDeviceID, originID)
        XCTAssertTrue(try migrated.state().recentProjectIDs.isEmpty)
    }

    func testSnapshotInstallPersistsCatalogAndQueuesDurableReceipt() throws {
        let (store, container) = try makeStore()
        let snapshot = fixtureSnapshot()

        let result = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(snapshot),
            contradictsPendingMutations: false
        )

        guard case .installed(let receipt) = result else {
            return XCTFail("Expected snapshot installation")
        }
        let state = try store.state()
        XCTAssertEqual(state.projection.projects.map(\.id), [projectAID, projectBID])
        XCTAssertEqual(state.projection.ledgerHead, snapshot.ledgerHead)
        XCTAssertEqual(state.pendingSnapshotReceiptCount, 1)
        XCTAssertEqual(receipt.originDeviceID, originID)
        XCTAssertEqual(receipt.snapshotID, snapshotID)
        XCTAssertEqual(try store.pendingSnapshotReceipts().first?.receiptData.isEmpty, false)

        let widgetState = try WatchWidgetSnapshotReader(container: container).read()
        XCTAssertEqual(widgetState.timerState, .ready)
        XCTAssertNil(widgetState.projectName)
        XCTAssertTrue(widgetState.pendingSync)
    }

    func testStartPauseResumeAndEndCommitStateWithCausalOutbox() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        try compactSetupReceipt(on: store)
        let resumeSegmentID = UUID(uuidString: "40000000-0000-0000-0000-000000000002")!

        let start = try store.performLocalCommand(
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectAID,
                    durationGoalSeconds: 3_600
                )
            ),
            capturedAt: startAt,
            timeZoneID: "America/New_York"
        )
        let pause = try store.performLocalCommand(
            .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID)),
            capturedAt: startAt.addingTimeInterval(60),
            timeZoneID: "America/New_York"
        )
        let resume = try store.performLocalCommand(
            .resume(ResumeTimerAction(runID: runID, newSegmentID: resumeSegmentID)),
            capturedAt: startAt.addingTimeInterval(120),
            timeZoneID: "America/New_York"
        )
        let end = try store.performLocalCommand(
            .end(EndTimerAction(runID: runID, openSegmentID: resumeSegmentID)),
            capturedAt: startAt.addingTimeInterval(180),
            timeZoneID: "America/New_York"
        )

        let outbox = try store.pendingOutbox()
        XCTAssertEqual(outbox.map(\.originSequence), [1, 2, 3, 4])
        let decoded = try outbox.map { try ContractWireCodec.decodeMutation($0.envelopeData) }
        XCTAssertNil(decoded[0].predecessorMutationID)
        XCTAssertEqual(decoded[1].predecessorMutationID, start.mutation.mutationID)
        XCTAssertEqual(decoded[2].predecessorMutationID, pause.mutation.mutationID)
        XCTAssertEqual(decoded[3].predecessorMutationID, resume.mutation.mutationID)
        XCTAssertEqual(end.mutation.originDeviceID, originID)

        let state = try store.state()
        XCTAssertNil(state.projection.activeRun)
        XCTAssertEqual(state.projection.recentlyEndedRun?.state, .ended)
        XCTAssertEqual(state.projection.recentlyEndedRun?.revision, 4)
        XCTAssertEqual(state.projection.recentlyEndedRunSegments.count, 2)
        XCTAssertEqual(
            state.projection.recentlyEndedRunSegments.compactMap { segment in
                segment.endedAt?.timeIntervalSince(segment.startedAt)
            },
            [60, 60]
        )
        XCTAssertEqual(state.pendingMutationCount, 4)
        XCTAssertEqual(state.nextOriginSequence, 5)
    }

    func testSaveFailureRollsBackRunAndOutboxTogether() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        try compactSetupReceipt(on: store)
        store.setBeforeSaveForTesting { throw InjectedFailure() }

        XCTAssertThrowsError(
            try store.performLocalCommand(
                .start(
                    StartTimerAction(
                        runID: runID,
                        segmentID: segmentID,
                        projectID: projectAID,
                        durationGoalSeconds: nil
                    )
                ),
                capturedAt: startAt,
                timeZoneID: "UTC"
            )
        ) { error in
            XCTAssertEqual(error as? WatchStoreError, .saveFailed)
        }

        store.setBeforeSaveForTesting {}
        let state = try store.state()
        XCTAssertNil(state.projection.activeRun)
        XCTAssertEqual(state.pendingMutationCount, 0)
        XCTAssertEqual(state.nextOriginSequence, 1)
    }

    func testCommittedCommandAndRetryMetadataSurviveContainerRecreation() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }
        let retryAt = startAt.addingTimeInterval(30)
        var mutationID: UUID?

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let store = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL,
                originDeviceID: originID
            )
            try installSetup(on: store)
            try compactSetupReceipt(on: store)
            let commit = try performStart(on: store)
            mutationID = commit.mutation.mutationID
            try store.recordDeliveryAttempt(
                mutationID: commit.mutation.mutationID,
                attemptedAt: startAt.addingTimeInterval(1),
                nextRetryAt: retryAt
            )
        }

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let reopened = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL
            )
            let state = try reopened.state()
            let outbox = try reopened.pendingOutbox()
            XCTAssertEqual(state.originDeviceID, originID)
            XCTAssertEqual(state.projection.activeRun?.id, runID)
            XCTAssertEqual(outbox.first?.mutationID, mutationID)
            XCTAssertEqual(outbox.first?.attemptCount, 1)
            XCTAssertEqual(outbox.first?.nextRetryAt, retryAt)
        }
    }

    func testEndedRunAndItsPendingOutboxSurviveContainerRecreation() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }
        let endedAt = startAt.addingTimeInterval(90)
        var endMutationID: UUID?

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let store = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL,
                originDeviceID: originID
            )
            try installSetup(on: store)
            try compactSetupReceipt(on: store)
            _ = try performStart(on: store)
            let end = try store.performLocalCommand(
                .end(EndTimerAction(runID: runID, openSegmentID: segmentID)),
                capturedAt: endedAt,
                timeZoneID: "UTC"
            )
            endMutationID = end.mutation.mutationID
        }

        let container = try WatchStorePersistence.makePersistentContainer(
            storeURL: fixture.storeURL
        )
        let reopened = try WellSpentWatchStore(
            container: container,
            storeURL: fixture.storeURL
        )
        let state = try reopened.state()
        let outbox = try reopened.pendingOutbox()
        XCTAssertNil(state.projection.activeRun)
        XCTAssertEqual(state.projection.recentlyEndedRun?.id, runID)
        XCTAssertEqual(state.projection.recentlyEndedRun?.endedAt, endedAt)
        XCTAssertEqual(state.projection.recentlyEndedRunSegments.first?.endedAt, endedAt)
        XCTAssertEqual(outbox.count, 2)
        XCTAssertEqual(outbox.last?.mutationID, endMutationID)
    }

    func testEndedRunAnnotationAndPendingOutboxSurviveContainerRecreation() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }
        let endedAt = startAt.addingTimeInterval(90)
        let annotatedAt = endedAt.addingTimeInterval(15)
        var tagID: UUID?
        var annotationMutationID: UUID?

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let store = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL,
                originDeviceID: originID
            )
            try installSetup(on: store)
            try compactSetupReceipt(on: store)
            tagID = try XCTUnwrap(store.state().projection.tags.first?.id)
            _ = try performStart(on: store)
            _ = try store.performLocalCommand(
                .end(EndTimerAction(runID: runID, openSegmentID: segmentID)),
                capturedAt: endedAt,
                timeZoneID: "UTC"
            )
            let annotation = try store.performLocalCommand(
                .annotate(
                    AnnotateTimerAction(
                        runID: runID,
                        normalizedNote: "Prepared court filing",
                        tagIDs: [try XCTUnwrap(tagID)]
                    )
                ),
                capturedAt: annotatedAt,
                timeZoneID: "America/New_York"
            )
            annotationMutationID = annotation.mutation.mutationID
        }

        let container = try WatchStorePersistence.makePersistentContainer(
            storeURL: fixture.storeURL
        )
        let reopened = try WellSpentWatchStore(
            container: container,
            storeURL: fixture.storeURL
        )
        let state = try reopened.state()
        let outbox = try reopened.pendingOutbox()
        XCTAssertNil(state.projection.activeRun)
        XCTAssertEqual(state.projection.recentlyEndedRun?.state, .ended)
        XCTAssertEqual(state.projection.recentlyEndedRun?.endedAt, endedAt)
        XCTAssertEqual(
            state.projection.recentlyEndedRun?.normalizedNote,
            "Prepared court filing"
        )
        XCTAssertEqual(state.projection.recentlyEndedRun?.tagIDs, [try XCTUnwrap(tagID)])
        XCTAssertEqual(state.projection.recentlyEndedRunSegments.first?.endedAt, endedAt)
        XCTAssertEqual(outbox.count, 3)
        XCTAssertEqual(outbox.last?.mutationID, annotationMutationID)
    }

    func testRestartReconstructsPausedPendingAndConflictState() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let store = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL,
                originDeviceID: originID
            )
            try installSetup(on: store)
            try compactSetupReceipt(on: store)
            _ = try performStart(on: store)
            let pause = try store.performLocalCommand(
                .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID)),
                capturedAt: startAt.addingTimeInterval(60),
                timeZoneID: "UTC"
            )
            try store.receiveAcknowledgement(
                acknowledgement(
                    mutationID: pause.mutation.mutationID,
                    originSequence: pause.mutation.originSequence,
                    outcome: .conflict,
                    reason: .observedStateDiverged
                )
            )
        }

        do {
            let container = try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let reopened = try WellSpentWatchStore(
                container: container,
                storeURL: fixture.storeURL
            )
            let state = try reopened.state()
            XCTAssertEqual(state.projection.activeRun?.state, .paused)
            XCTAssertEqual(state.pendingMutationCount, 1)
            XCTAssertEqual(state.quarantinedMutationCount, 1)
            XCTAssertEqual(
                state.blockingReasonCode,
                ContractReasonCode.observedStateDiverged.rawValue
            )
        }
    }

    func testOnlyNamedAppliedAcknowledgementCompactsOutbox() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        try compactSetupReceipt(on: store)
        let commit = try performStart(on: store)
        let unrelated = acknowledgement(
            mutationID: UUID(),
            originSequence: 99,
            outcome: .applied,
            reason: .applied
        )

        try store.receiveAcknowledgement(unrelated)
        XCTAssertEqual(try store.pendingOutbox().count, 1)

        let matching = acknowledgement(
            mutationID: commit.mutation.mutationID,
            originSequence: commit.mutation.originSequence,
            outcome: .applied,
            reason: .applied
        )
        try store.receiveAcknowledgement(matching)
        try store.receiveAcknowledgement(matching)

        XCTAssertEqual(try store.pendingOutbox().count, 0)
        XCTAssertEqual(try store.state().pendingMutationCount, 0)
    }

    func testConflictAcknowledgementQuarantinesExactEnvelopeAndBlocksCommands() throws {
        let (store, container) = try makeStore()
        try installSetup(on: store)
        try compactSetupReceipt(on: store)
        let commit = try performStart(on: store)
        let originalBytes = try XCTUnwrap(store.pendingOutbox().first?.envelopeData)

        try store.receiveAcknowledgement(
            acknowledgement(
                mutationID: commit.mutation.mutationID,
                originSequence: commit.mutation.originSequence,
                outcome: .conflict,
                reason: .staleCausalBase
            )
        )

        let state = try store.state()
        XCTAssertEqual(state.pendingMutationCount, 0)
        XCTAssertEqual(state.quarantinedMutationCount, 1)
        XCTAssertEqual(state.blockingReasonCode, ContractReasonCode.staleCausalBase.rawValue)
        let inspectionContext = ModelContext(container)
        let quarantined = try inspectionContext.fetch(FetchDescriptor<WatchQuarantineRecord>())
        XCTAssertEqual(quarantined.first?.envelopeData, originalBytes)
        XCTAssertThrowsError(
            try store.performLocalCommand(
                .setGoal(SetTimerGoalAction(runID: runID, durationGoalSeconds: 60)),
                capturedAt: startAt.addingTimeInterval(2),
                timeZoneID: "UTC"
            )
        ) { error in
            XCTAssertEqual(error as? WatchStoreError, .blocked)
        }
    }

    func testAcknowledgementIdentityCollisionIsDurableAndKeepsOutbox() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        try compactSetupReceipt(on: store)
        let commit = try performStart(on: store)
        let collision = MutationAcknowledgement(
            acknowledgementID: UUID(),
            mutationID: commit.mutation.mutationID,
            originDeviceID: UUID(),
            originSequence: commit.mutation.originSequence,
            outcome: .applied,
            canonicalSnapshotID: snapshotID,
            canonicalGeneration: 11,
            conflictID: nil,
            reasonCode: .applied,
            acknowledgedAt: startAt.addingTimeInterval(5)
        )

        try store.receiveAcknowledgement(collision)

        XCTAssertEqual(try store.pendingOutbox().count, 1)
        XCTAssertEqual(
            try store.state().blockingReasonCode,
            ContractReasonCode.mutationIdentityCollision.rawValue
        )
    }

    func testCorruptProjectionRecoversFromCanonicalSnapshotAndOutbox() throws {
        let (initialStore, container) = try makeStore()
        var store: WellSpentWatchStore? = initialStore
        try installSetup(on: initialStore)
        try compactSetupReceipt(on: initialStore)
        _ = try performStart(on: initialStore)

        let corruptionContext = ModelContext(container)
        let metadata = try XCTUnwrap(
            corruptionContext.fetch(FetchDescriptor<WatchStoreMetadataRecord>()).first
        )
        metadata.projectionData = Data("not-json".utf8)
        try corruptionContext.save()
        store = nil
        XCTAssertNil(store)

        let recovered = try WellSpentWatchStore(container: container)

        XCTAssertEqual(try recovered.state().projection.activeRun?.id, runID)
        XCTAssertEqual(try recovered.pendingOutbox().count, 1)
        XCTAssertFalse(try recovered.state().isBlocked)
    }

    func testCorruptOutboxIsQuarantinedByteForByteAndBlocksLaterMutation() throws {
        let (initialStore, container) = try makeStore()
        var store: WellSpentWatchStore? = initialStore
        try installSetup(on: initialStore)
        try compactSetupReceipt(on: initialStore)
        _ = try performStart(on: initialStore)
        let corruptBytes = Data([0x00, 0x01, 0x02, 0x03])

        let corruptionContext = ModelContext(container)
        let outbox = try XCTUnwrap(
            corruptionContext.fetch(FetchDescriptor<WatchOutboxRecord>()).first
        )
        outbox.envelopeData = corruptBytes
        try corruptionContext.save()
        store = nil
        XCTAssertNil(store)

        let recovered = try WellSpentWatchStore(container: container)

        let state = try recovered.state()
        XCTAssertTrue(state.isBlocked)
        XCTAssertEqual(state.pendingMutationCount, 0)
        XCTAssertEqual(state.quarantinedMutationCount, 1)
        let inspectionContext = ModelContext(container)
        let quarantine = try inspectionContext.fetch(FetchDescriptor<WatchQuarantineRecord>())
        XCTAssertEqual(quarantine.first?.envelopeData, corruptBytes)
    }

    func testUnsupportedStoredProtocolDoesNotRewriteData() throws {
        let (initialStore, container) = try makeStore()
        var store: WellSpentWatchStore? = initialStore
        let context = ModelContext(container)
        let metadata = try XCTUnwrap(
            context.fetch(FetchDescriptor<WatchStoreMetadataRecord>()).first
        )
        metadata.protocolMajor = 2
        try context.save()
        store = nil
        XCTAssertNil(store)

        XCTAssertThrowsError(try WellSpentWatchStore(container: container)) { error in
            XCTAssertEqual(error as? WatchStoreError, .unsupportedStoreVersion)
        }
        let unchanged = try XCTUnwrap(
            context.fetch(FetchDescriptor<WatchStoreMetadataRecord>()).first
        )
        XCTAssertEqual(unchanged.protocolMajor, 2)
    }

    func testStaleSnapshotIsIgnoredAndContradictionBlocksInstallation() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)

        let stale = fixtureSnapshot(generation: 9, snapshotID: UUID())
        XCTAssertEqual(
            try store.installSnapshotData(
                ContractWireCodec.encodeSnapshot(stale),
                contradictsPendingMutations: false
            ),
            .stale
        )

        let newer = fixtureSnapshot(generation: 11, snapshotID: UUID())
        XCTAssertEqual(
            try store.installSnapshotData(
                ContractWireCodec.encodeSnapshot(newer),
                contradictsPendingMutations: true
            ),
            .reviewRequired(.snapshotContradictsPending)
        )
        XCTAssertTrue(try store.state().isBlocked)
        XCTAssertEqual(try store.state().projection.ledgerHead?.canonicalGeneration, 10)
    }

    func testResolvedSnapshotClearsConflictFreezeAndAppliesTombstones() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        let conflictID = UUID()
        let conflict = TimerConflictSnapshot(
            conflictID: conflictID,
            state: .awaitingPhoneReview,
            reasonCode: .staleCausalBase,
            involvedRunIDs: [runID],
            involvedSegmentIDs: [segmentID]
        )
        let blockedSnapshot = fixtureSnapshot(
            generation: 11,
            snapshotID: UUID(),
            conflict: conflict
        )

        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(blockedSnapshot),
            contradictsPendingMutations: false
        )
        XCTAssertTrue(try store.state().isBlocked)
        XCTAssertEqual(try store.state().projection.conflict?.conflictID, conflictID)

        let resolvedSnapshot = fixtureSnapshot(
            generation: 12,
            snapshotID: UUID(),
            tombstones: [
                EntityTombstone(
                    entityType: .project,
                    entityID: projectBID,
                    canonicalGeneration: 12,
                    deletedAt: startAt
                ),
                EntityTombstone(
                    entityType: .conflictResolution,
                    entityID: conflictID,
                    canonicalGeneration: 12,
                    deletedAt: startAt
                ),
            ]
        )
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(resolvedSnapshot),
            contradictsPendingMutations: false
        )

        let state = try store.state()
        XCTAssertFalse(state.isBlocked)
        XCTAssertNil(state.projection.conflict)
        XCTAssertEqual(state.projection.projects.map(\.id), [projectAID])
        XCTAssertNoThrow(try performStart(on: store))
    }

    func testOversizedCatalogSnapshotFailsWithoutPartialInstallation() throws {
        let (store, _) = try makeStore()
        let oversizedProjects = (0...WatchStoreLimits.maximumProjects).map { index in
            ProjectSnapshot(
                id: UUID(),
                workspaceID: nil,
                name: "Project \(index)",
                colorToken: nil,
                symbolName: nil
            )
        }
        let snapshot = fixtureSnapshot(projects: oversizedProjects)

        XCTAssertThrowsError(
            try store.installSnapshotData(
                ContractWireCodec.encodeSnapshot(snapshot),
                contradictsPendingMutations: false
            )
        ) { error in
            XCTAssertEqual(error as? WatchStoreError, .localCapacityExceeded)
        }

        let state = try store.state()
        XCTAssertNil(state.projection.ledgerHead)
        XCTAssertEqual(state.pendingSnapshotReceiptCount, 0)
    }

    func testEraseAtomicallyClearsRecordsAndRotatesOrigin() throws {
        let (store, _) = try makeStore()
        try installSetup(on: store)
        _ = try performStart(on: store)
        let priorOrigin = try store.state().originDeviceID

        try store.eraseAll()

        let state = try store.state()
        XCTAssertNotEqual(state.originDeviceID, priorOrigin)
        XCTAssertEqual(state.nextOriginSequence, 1)
        XCTAssertEqual(state.pendingMutationCount, 0)
        XCTAssertEqual(state.pendingSnapshotReceiptCount, 0)
        XCTAssertTrue(state.recentProjectIDs.isEmpty)
        XCTAssertTrue(state.projection.projects.isEmpty)
    }

    func testPersistentStoreIsExcludedFromBackup() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }

        let container = try WatchStorePersistence.makePersistentContainer(storeURL: fixture.storeURL)
        _ = try WellSpentWatchStore(
            container: container,
            storeURL: fixture.storeURL,
            originDeviceID: originID
        )

        XCTAssertTrue(try WatchLocalStoragePrivacy.isExcludedFromBackup(fixture.directoryURL))
        XCTAssertTrue(try WatchLocalStoragePrivacy.isExcludedFromBackup(fixture.storeURL))
    }

    func testWidgetReaderKeepsPendingLocalRunAndAppliesNewPrivacyWithoutStaleOverwrite() throws {
        let (store, container) = try makeStore()
        try installSetup(on: store)
        _ = try performStart(on: store)
        let reader = WatchWidgetSnapshotReader(container: container)
        XCTAssertEqual(try reader.read().runID, runID)
        XCTAssertNil(try reader.read().projectName)
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(
                fixtureSnapshot(
                    generation: 11, snapshotID: UUID(), showNames: true)),
            contradictsPendingMutations: false)
        let current = try reader.read()
        XCTAssertEqual(current.runID, runID)
        XCTAssertTrue(current.pendingSync)
        XCTAssertEqual(current.projectName, "Client A")
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(
                fixtureSnapshot(
                    generation: 9, snapshotID: UUID(), showNames: false)),
            contradictsPendingMutations: false)
        XCTAssertEqual(try reader.read(), current)
    }

    func testReadOnlyWidgetOpenDoesNotCreateAStore() throws {
        let fixture = try TemporaryWatchStoreFixture()
        defer { fixture.remove() }
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.storeURL.path))
        XCTAssertThrowsError(
            try WatchStorePersistence.makePersistentContainer(
                storeURL: fixture.storeURL, allowsSave: false))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.storeURL.path))
    }

    private func makeStore() throws -> (WellSpentWatchStore, ModelContainer) {
        let container = try WatchStorePersistence.makeInMemoryContainer()
        return (
            try WellSpentWatchStore(container: container, originDeviceID: originID),
            container
        )
    }

    private func installSetup(on store: WellSpentWatchStore) throws {
        _ = try store.installSnapshotData(
            ContractWireCodec.encodeSnapshot(fixtureSnapshot()),
            contradictsPendingMutations: false
        )
    }

    private func compactSetupReceipt(on store: WellSpentWatchStore) throws {
        let receiptID = try XCTUnwrap(store.pendingSnapshotReceipts().first?.receiptID)
        try store.compactSnapshotReceipt(receiptID: receiptID)
    }

    private func performStart(on store: WellSpentWatchStore) throws -> WatchCommandCommit {
        try store.performLocalCommand(
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectAID,
                    durationGoalSeconds: nil
                )
            ),
            capturedAt: startAt,
            timeZoneID: "UTC"
        )
    }

    private func acknowledgement(
        mutationID: UUID,
        originSequence: UInt64,
        outcome: MutationOutcome,
        reason: ContractReasonCode
    ) -> MutationAcknowledgement {
        MutationAcknowledgement(
            acknowledgementID: UUID(),
            mutationID: mutationID,
            originDeviceID: originID,
            originSequence: originSequence,
            outcome: outcome,
            canonicalSnapshotID: snapshotID,
            canonicalGeneration: 11,
            conflictID: outcome == .conflict ? UUID() : nil,
            reasonCode: reason,
            acknowledgedAt: startAt.addingTimeInterval(5)
        )
    }

    private func fixtureSnapshot(
        generation: UInt64 = 10,
        snapshotID: UUID? = nil,
        projects: [ProjectSnapshot]? = nil,
        tombstones: [EntityTombstone] = [],
        conflict: TimerConflictSnapshot? = nil,
        showNames: Bool? = nil
    ) -> TimerSnapshotEnvelope {
        TimerSnapshotEnvelope(
            capabilities: ContractCapability.allCases,
            ledgerHead: TimerLedgerHead(
                snapshotID: snapshotID ?? self.snapshotID,
                canonicalGeneration: generation,
                activeRunID: nil,
                activeRunRevision: nil,
                headMutationID: nil
            ),
            projects: projects
                ?? [
                    ProjectSnapshot(
                        id: projectAID,
                        workspaceID: nil,
                        name: "Client A",
                        colorToken: "blue",
                        symbolName: "briefcase"
                    ),
                    ProjectSnapshot(
                        id: projectBID,
                        workspaceID: nil,
                        name: "Client B",
                        colorToken: "green",
                        symbolName: "folder"
                    ),
                ],
            tags: [
                TagSnapshot(id: UUID(), workspaceID: nil, name: "Billable")
            ],
            tombstones: tombstones,
            activeRun: nil,
            activeRunSegments: [],
            recentlyEndedRun: nil,
            recentlyEndedRunSegments: [],
            totals: TimerTotalsSnapshot(
                todaySeconds: 1_800,
                weekSeconds: 7_200,
                calculatedAt: startAt,
                calendarTimeZoneID: "America/New_York"
            ),
            conflict: conflict,
            recentAcknowledgements: [],
            receiptWatermarks: [],
            updateGuidance: MinimumAppVersionGuidance(
                minimumPhoneBuild: nil,
                minimumWatchBuild: nil,
                updateRequired: false
            ),
            showProjectNamesOnSystemSurfaces: showNames
        )
    }
}

private struct InjectedFailure: Error {}

private struct TemporaryWatchStoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WellSpentWatchStoreTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = directoryURL.appendingPathComponent("WellSpentWatch.store")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
