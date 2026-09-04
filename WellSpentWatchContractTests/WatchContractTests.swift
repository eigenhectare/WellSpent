import Foundation
import WellSpentWatchContracts
import XCTest

final class WatchContractTests: XCTestCase {
    private let mutationID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let originID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let snapshotID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    private let runID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    private let segmentID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    private let projectID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

    func testGoldenMutationFixtureIsByteStable() throws {
        let encoded = try ContractWireCodec.encodeMutation(fixtureMutation())

        XCTAssertEqual(
            SHA256Digest.hashing(encoded).hex,
            "3a0542539dc0bf320ac0fb4b2e0b235e4b36419d8a50ca4afa4c8260edda79bb"
        )
        XCTAssertEqual(try ContractWireCodec.decodeMutation(encoded), try fixtureMutation())
    }

    func testGoldenSnapshotFixtureIsByteStable() throws {
        let snapshot = fixtureSnapshot()
        let encoded = try ContractWireCodec.encodeSnapshot(snapshot)

        XCTAssertEqual(
            SHA256Digest.hashing(encoded).hex,
            "eb73209c93131e09fbf75807957c8f9821f68c05386f4bccfc3f14b59b4287ed"
        )
        XCTAssertEqual(try ContractWireCodec.decodeSnapshot(encoded), snapshot)
    }

