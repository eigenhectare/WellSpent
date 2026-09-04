import Foundation

enum SpikeReductionError: Error, Equatable {
    case mutationBlocked
    case invalidLocalState
}

enum SpikeWatchReducer {
    static func makeNextMutation(
        state: inout SpikePersistentState,
        now: Date,
        timeZoneID: String,
        makeUUID: () -> UUID
    ) throws -> SpikeMutationEnvelope {
        guard !state.mutationBlocked else {
            throw SpikeReductionError.mutationBlocked
        }

        let action: SpikeAction
        switch (state.localRunID, state.localRunState) {
        case (nil, nil):
            let runID = makeUUID()
            let segmentID = makeUUID()
            action = SpikeAction(
                kind: .start,
                runID: runID,
                segmentID: segmentID,
                projectID: Self.syntheticProjectID
            )
        case (let runID?, .running?):
            action = SpikeAction(
                kind: .pause,
                runID: runID,
                segmentID: state.localOpenSegmentID,
                projectID: nil
            )
        case (let runID?, .paused?):
            action = SpikeAction(
                kind: .resume,
                runID: runID,
                segmentID: makeUUID(),
                projectID: nil
            )
        default:
            throw SpikeReductionError.invalidLocalState
        }

        return try makeAndApply(
            action: action,
            state: &state,
            now: now,
            timeZoneID: timeZoneID,
            makeUUID: makeUUID
        )
    }

    static func makeEndMutation(
        state: inout SpikePersistentState,
        now: Date,
        timeZoneID: String,
        makeUUID: () -> UUID
    ) throws -> SpikeMutationEnvelope {
        guard !state.mutationBlocked else {
            throw SpikeReductionError.mutationBlocked
        }
        guard let runID = state.localRunID, state.localRunState != nil else {
            throw SpikeReductionError.invalidLocalState
        }
        return try makeAndApply(
            action: SpikeAction(
                kind: .end,
                runID: runID,
                segmentID: state.localOpenSegmentID,
                projectID: nil
            ),
            state: &state,
            now: now,
            timeZoneID: timeZoneID,
            makeUUID: makeUUID
        )
    }

    static func install(
        acknowledgement: SpikeMutationAcknowledgement,
        state: inout SpikePersistentState
    ) {
        guard !state.acknowledgements.contains(where: {
            $0.acknowledgementID == acknowledgement.acknowledgementID
        }) else { return }

        state.acknowledgements.append(acknowledgement)
        if acknowledgement.outcome.blocksMutation {
            state.mutationBlocked = true
            if let index = state.outbox.firstIndex(where: {
                $0.payload.mutationID == acknowledgement.mutationID
            }) {
                state.quarantinedOutbox.append(state.outbox.remove(at: index))
            }
        } else {
            state.outbox.removeAll {
                $0.payload.mutationID == acknowledgement.mutationID
            }
        }
        state.queuedMutationIDs.remove(acknowledgement.mutationID)
    }

    static func install(
        snapshot: SpikeSnapshot,
        state: inout SpikePersistentState
    ) -> Bool {
        if let installed = state.installedSnapshot,
            snapshot.canonicalGeneration <= installed.canonicalGeneration
        {
            return snapshot.snapshotID == installed.snapshotID
        }

        state.installedSnapshot = snapshot
        if state.outbox.isEmpty && snapshot.headMutationID == state.lastLocalMutationID {
            state.lastLocalMutationID = nil
        }
        if state.outbox.isEmpty && !state.mutationBlocked {
            state.localRunID = snapshot.activeRunID
            state.localRunRevision = snapshot.activeRunRevision
            state.localRunState = snapshot.activeRunState
            state.localOpenSegmentID = snapshot.openSegmentID
        }
        if snapshot.pendingConflictID != nil {
            state.mutationBlocked = true
        }
        return true
    }

    private static let syntheticProjectID = UUID(
        uuidString: "50000000-0000-4000-8000-000000000001"
    )!

    private static func makeAndApply(
        action: SpikeAction,
        state: inout SpikePersistentState,
        now: Date,
        timeZoneID: String,
        makeUUID: () -> UUID
    ) throws -> SpikeMutationEnvelope {
        let installed = state.installedSnapshot
        let payload = SpikeMutationPayload(
            mutationID: makeUUID(),
            originDeviceID: state.originDeviceID,
            originSequence: state.nextOriginSequence,
            capturedAt: now,
            capturedTimeZoneID: timeZoneID,
            baseSnapshotID: installed?.snapshotID,
            baseCanonicalGeneration: installed?.canonicalGeneration ?? 0,
            predecessorMutationID: state.lastLocalMutationID,
            observedRunID: state.localRunID,
            observedRunRevision: state.localRunRevision,
            action: action
        )
        let envelope = try SpikeMutationEnvelope(payload: payload)

        switch action.kind {
        case .start:
            guard state.localRunID == nil, let segmentID = action.segmentID else {
                throw SpikeReductionError.invalidLocalState
            }
            state.localRunID = action.runID
            state.localRunRevision = 1
            state.localRunState = .running
            state.localOpenSegmentID = segmentID
        case .pause:
            guard state.localRunID == action.runID, state.localRunState == .running else {
                throw SpikeReductionError.invalidLocalState
            }
            state.localRunRevision = (state.localRunRevision ?? 0) + 1
            state.localRunState = .paused
            state.localOpenSegmentID = nil
        case .resume:
            guard state.localRunID == action.runID, state.localRunState == .paused,
                let segmentID = action.segmentID
            else {
                throw SpikeReductionError.invalidLocalState
            }
            state.localRunRevision = (state.localRunRevision ?? 0) + 1
            state.localRunState = .running
            state.localOpenSegmentID = segmentID
        case .end:
            guard state.localRunID == action.runID, state.localRunState != nil else {
                throw SpikeReductionError.invalidLocalState
            }
            state.localRunID = nil
            state.localRunRevision = nil
            state.localRunState = nil
            state.localOpenSegmentID = nil
        }

        state.nextOriginSequence += 1
        state.outbox.append(envelope)
        state.lastLocalMutationID = envelope.payload.mutationID
        return envelope
    }
}

