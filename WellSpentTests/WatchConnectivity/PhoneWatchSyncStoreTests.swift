import Foundation
import SwiftData
import WatchConnectivity
import WellSpentShared
import WellSpentWatchContracts
import XCTest

@testable import WellSpent

@MainActor
final class PhoneWatchSyncStoreTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private let originID = UUID(uuidString: "10000000-0000-4000-8000-000000000001")!
    private let projectID = UUID(uuidString: "20000000-0000-4000-8000-000000000001")!
    private let runID = UUID(uuidString: "30000000-0000-4000-8000-000000000001")!
    private let segmentID = UUID(uuidString: "40000000-0000-4000-8000-000000000001")!
    private let startMutationID = UUID(uuidString: "50000000-0000-4000-8000-000000000001")!

    func testDuplicateAndLostAcknowledgementApplyMutationExactlyOnce() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.store.makeSnapshot()
        let mutation = try startMutation(head: snapshot.ledgerHead)
        let data = try ContractWireCodec.encodeMutation(mutation)

        let first = try fixture.store.receiveMutationData(data)
        let acknowledgement = try XCTUnwrap(first.acknowledgements.first)
        XCTAssertEqual(acknowledgement.outcome, .applied)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)

        let receipt = SnapshotReceipt(
            receiptID: UUID(),
            originDeviceID: originID,
            snapshotID: acknowledgement.canonicalSnapshotID,
            canonicalGeneration: acknowledgement.canonicalGeneration,
            receivedAt: now
        )
        try fixture.store.receiveSnapshotReceiptData(
            ContractWireCodec.encodeCanonical(receipt)
        )
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 0)

        let redelivery = try fixture.store.receiveMutationData(data)
        XCTAssertEqual(redelivery.acknowledgements, [acknowledgement])
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<TimerRunRecord>()).first?.revision,
            1
        )
    }

    func testReceiveBeforeTerminationResumesWithoutDoubleApply() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.store.makeSnapshot()
        let data = try ContractWireCodec.encodeMutation(
            startMutation(head: snapshot.ledgerHead)
        )
        fixture.store.setAfterInboxReceiptSavedForTesting {
            throw InjectedFailure.afterReceipt
        }

        XCTAssertThrowsError(try fixture.store.receiveMutationData(data))
        XCTAssertEqual(
            try fixture.context.fetchCount(FetchDescriptor<PhoneMutationInboxRecord>()),
            1
        )
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)

        fixture.store.setAfterInboxReceiptSavedForTesting(nil)
        let resumed = try fixture.store.processReceivedInbox()
        XCTAssertEqual(resumed.appliedMutationIDs, [startMutationID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 1)

        let replay = try fixture.store.receiveMutationData(data)
        XCTAssertTrue(replay.appliedMutationIDs.isEmpty)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
    }

    func testDomainAndTerminalReceiptRollbackTogetherOnSaveFailure() throws {
        let fixture = try makeFixture()
        let snapshot = try fixture.store.makeSnapshot()
        let data = try ContractWireCodec.encodeMutation(
            startMutation(head: snapshot.ledgerHead)
        )
        fixture.store.setAfterInboxReceiptSavedForTesting { [store = fixture.store] in
            store.setBeforeSaveForTesting { throw InjectedFailure.terminalSave }
        }

        XCTAssertThrowsError(try fixture.store.receiveMutationData(data))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 0)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<PhoneMutationInboxRecord>()).first?
                .statusRawValue,
            PhoneMutationInboxStatus.received.rawValue
        )

        fixture.store.setAfterInboxReceiptSavedForTesting(nil)
        fixture.store.setBeforeSaveForTesting(nil)
        let resumed = try fixture.store.processReceivedInbox()
        XCTAssertEqual(resumed.appliedMutationIDs, [startMutationID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 1)
    }

    func testDelayedPredecessorUnblocksReorderedPause() throws {
        let fixture = try makeFixture()
        let head = try fixture.store.makeSnapshot().ledgerHead
        let start = try startMutation(head: head)
        let pauseID = UUID(uuidString: "50000000-0000-4000-8000-000000000002")!
        let pause = try TimerMutationEnvelope(
            mutationID: pauseID,
            originDeviceID: originID,
            originSequence: 2,
            capturedAt: now.addingTimeInterval(-60),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: head.snapshotID,
            baseCanonicalGeneration: head.canonicalGeneration,
            predecessorMutationID: startMutationID,
            observedRunID: runID,
            observedRunRevision: 1,
            action: .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID))
        )

        let waiting = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(pause)
        )
        XCTAssertEqual(waiting.waitingMutationIDs, [pauseID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)

        let converged = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(start)
        )
        XCTAssertEqual(Set(converged.appliedMutationIDs), Set([startMutationID, pauseID]))
        let run = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<TimerRunRecord>()).first
        )
        XCTAssertEqual(run.state, .paused)
        XCTAssertEqual(run.revision, 2)
        XCTAssertEqual(try fixture.store.pendingAcknowledgements().count, 2)
    }

    func testSnapshotIsStableBoundedAndAdvancesForCanonicalChange() throws {
        let fixture = try makeFixture()
        let first = try fixture.store.makeSnapshot()
        let second = try fixture.store.makeSnapshot()
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.projects.map(\.id), [projectID])

        _ = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(startMutation(head: first.ledgerHead))
        )
        let changed = try fixture.store.makeSnapshot()
        XCTAssertGreaterThan(changed.ledgerHead.canonicalGeneration, first.ledgerHead.canonicalGeneration)
        XCTAssertEqual(changed.activeRun?.id, runID)
        XCTAssertEqual(changed.activeRunSegments.map(\.id), [segmentID])
        XCTAssertEqual(changed.recentAcknowledgements.map(\.mutationID), [startMutationID])
        XCTAssertLessThanOrEqual(changed.projects.count, 250)
        XCTAssertLessThanOrEqual(changed.tags.count, 250)
        XCTAssertLessThanOrEqual(changed.recentAcknowledgements.count, 128)
    }

    func testCoordinatorUsesDurablePathOfflineAndFastPathWhenReachable() throws {
        let fixture = try makeFixture()
        let head = try fixture.store.makeSnapshot().ledgerHead
        let data = try ContractWireCodec.encodeMutation(startMutation(head: head))
        let session = FakePhoneSession()
        session.reachable = false
        let coordinator = IPhoneWatchConnectivityCoordinator(
            syncStore: fixture.store,
            session: session,
            now: { self.now }
        )
        coordinator.activate()

        coordinator.receiveForTesting(kind: .mutation, data: data)
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertEqual(session.userInfoPackets.compactMap(WatchConnectivityWire.decode).count, 1)
        XCTAssertEqual(session.applicationContexts.count, 1)

        session.reachable = true
        coordinator.receiveForTesting(kind: .mutation, data: data)
        XCTAssertEqual(session.messages.compactMap(WatchConnectivityWire.decode).count, 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
    }

    func testConcurrentStartPreservesCanonicalAndReconstructedWatchBranches() throws {
        let fixture = try makeFixture()
        let conflict = try createConcurrentStartConflict(in: fixture)

        XCTAssertEqual(conflict.acknowledgement.outcome, .conflict)
        XCTAssertEqual(conflict.acknowledgement.reasonCode, .staleCausalBase)
        XCTAssertNotNil(conflict.acknowledgement.conflictID)
        XCTAssertEqual(try fixture.repository.fetchRuns().map(\.id), [conflict.phoneRunID])

        let pending = try XCTUnwrap(fixture.store.pendingConflicts().first)
        XCTAssertEqual(pending.snapshot.conflictID, conflict.acknowledgement.conflictID)
        XCTAssertEqual(
            Set(pending.snapshot.involvedRunIDs),
            Set([conflict.phoneRunID, runID])
        )
        XCTAssertEqual(pending.canonicalSnapshot?.activeRun?.id, conflict.phoneRunID)
        XCTAssertEqual(pending.branches.first?.projection?.activeRun?.id, runID)
        XCTAssertEqual(pending.branches.first?.projection?.activeRunSegments.map(\.id), [segmentID])

        XCTAssertThrowsError(
            try fixture.commands.setGoal(runID: conflict.phoneRunID, durationGoalSeconds: 900)
        ) { error in
            guard case .reviewRequired = error as? TimerRunCommandError else {
                return XCTFail("Expected timer mutation freeze")
            }
        }

        let snapshot = try fixture.store.makeSnapshot()
        XCTAssertEqual(snapshot.conflict?.conflictID, conflict.acknowledgement.conflictID)
        XCTAssertEqual(snapshot.conflict?.state, .awaitingPhoneReview)
    }

    func testLateWatchAnnotationConflictsWithoutOverwritingPhoneEditAndRetryIsDuplicate() throws {
        let fixture = try makeFixture()
        _ = try fixture.commands.start(
            projectID: projectID,
            capturedAt: now.addingTimeInterval(-300),
            timeZoneID: "UTC",
            runID: runID,
            segmentID: segmentID
        )
        _ = try fixture.commands.end(
            runID: runID,
            capturedAt: now.addingTimeInterval(-120),
            timeZoneID: "UTC"
        )
        let watchBase = try fixture.store.makeSnapshot()
        XCTAssertEqual(watchBase.recentlyEndedRun?.id, runID)

        _ = try fixture.commands.annotate(
            runID: runID,
            note: "Phone revision",
            tagIDs: [],
            capturedAt: now.addingTimeInterval(-60),
            timeZoneID: "UTC"
        )
        _ = try fixture.store.makeSnapshot()

        let annotationID = UUID(uuidString: "50000000-0000-4000-8000-000000000016")!
        let mutation = try TimerMutationEnvelope(
            mutationID: annotationID,
            originDeviceID: originID,
            originSequence: 1,
            capturedAt: now.addingTimeInterval(-30),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: watchBase.ledgerHead.snapshotID,
            baseCanonicalGeneration: watchBase.ledgerHead.canonicalGeneration,
            predecessorMutationID: nil,
            observedRunID: nil,
            observedRunRevision: nil,
            action: .annotate(
                AnnotateTimerAction(
                    runID: runID,
                    normalizedNote: "Watch revision",
                    tagIDs: []
                )
            )
        )
        let data = try ContractWireCodec.encodeMutation(mutation)

        let first = try fixture.store.receiveMutationData(data)
        let acknowledgement = try XCTUnwrap(first.acknowledgements.first)
        XCTAssertEqual(acknowledgement.outcome, .conflict)
        XCTAssertEqual(acknowledgement.reasonCode, .staleCausalBase)
        XCTAssertNotNil(acknowledgement.conflictID)
        XCTAssertEqual(try fixture.repository.fetchRun(id: runID)?.note, "Phone revision")

        let retry = try fixture.store.receiveMutationData(data)
        XCTAssertEqual(retry.acknowledgements, [acknowledgement])
        XCTAssertEqual(try fixture.repository.fetchRun(id: runID)?.note, "Phone revision")
        XCTAssertEqual(
            try fixture.context.fetchCount(FetchDescriptor<PhoneTimerConflictRecord>()),
            1
        )
    }

    func testKeepBothResolutionIsAuditableIdempotentAndPreservesExactTotals() throws {
        let fixture = try makeFixture()
        let conflict = try createConcurrentStartConflict(in: fixture)
        _ = try fixture.store.makeSnapshot()
        let conflictID = try XCTUnwrap(conflict.acknowledgement.conflictID)
        let resolutionID = UUID(uuidString: "60000000-0000-4000-8000-000000000001")!
        let watchEnd = now.addingTimeInterval(-30)
        let watchRun = endedContractRun(
            id: runID,
            segmentID: segmentID,
            start: now.addingTimeInterval(-120),
            end: watchEnd,
            originID: originID,
            mutationID: resolutionID
        )
        let payload = ConflictResolutionPayload(
            chosenActiveRunID: conflict.phoneRunID,
            retainedRunIDs: [conflict.phoneRunID],
            replacementRuns: [watchRun.run],
            replacementSegments: [watchRun.segment]
        )

        let resolved = try fixture.store.resolveConflict(
            conflictID: conflictID,
            resolution: payload,
            capturedAt: now,
            timeZoneID: "UTC",
            mutationID: resolutionID
        )
        let replay = try fixture.store.resolveConflict(
            conflictID: conflictID,
            resolution: payload,
            capturedAt: now,
            timeZoneID: "UTC",
            mutationID: resolutionID
        )

        XCTAssertEqual(resolved, replay)
        XCTAssertEqual(Set(try fixture.repository.fetchRuns().map(\.id)), Set([conflict.phoneRunID, runID]))
        let watchSegment = try XCTUnwrap(fixture.repository.fetchSession(id: segmentID))
        XCTAssertEqual(watchSegment.startAt, now.addingTimeInterval(-120))
        XCTAssertEqual(watchSegment.endAt, watchEnd)
        XCTAssertEqual(watchSegment.duration, 90)
        XCTAssertTrue(try fixture.store.pendingConflicts().isEmpty)
        let snapshot = try fixture.store.makeSnapshot()
        XCTAssertNil(snapshot.conflict)
        XCTAssertEqual(snapshot.ledgerHead.activeRunID, conflict.phoneRunID)
        XCTAssertTrue(
            snapshot.tombstones.contains {
                $0.entityType == .conflictResolution && $0.entityID == conflictID
            })

        XCTAssertNoThrow(
            try fixture.commands.setGoal(
                runID: conflict.phoneRunID,
                durationGoalSeconds: 1_800,
                capturedAt: now.addingTimeInterval(1),
                timeZoneID: "UTC"
            )
        )
    }

    func testMergeResolutionSoftDeletesCanonicalUntilWatchCrossesTombstone() throws {
        let fixture = try makeFixture()
        let conflict = try createConcurrentStartConflict(in: fixture)
        _ = try fixture.store.makeSnapshot()
        let conflictID = try XCTUnwrap(conflict.acknowledgement.conflictID)
        let mergedRunID = UUID(uuidString: "70000000-0000-4000-8000-000000000001")!
        let mergedSegmentAID = UUID(uuidString: "71000000-0000-4000-8000-000000000001")!
        let mergedSegmentBID = UUID(uuidString: "71000000-0000-4000-8000-000000000002")!
        let resolutionID = UUID(uuidString: "72000000-0000-4000-8000-000000000001")!
        let mergedStart = now.addingTimeInterval(-180)
        let mergedEnd = now.addingTimeInterval(-20)
        let mergedRun = WellSpentWatchContracts.TimerRunSnapshot(
            id: mergedRunID,
            workspaceID: nil,
            projectID: projectID,
            state: .ended,
            startedAt: mergedStart,
            endedAt: mergedEnd,
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC",
            durationGoalSeconds: nil,
            normalizedNote: nil,
            tagIDs: [],
            originDeviceID: originID,
            revision: 1,
            lastAppliedMutationID: resolutionID,
            createdAt: mergedStart,
            updatedAt: mergedEnd,
            updatedTimeZoneID: "UTC"
        )
        let mergedSegments = [
            TimerSegmentSnapshot(
                id: mergedSegmentAID,
                runID: mergedRunID,
                workspaceID: nil,
                projectID: projectID,
                startedAt: mergedStart,
                endedAt: now.addingTimeInterval(-100),
                startTimeZoneID: "UTC",
                endTimeZoneID: "UTC",
                revision: 1
            ),
            TimerSegmentSnapshot(
                id: mergedSegmentBID,
                runID: mergedRunID,
                workspaceID: nil,
                projectID: projectID,
                startedAt: now.addingTimeInterval(-80),
                endedAt: mergedEnd,
                startTimeZoneID: "UTC",
                endTimeZoneID: "UTC",
                revision: 1
            ),
        ]

        let result = try fixture.store.resolveConflict(
            conflictID: conflictID,
            resolution: ConflictResolutionPayload(
                chosenActiveRunID: nil,
                retainedRunIDs: [],
                replacementRuns: [mergedRun],
                replacementSegments: mergedSegments
            ),
            capturedAt: now,
            timeZoneID: "UTC",
            mutationID: resolutionID
        )
        let resolvedSnapshot = try fixture.store.makeSnapshot()

        XCTAssertEqual(try fixture.repository.fetchRuns().map(\.id), [mergedRunID])
        XCTAssertEqual(
            try fixture.repository.fetchSegments(runID: mergedRunID).compactMap(\.duration),
            [80, 60]
        )
        XCTAssertEqual(
            try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()),
            2,
            "Superseded canonical bytes stay durable until a crossed snapshot receipt"
        )
        XCTAssertTrue(
            resolvedSnapshot.tombstones.contains {
                $0.entityType == .run && $0.entityID == conflict.phoneRunID
            })

        try fixture.store.receiveSnapshotReceiptData(
            ContractWireCodec.encodeCanonical(
                SnapshotReceipt(
                    receiptID: UUID(),
                    originDeviceID: originID,
                    snapshotID: resolvedSnapshot.ledgerHead.snapshotID,
                    canonicalGeneration: result.resultingHead.canonicalGeneration,
                    receivedAt: now.addingTimeInterval(1)
                )
            )
        )
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(try fixture.repository.fetchRuns().map(\.id), [mergedRunID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PhoneTimerConflictRecord>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PhoneConflictMutationRecord>()), 1)
    }

    func testSecondConflictRoundGetsNewIdentityAfterResolution() throws {
        let fixture = try makeFixture()
        let first = try createConcurrentStartConflict(in: fixture)
        let firstID = try XCTUnwrap(first.acknowledgement.conflictID)
        let resolutionID = UUID()
        _ = try fixture.store.resolveConflict(
            conflictID: firstID,
            resolution: ConflictResolutionPayload(
                chosenActiveRunID: first.phoneRunID,
                retainedRunIDs: [first.phoneRunID],
                replacementRuns: [],
                replacementSegments: []
            ),
            capturedAt: now,
            timeZoneID: "UTC",
            mutationID: resolutionID
        )
        let newBase = try fixture.store.makeSnapshot().ledgerHead
        _ = try fixture.commands.setGoal(
            runID: first.phoneRunID,
            durationGoalSeconds: 1_200,
            capturedAt: now.addingTimeInterval(1),
            timeZoneID: "UTC"
        )
        _ = try fixture.store.makeSnapshot()
        let staleGoal = try TimerMutationEnvelope(
            mutationID: UUID(),
            originDeviceID: originID,
            originSequence: 2,
            capturedAt: now.addingTimeInterval(-10_000),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: newBase.snapshotID,
            baseCanonicalGeneration: newBase.canonicalGeneration,
            predecessorMutationID: nil,
            observedRunID: first.phoneRunID,
            observedRunRevision: 1,
            action: .setGoal(
                SetTimerGoalAction(runID: first.phoneRunID, durationGoalSeconds: 900)
            )
        )
        let result = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(staleGoal)
        )
        XCTAssertNotEqual(result.acknowledgements.first?.conflictID, firstID)
        XCTAssertEqual(result.acknowledgements.first?.outcome, .conflict)
    }

    func testOriginSequenceCollisionIsRetainedForReview() throws {
        let fixture = try makeFixture()
        let base = try fixture.store.makeSnapshot().ledgerHead
        _ = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(startMutation(head: base))
        )
        let current = try fixture.store.makeSnapshot().ledgerHead
        let collision = try TimerMutationEnvelope(
            mutationID: UUID(uuidString: "50000000-0000-4000-8000-000000000099")!,
            originDeviceID: originID,
            originSequence: 1,
            capturedAt: now.addingTimeInterval(-30),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: current.snapshotID,
            baseCanonicalGeneration: current.canonicalGeneration,
            predecessorMutationID: nil,
            observedRunID: runID,
            observedRunRevision: 1,
            action: .setGoal(
                SetTimerGoalAction(runID: runID, durationGoalSeconds: 1_800)
            )
        )

        let result = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(collision)
        )

        let acknowledgement = try XCTUnwrap(result.acknowledgements.first)
        XCTAssertEqual(acknowledgement.outcome, .conflict)
        XCTAssertEqual(acknowledgement.reasonCode, .originSequenceCollision)
        XCTAssertNotNil(acknowledgement.conflictID)
        XCTAssertEqual(try fixture.store.pendingConflicts().first?.branches.count, 1)
        XCTAssertEqual(try fixture.repository.fetchRun(id: runID)?.durationGoalSeconds, 3_600)
    }

    func testArchivedProjectProducesTombstoneAndCannotReappearInSnapshot() throws {
        let fixture = try makeFixture()
        _ = try fixture.store.makeSnapshot()
        let project = try XCTUnwrap(
            fixture.context.fetch(FetchDescriptor<ProjectRecord>()).first
        )
        project.status = .archived
        project.updatedAt = now.addingTimeInterval(1)
        try fixture.context.save()

        let snapshot = try fixture.store.makeSnapshot()

        XCTAssertTrue(snapshot.projects.isEmpty)
        XCTAssertTrue(
            snapshot.tombstones.contains {
                $0.entityType == .project && $0.entityID == projectID
            })
    }

    func testSystemPrivacyPreferenceChangesSnapshotGenerationAndDefaultsPrivate() throws {
        var showsNames = false
        let fixture = try makeFixture(showsSystemProjectNames: { showsNames })
        let first = try fixture.store.makeSnapshot()
        XCTAssertEqual(first.showProjectNamesOnSystemSurfaces, false)
        showsNames = true
        let optedIn = try fixture.store.makeSnapshot()
        XCTAssertEqual(optedIn.showProjectNamesOnSystemSurfaces, true)
        XCTAssertGreaterThan(optedIn.ledgerHead.canonicalGeneration, first.ledgerHead.canonicalGeneration)
        XCTAssertEqual(try fixture.store.makeSnapshot().ledgerHead, optedIn.ledgerHead)
        showsNames = false
        let optedOut = try fixture.store.makeSnapshot()
        XCTAssertEqual(optedOut.showProjectNamesOnSystemSurfaces, false)
        XCTAssertGreaterThan(optedOut.ledgerHead.canonicalGeneration, optedIn.ledgerHead.canonicalGeneration)
    }

    private func makeFixture(showsSystemProjectNames: @escaping () -> Bool = { false }) throws -> Fixture {
        let fixedNow = now
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        context.insert(
            ProjectRecord(
                id: projectID,
                name: "Client",
                colorToken: "blue",
                emoji: "briefcase",
                createdAt: now,
                updatedAt: now
            )
        )
        try context.save()
        let dependencies = WellSpentDependencies(
            nowProvider: NowProvider { fixedNow },
            localeProvider: LocaleProvider { Locale(identifier: "en_US") },
            timeZoneProvider: TimeZoneProvider { TimeZone(secondsFromGMT: 0)! },
            calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
            uuidProvider: UUIDProvider { UUID() }
        )
        let repository = SwiftDataTimerRunRepository(context: context)
        let commands = TimerRunCommandService(
            repository: repository,
            dependencies: dependencies
        )
        return Fixture(
            context: context,
            repository: repository,
            commands: commands,
            store: PhoneWatchSyncStore(
                context: context,
                timerRepository: repository,
                timerCommands: commands,
                dependencies: dependencies,
                showsSystemProjectNames: showsSystemProjectNames
            )
        )
    }

    func testPhoneConflictChoicesPreviewAndCommitExactResults() throws {
        for choice in PhoneConflictChoice.allCases {
            let fixture = try makeFixture()
            let conflictIDs = try createConcurrentStartConflict(in: fixture)
            let conflict = try XCTUnwrap(fixture.store.pendingConflicts().first)
            let plan = try PhoneConflictResolutionPlan.make(
                conflict: conflict, runs: fixture.commands.allRuns(), choice: choice,
                branchID: conflict.branches.last?.mutation.mutationID, at: now,
                watchEndAt: now.addingTimeInterval(-30), timeZoneID: "UTC"
            )
            _ = try fixture.store.resolveConflict(
                conflictID: conflict.snapshot.conflictID,
                resolution: plan.payload, capturedAt: plan.capturedAt, mutationID: plan.id)
            let runs = try fixture.commands.allRuns()
            XCTAssertTrue(try fixture.store.pendingConflicts().isEmpty)
            switch choice {
            case .keepPhone:
                XCTAssertEqual(runs.map(\.id), [conflictIDs.phoneRunID])
                XCTAssertEqual(runs.first?.countedDuration(at: now), 180)
            case .useWatch:
                XCTAssertEqual(runs.count, 1)
                XCTAssertEqual(runs.first?.originDeviceID, originID)
                XCTAssertEqual(runs.first?.countedDuration(at: now), 120)
                XCTAssertEqual(runs.first?.id, plan.payload.chosenActiveRunID)
            case .keepBoth:
                XCTAssertEqual(runs.count, 2)
                XCTAssertEqual(runs.reduce(0) { $0 + $1.countedDuration(at: now) }, 270)
                XCTAssertEqual(plan.payload.chosenActiveRunID, conflictIDs.phoneRunID)
                XCTAssertEqual(runs.first(where: { $0.originDeviceID == originID })?.endAt, now.addingTimeInterval(-30))
            }
        }
    }

    func testConflictPreviewRejectsInvalidWatchBoundaryAndMissingBranch() throws {
        let fixture = try makeFixture()
        _ = try createConcurrentStartConflict(in: fixture)
        let conflict = try XCTUnwrap(fixture.store.pendingConflicts().first)
        for end in [now.addingTimeInterval(-121), now.addingTimeInterval(1)] {
            XCTAssertThrowsError(
                try PhoneConflictResolutionPlan.make(
                    conflict: conflict, runs: fixture.commands.allRuns(), choice: .keepBoth,
                    branchID: conflict.branches.last?.mutation.mutationID, at: now,
                    watchEndAt: end, timeZoneID: "UTC"))
        }
        XCTAssertThrowsError(
            try PhoneConflictResolutionPlan.make(
                conflict: conflict, runs: fixture.commands.allRuns(), choice: .useWatch,
                branchID: UUID(), at: now, watchEndAt: now, timeZoneID: "UTC"))
        XCTAssertEqual(try fixture.store.pendingConflicts().count, 1)
    }

    func testResolutionSaveFailureLeavesBothBranchesAndCanRetrySamePreview() throws {
        let fixture = try makeFixture()
        _ = try createConcurrentStartConflict(in: fixture)
        let conflict = try XCTUnwrap(fixture.store.pendingConflicts().first)
        let plan = try PhoneConflictResolutionPlan.make(
            conflict: conflict, runs: fixture.commands.allRuns(), choice: .keepBoth,
            branchID: conflict.branches.last?.mutation.mutationID, at: now,
            watchEndAt: now, timeZoneID: "UTC")
        fixture.store.setBeforeSaveForTesting { throw InjectedFailure.terminalSave }
        XCTAssertThrowsError(
            try fixture.store.resolveConflict(
                conflictID: conflict.snapshot.conflictID,
                resolution: plan.payload, mutationID: plan.id))
        XCTAssertEqual(try fixture.store.pendingConflicts(), [conflict])
        XCTAssertEqual(try fixture.commands.allRuns().count, 1)
        fixture.store.setBeforeSaveForTesting(nil)
        _ = try fixture.store.resolveConflict(
            conflictID: conflict.snapshot.conflictID,
            resolution: plan.payload, mutationID: plan.id)
        XCTAssertEqual(try fixture.commands.allRuns().count, 2)
    }

    func testSyncOverviewWaitsForReceiptAndTracksOfflinePhoneEdits() throws {
        let fixture = try makeFixture()
        XCTAssertFalse(try fixture.store.syncOverview().hasWatchHistory)
        let base = try fixture.store.makeSnapshot()
        _ = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(startMutation(head: base.ledgerHead)))
        XCTAssertEqual(try fixture.store.syncOverview().pendingAcknowledgements, 1)
        let snapshot = try fixture.store.makeSnapshot()
        try fixture.store.receiveSnapshotReceiptData(
            ContractWireCodec.encodeCanonical(
                SnapshotReceipt(
                    receiptID: UUID(), originDeviceID: originID, snapshotID: snapshot.ledgerHead.snapshotID,
                    canonicalGeneration: snapshot.ledgerHead.canonicalGeneration, receivedAt: now)))
        XCTAssertFalse(try fixture.store.syncOverview().awaitingSnapshotReceipt)
        _ = try fixture.commands.pause(runID: runID, capturedAt: now)
        XCTAssertTrue(try fixture.store.syncOverview().awaitingSnapshotReceipt)
        XCTAssertTrue(try fixture.store.syncOverview().watchOriginIDs.contains(originID))
    }

    func testEraseRejectsDelayedWatchContentAndKeepsGenerationMonotonic() throws {
        let fixture = try makeFixture()
        let base = try fixture.store.makeSnapshot()
        let data = try ContractWireCodec.encodeMutation(startMutation(head: base.ledgerHead))
        _ = try fixture.store.receiveMutationData(data)
        let before = try fixture.store.makeSnapshot().ledgerHead.canonicalGeneration
        try WellSpentLocalDataResetService(context: fixture.context).deleteAllUserData()
        let after = try fixture.store.makeSnapshot()
        XCTAssertGreaterThan(after.ledgerHead.canonicalGeneration, before)
        XCTAssertTrue(after.projects.isEmpty)
        for _ in 0..<2 {
            let result = try fixture.store.receiveMutationData(data)
            XCTAssertEqual(result.acknowledgements.first?.outcome, .invalid)
        }
        XCTAssertTrue(try fixture.commands.allRuns().isEmpty)
        XCTAssertTrue(try fixture.store.pendingConflicts().isEmpty)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<PhoneMutationInboxRecord>()), 0)
        try WellSpentLocalDataResetService(context: fixture.context).deleteAllUserData()
        XCTAssertGreaterThan(
            try fixture.store.makeSnapshot().ledgerHead.canonicalGeneration, after.ledgerHead.canonicalGeneration)
    }

    func testWatchReviewLinksAreStrictAndCarryOnlyConflictIdentity() {
        let id = UUID()
        XCTAssertEqual(WatchReviewLink.conflictID(from: WatchReviewLink.url(conflictID: id)), id)
        XCTAssertNil(WatchReviewLink.conflictID(from: URL(string: "https://review/\(id)")!))
        XCTAssertNil(WatchReviewLink.conflictID(from: URL(string: "wellspent://review/\(id)/extra")!))
    }

    func testPhoneModelResumesSwitchesAndEndsPausedWatchRunThroughJournal() async throws {
        for operation in ["resume", "switch", "end"] {
            let fixture = try makeFixture()
            let base = try fixture.store.makeSnapshot()
            _ = try fixture.store.receiveMutationData(
                ContractWireCodec.encodeMutation(startMutation(head: base.ledgerHead)))
            _ = try fixture.commands.pause(runID: runID, capturedAt: now.addingTimeInterval(-60))
            let lifecycle = CompanionTestLiveActivity()
            let model = WellSpentAppModel(
                modelContainer: fixture.context.container, dependencies: DependencyFixtures.fixed(now: now),
                startupReconciliation: try fixture.commands.reconcileActiveState(), liveActivityLifecycle: lifecycle,
                makeWatchConnectivity: DependencyFixtures.disconnectedWatch)
            XCTAssertTrue(model.isWatchOrigin(try XCTUnwrap(model.activeRun)))
            XCTAssertEqual(model.activeRun?.countedDuration(at: .now), 60)
            if operation == "resume" {
                await model.resumeActiveTimer()
                XCTAssertEqual(model.activeRun?.id, runID)
                XCTAssertEqual(model.activeRun?.segments.count, 2)
                XCTAssertEqual(lifecycle.lastProjection?.sessionID, runID)
            } else if operation == "switch" {
                let project = ProjectRecord(name: "Next project")
                fixture.context.insert(project)
                try fixture.context.save()
                model.refresh()
                await model.startOrSwitch(to: project.id)
                XCTAssertEqual(model.activeRun?.projectID, project.id)
                XCTAssertEqual(model.run(id: runID)?.countedDuration(at: .now), 60)
                XCTAssertEqual(model.completionRoute?.sessionID, runID)
            } else {
                await model.stopActiveTimer()
                XCTAssertNil(model.activeRun)
                XCTAssertEqual(model.run(id: runID)?.countedDuration(at: .now), 60)
                XCTAssertEqual(model.completionRoute?.sessionID, runID)
            }
        }
    }

    func testPhoneConflictDeepLinkFreezesCommandsAndRejectsChangedPreview() async throws {
        let fixture = try makeFixture()
        _ = try createConcurrentStartConflict(in: fixture)
        let conflict = try XCTUnwrap(fixture.store.pendingConflicts().first)
        let lifecycle = CompanionTestLiveActivity()
        let model = WellSpentAppModel(
            modelContainer: fixture.context.container, dependencies: DependencyFixtures.fixed(now: now),
            startupReconciliation: try fixture.commands.reconcileActiveState(),
            liveActivityLifecycle: lifecycle, makeWatchConnectivity: DependencyFixtures.disconnectedWatch)
        await model.handle(url: WatchReviewLink.url(conflictID: conflict.snapshot.conflictID))
        XCTAssertEqual(model.conflictReviewRoute?.id, conflict.snapshot.conflictID)
        XCTAssertTrue(model.timerCommandsBlocked)
        let frozen = try XCTUnwrap(lifecycle.lastProjection?.contentState)
        XCTAssertEqual(frozen.requiresReview, true)
        XCTAssertFalse(frozen.canStop)
        XCTAssertNil(frozen.projectName)
        let frozenCount = frozen.countedSeconds
        model.refresh()
        XCTAssertEqual(lifecycle.lastProjection?.contentState.countedSeconds, frozenCount)
        XCTAssertEqual(frozen.destinationURL(runID: UUID()), WellSpentDeepLink.trackerURL)
        let before = model.runs
        await model.startOrSwitch(to: projectID)
        XCTAssertEqual(model.runs, before)
        let plan = try PhoneConflictResolutionPlan.make(
            conflict: conflict, runs: before, choice: .keepPhone,
            branchID: nil, at: now, watchEndAt: now, timeZoneID: "UTC")
        _ = try fixture.store.resolveConflict(
            conflictID: conflict.snapshot.conflictID,
            resolution: plan.payload, mutationID: UUID())
        let error = await model.resolveWatchConflict(plan)
        XCTAssertNotNil(error)
    }

    func testWatchReceiptPublishesPersistedRunAndPendingConfirmationThenClearsIt() async throws {
        let fixture = try makeFixture()
        let secondProjectID = UUID()
        fixture.context.insert(ProjectRecord(id: secondProjectID, name: "Next client"))
        try fixture.context.save()
        let lifecycle = CompanionTestLiveActivity()
        let session = FakePhoneSession()
        var syncStore: PhoneWatchSyncStore?
        var coordinator: IPhoneWatchConnectivityCoordinator?
        let suite = "WAT21.WatchReceipt.\(UUID())"
        defer { try? WellSpentStopHandoff.clear(suiteName: suite) }
        let model = WellSpentAppModel(
            modelContainer: fixture.context.container,
            dependencies: DependencyFixtures.fixed(now: now), startupReconciliation: .noActiveRun,
            liveActivityLifecycle: lifecycle, stopHandoffSuiteName: suite, foregroundHandoffPollDelays: [],
            makeWatchConnectivity: { store in
                syncStore = store
                let value = IPhoneWatchConnectivityCoordinator(syncStore: store, session: session, now: { self.now })
                coordinator = value
                return value
            })
        model.activateWatchConnectivity()
        let store = try XCTUnwrap(syncStore)
        let transport = try XCTUnwrap(coordinator)
        let base = try store.makeSnapshot()
        let data = try ContractWireCodec.encodeMutation(startMutation(head: base.ledgerHead))

        transport.receiveForTesting(kind: .mutation, data: data)

        XCTAssertEqual(model.activeRun?.id, runID)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        XCTAssertEqual(lifecycle.lastProjection?.sessionID, runID)
        XCTAssertEqual(lifecycle.lastProjection?.revision, model.activeRun?.revision)
        XCTAssertEqual(lifecycle.lastProjection?.contentState.watchConfirmationPending, true)
        XCTAssertNil(lifecycle.lastProjection?.contentState.projectName)
        // At-least-once delivery cannot create another local run or Activity.
        transport.receiveForTesting(kind: .mutation, data: data)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 1)
        let latest = try store.makeSnapshot()
        transport.receiveForTesting(
            kind: .snapshotReceipt,
            data: try ContractWireCodec.encodeCanonical(
                SnapshotReceipt(
                    receiptID: UUID(), originDeviceID: originID, snapshotID: latest.ledgerHead.snapshotID,
                    canonicalGeneration: latest.ledgerHead.canonicalGeneration, receivedAt: now)))
        await model.retryLiveActivityProjection()
        XCTAssertEqual(lifecycle.lastProjection?.contentState.watchConfirmationPending, false)
        XCTAssertEqual(model.activeRun?.id, runID)

        let resumedSegmentID = UUID()
        let switchedRunID = UUID()
        let switchedSegmentID = UUID()
        let actions: [TimerMutationAction] = [
            .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID)),
            .resume(ResumeTimerAction(runID: runID, newSegmentID: resumedSegmentID)),
            .switch(
                SwitchTimerAction(
                    fromRunID: runID, openSegmentID: resumedSegmentID,
                    toRunID: switchedRunID, toSegmentID: switchedSegmentID,
                    projectID: secondProjectID, durationGoalSeconds: nil)),
            .end(EndTimerAction(runID: switchedRunID, openSegmentID: switchedSegmentID)),
        ]
        let offsets: [TimeInterval] = [-90, -60, -30, -10]
        for (index, action) in actions.enumerated() {
            let head = try store.makeSnapshot().ledgerHead
            let current = try XCTUnwrap(model.activeRun)
            let mutation = try TimerMutationEnvelope(
                mutationID: UUID(), originDeviceID: originID, originSequence: UInt64(index + 2),
                capturedAt: now.addingTimeInterval(offsets[index]), capturedTimeZoneID: "UTC",
                baseSnapshotID: head.snapshotID, baseCanonicalGeneration: head.canonicalGeneration,
                // This fixture receives a fresh canonical snapshot before each
                // action; it is not an offline child of the original base.
                predecessorMutationID: nil, observedRunID: current.id,
                observedRunRevision: current.revision, action: action)
            transport.receiveForTesting(kind: .mutation, data: try ContractWireCodec.encodeMutation(mutation))
            XCTAssertTrue(model.pendingWatchConflicts.isEmpty)
            XCTAssertEqual(lifecycle.lastProjection?.sessionID, model.activeRun?.id)
            XCTAssertEqual(lifecycle.lastProjection?.revision, model.activeRun?.revision)
            if index == 0 {
                XCTAssertEqual(lifecycle.lastProjection?.phase, .paused)
                XCTAssertEqual(lifecycle.lastProjection?.countedSeconds, 30)
            }
            if index == 1 { XCTAssertEqual(lifecycle.lastProjection?.phase, .running) }
        }
        await model.retryLiveActivityProjection()
        XCTAssertNil(model.activeRun)
        XCTAssertNil(lifecycle.lastProjection)
        let final = try XCTUnwrap(lifecycle.desired.completed.first { $0.sessionID == switchedRunID })
        XCTAssertEqual(final.phase, .ended)
        XCTAssertEqual(final.countedSeconds, 20)
        XCTAssertEqual(model.run(id: runID)?.countedDuration(at: now), 60)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimerRunRecord>()), 2)
    }

    private func createConcurrentStartConflict(in fixture: Fixture) throws
        -> ConcurrentStartConflict
    {
        let base = try fixture.store.makeSnapshot().ledgerHead
        let phoneRunID = UUID(uuidString: "30000000-0000-4000-8000-000000000099")!
        _ = try fixture.commands.start(
            projectID: projectID,
            capturedAt: now.addingTimeInterval(-180),
            timeZoneID: "UTC",
            runID: phoneRunID,
            segmentID: UUID(uuidString: "40000000-0000-4000-8000-000000000099")!
        )
        _ = try fixture.store.makeSnapshot()
        let result = try fixture.store.receiveMutationData(
            ContractWireCodec.encodeMutation(startMutation(head: base))
        )
        return ConcurrentStartConflict(
            phoneRunID: phoneRunID,
            acknowledgement: try XCTUnwrap(result.acknowledgements.first)
        )
    }

    private func endedContractRun(
        id: UUID,
        segmentID: UUID,
        start: Date,
        end: Date,
        originID: UUID,
        mutationID: UUID
    ) -> (run: WellSpentWatchContracts.TimerRunSnapshot, segment: TimerSegmentSnapshot) {
        (
            WellSpentWatchContracts.TimerRunSnapshot(
                id: id,
                workspaceID: nil,
                projectID: projectID,
                state: .ended,
                startedAt: start,
                endedAt: end,
                startTimeZoneID: "UTC",
                endTimeZoneID: "UTC",
                durationGoalSeconds: nil,
                normalizedNote: nil,
                tagIDs: [],
                originDeviceID: originID,
                revision: 2,
                lastAppliedMutationID: mutationID,
                createdAt: start,
                updatedAt: end,
                updatedTimeZoneID: "UTC"
            ),
            TimerSegmentSnapshot(
                id: segmentID,
                runID: id,
                workspaceID: nil,
                projectID: projectID,
                startedAt: start,
                endedAt: end,
                startTimeZoneID: "UTC",
                endTimeZoneID: "UTC",
                revision: 2
            )
        )
    }

    private func startMutation(head: TimerLedgerHead) throws -> TimerMutationEnvelope {
        try TimerMutationEnvelope(
            mutationID: startMutationID,
            originDeviceID: originID,
            originSequence: 1,
            capturedAt: now.addingTimeInterval(-120),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: head.snapshotID,
            baseCanonicalGeneration: head.canonicalGeneration,
            predecessorMutationID: nil,
            observedRunID: nil,
            observedRunRevision: nil,
            action: .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: 3_600
                )
            )
        )
    }
}