    func testPureSwiftSHA256MatchesPublishedVector() {
        XCTAssertEqual(
            SHA256Digest.hashing(Data("abc".utf8)).hex,
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
    }

    func testUnknownOptionalEnvelopeFieldIsIgnored() throws {
        let encoded = try ContractWireCodec.encodeMutation(fixtureMutation())
        let original = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let extended = original.dropLast() + ",\"futureOptionalHint\":\"ignored\"}"

        XCTAssertEqual(
            try ContractWireCodec.decodeMutation(Data(extended.utf8)),
            try fixtureMutation()
        )
    }

    func testUnsupportedRequiredMajorFailsWithFixedError() throws {
        let encoded = try ContractWireCodec.encodeMutation(
            fixtureMutation(protocolVersion: ContractVersion(major: 2, minor: 0))
        )

        XCTAssertThrowsError(try ContractWireCodec.decodeMutation(encoded)) { error in
            XCTAssertEqual(error as? ContractWireError, .unsupportedProtocol)
        }
    }

    func testUnknownRequiredActionFailsWithFixedError() throws {
        let encoded = try ContractWireCodec.encodeMutation(fixtureMutation())
        let original = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let unknownAction = original.replacingOccurrences(
            of: "\"kind\":\"start\"",
            with: "\"kind\":\"future_action\""
        )

        XCTAssertThrowsError(try ContractWireCodec.decodeMutation(Data(unknownAction.utf8))) {
            error in
            XCTAssertEqual(error as? ContractWireError, .unsupportedAction)
        }
    }

    func testMutationDigestDetectsPayloadTampering() throws {
        let encoded = try ContractWireCodec.encodeMutation(fixtureMutation())
        let original = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        let tampered = original.replacingOccurrences(
            of: "\"durationGoalSeconds\":3600",
            with: "\"durationGoalSeconds\":3601"
        )

        XCTAssertThrowsError(try ContractWireCodec.decodeMutation(Data(tampered.utf8))) { error in
            XCTAssertEqual(error as? ContractWireError, .digestMismatch)
        }
    }

    func testMalformedAndOversizedPayloadsReturnPrivacySafeErrors() {
        for seed in UInt8(0)..<32 {
            let bytes = (0..<64).map { offset in seed &+ UInt8(offset) }
            XCTAssertThrowsError(try ContractWireCodec.decodeMutation(Data(bytes))) { error in
                XCTAssertEqual(error as? ContractWireError, .malformedPayload)
            }
        }

        let oversized = Data(
            repeating: 0,
            count: WellSpentWatchContract.maximumMutationBytes + 1
        )
        XCTAssertThrowsError(try ContractWireCodec.decodeMutation(oversized)) { error in
            XCTAssertEqual(error as? ContractWireError, .payloadTooLarge)
        }
    }

    func testExactMutationDuplicateReturnsStoredOutcome() throws {
        let mutation = try fixtureMutation()
        let head = fixtureHead()
        let record = AppliedMutationRecord(
            mutationID: mutation.mutationID,
            originDeviceID: mutation.originDeviceID,
            originSequence: mutation.originSequence,
            payloadDigest: mutation.payloadDigest,
            outcome: .applied,
            resultingHead: head
        )
        let context = MutationReconciliationContext(
            canonicalHead: head,
            mutationsByID: [mutation.mutationID: record],
            mutationsByOriginSequence: [
                OriginSequenceKey(
                    originDeviceID: mutation.originDeviceID,
                    originSequence: mutation.originSequence
                ): record
            ]
        )

        XCTAssertEqual(TimerMutationReconciler.classify(mutation, in: context), .duplicate(.applied))
    }

    func testMutationIDReuseWithDifferentDigestRequiresReview() throws {
        let mutation = try fixtureMutation()
        let other = try fixtureMutation(
            action: .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: 7_200
                )
            )
        )
        let head = fixtureHead()
        let record = AppliedMutationRecord(
            mutationID: mutation.mutationID,
            originDeviceID: mutation.originDeviceID,
            originSequence: mutation.originSequence,
            payloadDigest: mutation.payloadDigest,
            outcome: .applied,
            resultingHead: head
        )

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                other,
                in: MutationReconciliationContext(
                    canonicalHead: head,
                    mutationsByID: [mutation.mutationID: record]
                )
            ),
            .reviewRequired(.mutationIdentityCollision)
        )
    }

    func testOriginSequenceReuseWithDifferentIdentityRequiresReview() throws {
        let mutation = try fixtureMutation()
        let other = try fixtureMutation(
            mutationID: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        )
        let head = fixtureHead()
        let record = AppliedMutationRecord(
            mutationID: mutation.mutationID,
            originDeviceID: mutation.originDeviceID,
            originSequence: mutation.originSequence,
            payloadDigest: mutation.payloadDigest,
            outcome: .applied,
            resultingHead: head
        )

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                other,
                in: MutationReconciliationContext(
                    canonicalHead: head,
                    mutationsByOriginSequence: [
                        OriginSequenceKey(
                            originDeviceID: mutation.originDeviceID,
                            originSequence: mutation.originSequence
                        ): record
                    ]
                )
            ),
            .reviewRequired(.originSequenceCollision)
        )
    }

    func testFirstOfflineMutationRequiresExactCausalBase() throws {
        let currentHead = fixtureHead(generation: 8)

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                try fixtureMutation(),
                in: MutationReconciliationContext(canonicalHead: currentHead)
            ),
            .reviewRequired(.staleCausalBase)
        )
    }

    func testOfflineSuccessorWaitsForMissingPredecessor() throws {
        let predecessorID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let mutation = try fixtureMutation(
            predecessorMutationID: predecessorID,
            observedRunID: runID,
            observedRunRevision: 9
        )

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                mutation,
                in: MutationReconciliationContext(
                    canonicalHead: fixtureHead(activeRunID: runID, activeRunRevision: 9)
                )
            ),
            .awaitPredecessor(predecessorID)
        )
    }

    func testOfflineSuccessorAppliesOnlyAgainstPredecessorResult() throws {
        let predecessorID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let head = fixtureHead(activeRunID: runID, activeRunRevision: 9)
        let predecessor = AppliedMutationRecord(
            mutationID: predecessorID,
            originDeviceID: originID,
            originSequence: 7,
            payloadDigest: SHA256Digest.hashing(Data("predecessor".utf8)),
            outcome: .applied,
            resultingHead: head
        )
        let mutation = try fixtureMutation(
            predecessorMutationID: predecessorID,
            observedRunID: runID,
            observedRunRevision: 9
        )

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                mutation,
                in: MutationReconciliationContext(
                    canonicalHead: head,
                    mutationsByID: [predecessorID: predecessor]
                )
            ),
            .apply
        )
    }

    func testDivergentObservedRunRequiresReview() throws {
        let mutation = try fixtureMutation(observedRunID: runID, observedRunRevision: 4)

        XCTAssertEqual(
            TimerMutationReconciler.classify(
                mutation,
                in: MutationReconciliationContext(canonicalHead: fixtureHead())
            ),
            .reviewRequired(.observedStateDiverged)
        )
    }

    func testSnapshotOrderingRejectsStaleAndTiedDivergentHeads() {
        let installed = fixtureHead(generation: 7)

        XCTAssertEqual(
            TimerSnapshotReconciler.classify(
                incoming: fixtureHead(generation: 6),
                installed: installed,
                contradictsPendingMutations: false
            ),
            .stale
        )
        XCTAssertEqual(
            TimerSnapshotReconciler.classify(
                incoming: TimerLedgerHead(
                    snapshotID: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
                    canonicalGeneration: 7,
                    activeRunID: nil,
                    activeRunRevision: nil,
                    headMutationID: nil
                ),
                installed: installed,
                contradictsPendingMutations: false
            ),
            .reviewRequired(.snapshotGenerationCollision)
        )
        XCTAssertEqual(
            TimerSnapshotReconciler.classify(
                incoming: fixtureHead(generation: 8),
                installed: installed,
                contradictsPendingMutations: true
            ),
            .reviewRequired(.snapshotContradictsPending)
        )
    }

    func testEveryTimerActionFromAStaleBaseRequiresReviewWithoutClockOrdering() throws {
        let otherRunID = UUID()
        let otherSegmentID = UUID()
        let actions: [TimerMutationAction] = [
            .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            ),
            .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID)),
            .resume(ResumeTimerAction(runID: runID, newSegmentID: otherSegmentID)),
            .switch(
                SwitchTimerAction(
                    fromRunID: runID,
                    openSegmentID: segmentID,
                    toRunID: otherRunID,
                    toSegmentID: otherSegmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            ),
            .end(EndTimerAction(runID: runID, openSegmentID: segmentID)),
            .annotate(AnnotateTimerAction(runID: runID, normalizedNote: "note", tagIDs: [])),
            .setGoal(SetTimerGoalAction(runID: runID, durationGoalSeconds: 1_800)),
        ]

        for (index, action) in actions.enumerated() {
            let mutation = try TimerMutationEnvelope(
                mutationID: UUID(),
                originDeviceID: originID,
                originSequence: UInt64(index + 1),
                capturedAt: Date(timeIntervalSince1970: -10_000 - Double(index)),
                capturedTimeZoneID: "UTC",
                baseSnapshotID: snapshotID,
                baseCanonicalGeneration: 7,
                predecessorMutationID: nil,
                observedRunID: nil,
                observedRunRevision: nil,
                action: action
            )
            XCTAssertEqual(
                TimerMutationReconciler.classify(
                    mutation,
                    in: MutationReconciliationContext(canonicalHead: fixtureHead(generation: 8))
                ),
                .reviewRequired(.staleCausalBase),
                "Action index \(index) must not win by capturedAt"
            )
        }
    }

    func testConflictBranchReconstructionPreservesEveryExactBoundary() throws {
        let base = fixtureSnapshot()
        let start = try TimerMutationEnvelope(
            mutationID: UUID(),
            originDeviceID: originID,
            originSequence: 1,
            capturedAt: Date(timeIntervalSince1970: 100),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: snapshotID,
            baseCanonicalGeneration: 7,
            predecessorMutationID: nil,
            observedRunID: nil,
            observedRunRevision: nil,
            action: .start(
                StartTimerAction(
                    runID: runID,
                    segmentID: segmentID,
                    projectID: projectID,
                    durationGoalSeconds: nil
                )
            )
        )
        let pause = try TimerMutationEnvelope(
            mutationID: UUID(),
            originDeviceID: originID,
            originSequence: 2,
            capturedAt: Date(timeIntervalSince1970: 160),
            capturedTimeZoneID: "UTC",
            baseSnapshotID: snapshotID,
            baseCanonicalGeneration: 7,
            predecessorMutationID: start.mutationID,
            observedRunID: runID,
            observedRunRevision: 1,
            action: .pause(PauseTimerAction(runID: runID, openSegmentID: segmentID))
        )
        let projection = try TimerConflictBranchReconstructor.reconstruct(
            base: base,
            mutations: [pause, start]
        )

        XCTAssertEqual(projection.activeRun?.state, .paused)
        XCTAssertEqual(projection.activeRun?.revision, 2)
        XCTAssertEqual(projection.activeRunSegments.first?.startedAt, start.capturedAt)
        XCTAssertEqual(projection.activeRunSegments.first?.endedAt, pause.capturedAt)
    }

    func testSegmentOrderingUsesStartThenStableID() {
        let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        let laterID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let time = Date(timeIntervalSince1970: 1_700_000_000)
        let unordered = [
            fixtureSegment(id: laterID, startedAt: time.addingTimeInterval(1)),
            fixtureSegment(id: secondID, startedAt: time),
            fixtureSegment(id: firstID, startedAt: time),
        ]

        XCTAssertEqual(
            ContractStableOrdering.segments(unordered).map(\.id),
            [firstID, secondID, laterID]
        )
    }

    private func fixtureMutation(
        protocolVersion: ContractVersion = WellSpentWatchContract.protocolVersion,
        mutationID: UUID? = nil,
        predecessorMutationID: UUID? = nil,
        observedRunID: UUID? = nil,
        observedRunRevision: Int64? = nil,
        action: TimerMutationAction? = nil
    ) throws -> TimerMutationEnvelope {
        try TimerMutationEnvelope(
            protocolVersion: protocolVersion,
            mutationID: mutationID ?? self.mutationID,
            originDeviceID: originID,
            originSequence: 8,
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000.125),
            capturedTimeZoneID: "America/New_York",
            baseSnapshotID: snapshotID,
            baseCanonicalGeneration: 7,
            predecessorMutationID: predecessorMutationID,
            observedRunID: observedRunID,
            observedRunRevision: observedRunRevision,
            action: action
                ?? .start(
                    StartTimerAction(
                        runID: runID,
                        segmentID: segmentID,
                        projectID: projectID,
                        durationGoalSeconds: 3_600
                    )
                )
        )
    }

    private func fixtureHead(
        generation: UInt64 = 7,
        activeRunID: UUID? = nil,
        activeRunRevision: Int64? = nil
    ) -> TimerLedgerHead {
        TimerLedgerHead(
            snapshotID: snapshotID,
            canonicalGeneration: generation,
            activeRunID: activeRunID,
            activeRunRevision: activeRunRevision,
            headMutationID: nil
        )
    }

    private func fixtureSnapshot() -> TimerSnapshotEnvelope {
        TimerSnapshotEnvelope(
            capabilities: [
                .acknowledgements,
                .causalMutationChain,
                .snapshotReceipts,
                .tombstones,
            ],
            ledgerHead: fixtureHead(),
            projects: [
                ProjectSnapshot(
                    id: projectID,
                    workspaceID: nil,
                    name: "Client work",
                    colorToken: "indigo",
                    symbolName: "briefcase"
                )
            ],
            tags: [
                TagSnapshot(
                    id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
                    workspaceID: nil,
                    name: "Billable"
                )
            ],
            tombstones: [],
            activeRun: nil,
            activeRunSegments: [],
            recentlyEndedRun: nil,
            recentlyEndedRunSegments: [],
            totals: TimerTotalsSnapshot(
                todaySeconds: 3_600,
                weekSeconds: 18_000,
                calculatedAt: Date(timeIntervalSince1970: 1_700_000_100.5),
                calendarTimeZoneID: "America/New_York"
            ),
            conflict: nil,
            recentAcknowledgements: [],
            receiptWatermarks: [
                OriginReceiptWatermark(originDeviceID: originID, contiguousSequence: 7)
            ],
            updateGuidance: MinimumAppVersionGuidance(
                minimumPhoneBuild: 2,
                minimumWatchBuild: 2,
                updateRequired: false
            )
        )
    }

    private func fixtureSegment(id: UUID, startedAt: Date) -> TimerSegmentSnapshot {
        TimerSegmentSnapshot(
            id: id,
            runID: runID,
            workspaceID: nil,
            projectID: projectID,
            startedAt: startedAt,
            endedAt: nil,
            startTimeZoneID: "UTC",
            endTimeZoneID: nil,
            revision: 1
        )
    }
}