enum SpikePhoneReducer {
    static func receive(
        envelope: SpikeMutationEnvelope,
        transport: SpikeTransportKind,
        state: inout SpikePersistentState,
        now: Date
    ) -> SpikeMutationAcknowledgement? {
        if let receipt = state.inbox.first(where: { $0.id == envelope.payload.mutationID }),
            let acknowledgement = receipt.acknowledgement
        {
            return acknowledgement
        }

        state.inbox.append(
            SpikeInboxReceipt(
                envelope: envelope,
                status: .received,
                acknowledgement: nil,
                receivedAt: now,
                receivedTransport: transport
            )
        )
        return nil
    }

    static func processReceived(
        mutationID: UUID,
        state: inout SpikePersistentState,
        now: Date,
        makeUUID: () -> UUID
    ) -> SpikeMutationAcknowledgement? {
        guard let index = state.inbox.firstIndex(where: { $0.id == mutationID }) else {
            return nil
        }
        if let acknowledgement = state.inbox[index].acknowledgement {
            return acknowledgement
        }

        let envelope = state.inbox[index].envelope
        if let predecessor = envelope.payload.predecessorMutationID {
            guard let predecessorReceipt = state.inbox.first(where: { $0.id == predecessor }) else {
                return nil
            }
            guard let predecessorOutcome = predecessorReceipt.acknowledgement?.outcome else {
                return nil
            }
            guard predecessorOutcome == .applied || predecessorOutcome == .duplicate else {
                return finishWithoutApplying(
                    index: index,
                    envelope: envelope,
                    outcome: .conflict,
                    reasonCode: "rejected_predecessor",
                    state: &state,
                    now: now,
                    makeUUID: makeUUID
                )
            }
        }
        let outcome = evaluate(envelope: envelope, state: state)
        let applied = outcome.outcome == .applied
        if applied {
            apply(envelope.payload.action, state: &state)
            state.canonicalSnapshot = SpikeSnapshot(
                protocolMajor: SpikeMutationPayload.protocolMajor,
                protocolMinor: SpikeMutationPayload.protocolMinor,
                schemaVersion: SpikeMutationPayload.schemaVersion,
                snapshotID: makeUUID(),
                canonicalGeneration: state.canonicalSnapshot.canonicalGeneration + 1,
                activeRunID: state.localRunID,
                activeRunRevision: state.localRunRevision,
                activeRunState: state.localRunState,
                openSegmentID: state.localOpenSegmentID,
                headMutationID: envelope.payload.mutationID,
                pendingConflictID: nil,
                producedAt: now
            )
        }

        let conflictID = outcome.outcome == .conflict ? makeUUID() : nil
        if let conflictID {
            state.mutationBlocked = true
            state.canonicalSnapshot = SpikeSnapshot(
                protocolMajor: state.canonicalSnapshot.protocolMajor,
                protocolMinor: state.canonicalSnapshot.protocolMinor,
                schemaVersion: state.canonicalSnapshot.schemaVersion,
                snapshotID: makeUUID(),
                canonicalGeneration: state.canonicalSnapshot.canonicalGeneration + 1,
                activeRunID: state.canonicalSnapshot.activeRunID,
                activeRunRevision: state.canonicalSnapshot.activeRunRevision,
                activeRunState: state.canonicalSnapshot.activeRunState,
                openSegmentID: state.canonicalSnapshot.openSegmentID,
                headMutationID: state.canonicalSnapshot.headMutationID,
                pendingConflictID: conflictID,
                producedAt: now
            )
        }

        let acknowledgement = SpikeMutationAcknowledgement(
            acknowledgementID: makeUUID(),
            mutationID: envelope.payload.mutationID,
            originDeviceID: envelope.payload.originDeviceID,
            originSequence: envelope.payload.originSequence,
            outcome: outcome.outcome,
            canonicalSnapshotID: state.canonicalSnapshot.snapshotID,
            canonicalGeneration: state.canonicalSnapshot.canonicalGeneration,
            conflictID: conflictID,
            reasonCode: outcome.reasonCode,
            acknowledgedAt: now
        )
        state.inbox[index].status = .terminal
        state.inbox[index].acknowledgement = acknowledgement
        return acknowledgement
    }