private struct Fixture {
    let context: ModelContext
    let repository: SwiftDataTimerRunRepository
    let commands: TimerRunCommandService
    let store: PhoneWatchSyncStore
}

private struct ConcurrentStartConflict {
    let phoneRunID: UUID
    let acknowledgement: MutationAcknowledgement
}

private enum InjectedFailure: Error {
    case afterReceipt
    case terminalSave
}

@MainActor
private final class CompanionTestLiveActivity: LiveActivityLifecycle {
    let activitiesEnabled = true
    var lastProjection: LiveActivityProjection?
    var desired = LiveActivityDesiredState(active: nil)
    func setDesiredState(_ state: LiveActivityDesiredState) {
        lastProjection = state.active
        desired = state
    }
    func reconcile() async throws {}
}

@MainActor
private final class FakePhoneSession: IPhoneWatchConnectivitySession {
    var activationState: WCSessionActivationState = .notActivated
    var isPaired = true
    var isWatchAppInstalled = true
    var reachable = false
    var isReachable: Bool { reachable }
    var outstandingUserInfoPackets: [[String: Any]] = []
    var messages: [[String: Any]] = []
    var userInfoPackets: [[String: Any]] = []
    var applicationContexts: [[String: Any]] = []

    func configure(delegate: any WCSessionDelegate) {}

    func activate() {
        activationState = .activated
    }

    func sendMessage(
        _ message: [String: Any],
        errorHandler: (@Sendable (any Error) -> Void)?
    ) {
        messages.append(message)
    }

    func queueUserInfo(_ userInfo: [String: Any]) {
        userInfoPackets.append(userInfo)
        outstandingUserInfoPackets.append(userInfo)
    }

    func publishApplicationContext(_ applicationContext: [String: Any]) throws {
        applicationContexts.append(applicationContext)
    }
}