    private static func finishWithoutApplying(
        index: Int,
        envelope: SpikeMutationEnvelope,
        outcome: SpikeAcknowledgementOutcome,
        reasonCode: String,
        state: inout SpikePersistentState,
        now: Date,
        makeUUID: () -> UUID
    ) -> SpikeMutationAcknowledgement {
        let conflictID = outcome == .conflict ? makeUUID() : nil
        if let conflictID {
            state.mutationBlocked = true
            state.canonicalSnapshot = SpikeSnapshot(
                protocolMajor: state.canonicalSnapshot.protocolMajor,
                protocolMinor: state.canonicalSnapshot.protocolMinor,
                schemaVersion: state.canonicalSnapshot.schemaVersion,
                snapshotID: makeUUID(),
                canonicalGeneration: state.canonicalSnapshot.canonicalGeneration + 1,
                activeRunID: state.canonicalSnapshot.activeRunID,
                activeRunRevision: state.canonicalSnapshot.activeRunRevision,
                activeRunState: state.canonicalSnapshot.activeRunState,
                openSegmentID: state.canonicalSnapshot.openSegmentID,
                headMutationID: state.canonicalSnapshot.headMutationID,
                pendingConflictID: conflictID,
                producedAt: now
            )
        }
        let acknowledgement = SpikeMutationAcknowledgement(
            acknowledgementID: makeUUID(),
            mutationID: envelope.payload.mutationID,
            originDeviceID: envelope.payload.originDeviceID,
            originSequence: envelope.payload.originSequence,
            outcome: outcome,
            canonicalSnapshotID: state.canonicalSnapshot.snapshotID,
            canonicalGeneration: state.canonicalSnapshot.canonicalGeneration,
            conflictID: conflictID,
            reasonCode: reasonCode,
            acknowledgedAt: now
        )
        state.inbox[index].status = .terminal
        state.inbox[index].acknowledgement = acknowledgement
        return acknowledgement
    }

    private static func evaluate(
        envelope: SpikeMutationEnvelope,
        state: SpikePersistentState
    ) -> (outcome: SpikeAcknowledgementOutcome, reasonCode: String) {
        let payload = envelope.payload
        guard envelope.hasValidDigest else { return (.invalid, "digest_mismatch") }
        guard payload.protocolMajor == SpikeMutationPayload.protocolMajor else {
            return (.unsupported, "unsupported_protocol")
        }
        if state.inbox.contains(where: {
            $0.envelope.payload.originDeviceID == payload.originDeviceID
                && $0.envelope.payload.originSequence == payload.originSequence
                && $0.envelope.payload.mutationID != payload.mutationID
        }) {
            return (.conflict, "origin_sequence_collision")
        }
        guard !state.mutationBlocked else { return (.conflict, "mutation_blocked") }

        if payload.predecessorMutationID == nil {
            guard payload.baseCanonicalGeneration
                    == state.canonicalSnapshot.canonicalGeneration
            else {
                return (.conflict, "stale_canonical_base")
            }
            if payload.baseCanonicalGeneration > 0,
                payload.baseSnapshotID != state.canonicalSnapshot.snapshotID
            {
                return (.conflict, "snapshot_identity_mismatch")
            }
        }

        guard payload.observedRunID == state.localRunID,
            payload.observedRunRevision == state.localRunRevision
        else {
            return (.conflict, "observed_run_mismatch")
        }
        guard actionIsValid(payload.action, state: state) else {
            return (.invalid, "invalid_transition")
        }
        return (.applied, "applied")
    }

    private static func actionIsValid(
        _ action: SpikeAction,
        state: SpikePersistentState
    ) -> Bool {
        switch action.kind {
        case .start:
            state.localRunID == nil && action.segmentID != nil && action.projectID != nil
        case .pause:
            state.localRunID == action.runID && state.localRunState == .running
                && state.localOpenSegmentID == action.segmentID
        case .resume:
            state.localRunID == action.runID && state.localRunState == .paused
                && action.segmentID != nil
        case .end:
            state.localRunID == action.runID && state.localRunState != nil
                && state.localOpenSegmentID == action.segmentID
        }
    }

    private static func apply(_ action: SpikeAction, state: inout SpikePersistentState) {
        switch action.kind {
        case .start:
            state.localRunID = action.runID
            state.localRunRevision = 1
            state.localRunState = .running
            state.localOpenSegmentID = action.segmentID
        case .pause:
            state.localRunRevision = (state.localRunRevision ?? 0) + 1
            state.localRunState = .paused
            state.localOpenSegmentID = nil
        case .resume:
            state.localRunRevision = (state.localRunRevision ?? 0) + 1
            state.localRunState = .running
            state.localOpenSegmentID = action.segmentID
        case .end:
            state.localRunID = nil
            state.localRunRevision = nil
            state.localRunState = nil
            state.localOpenSegmentID = nil
        }
    }
}
