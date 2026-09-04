import Foundation

public struct OriginSequenceKey: Codable, Equatable, Hashable, Sendable {
    public let originDeviceID: UUID
    public let originSequence: UInt64

    public init(originDeviceID: UUID, originSequence: UInt64) {
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
    }
}

public struct AppliedMutationRecord: Codable, Equatable, Sendable {
    public let mutationID: UUID
    public let originDeviceID: UUID
    public let originSequence: UInt64
    public let payloadDigest: SHA256Digest
    public let outcome: MutationOutcome
    public let resultingHead: TimerLedgerHead
    public let baseSnapshotID: UUID?
    public let baseCanonicalGeneration: UInt64?
    public let predecessorMutationID: UUID?

    public init(
        mutationID: UUID,
        originDeviceID: UUID,
        originSequence: UInt64,
        payloadDigest: SHA256Digest,
        outcome: MutationOutcome,
        resultingHead: TimerLedgerHead,
        baseSnapshotID: UUID? = nil,
        baseCanonicalGeneration: UInt64? = nil,
        predecessorMutationID: UUID? = nil
    ) {
        self.mutationID = mutationID
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
        self.payloadDigest = payloadDigest
        self.outcome = outcome
        self.resultingHead = resultingHead
        self.baseSnapshotID = baseSnapshotID
        self.baseCanonicalGeneration = baseCanonicalGeneration
        self.predecessorMutationID = predecessorMutationID
    }
}

public struct MutationReconciliationContext: Sendable {
    public let canonicalHead: TimerLedgerHead
    public let mutationsByID: [UUID: AppliedMutationRecord]
    public let mutationsByOriginSequence: [OriginSequenceKey: AppliedMutationRecord]

    public init(
        canonicalHead: TimerLedgerHead,
        mutationsByID: [UUID: AppliedMutationRecord] = [:],
        mutationsByOriginSequence: [OriginSequenceKey: AppliedMutationRecord] = [:]
    ) {
        self.canonicalHead = canonicalHead
        self.mutationsByID = mutationsByID
        self.mutationsByOriginSequence = mutationsByOriginSequence
    }
}

public enum MutationReconciliationDecision: Equatable, Sendable {
    case apply
    case awaitPredecessor(UUID)
    case duplicate(MutationOutcome)
    case reject(ContractReasonCode)
    case reviewRequired(ContractReasonCode)
}

public enum TimerMutationReconciler {
    public static func classify(
        _ mutation: TimerMutationEnvelope,
        in context: MutationReconciliationContext
    ) -> MutationReconciliationDecision {
        guard
            WellSpentWatchContract.supportedVersions.supports(
                protocolVersion: mutation.protocolVersion,
                schemaVersion: mutation.schemaVersion
            )
        else {
            return .reject(.unsupportedProtocol)
        }
        guard mutation.hasValidDigest() else {
            return .reject(.digestMismatch)
        }

        if let existing = context.mutationsByID[mutation.mutationID] {
            guard existing.payloadDigest == mutation.payloadDigest else {
                return .reviewRequired(.mutationIdentityCollision)
            }
            return .duplicate(existing.outcome)
        }

        let sequenceKey = OriginSequenceKey(
            originDeviceID: mutation.originDeviceID,
            originSequence: mutation.originSequence
        )
        if let existing = context.mutationsByOriginSequence[sequenceKey] {
            guard
                existing.mutationID == mutation.mutationID,
                existing.payloadDigest == mutation.payloadDigest
            else {
                return .reviewRequired(.originSequenceCollision)
            }
            return .duplicate(existing.outcome)
        }

        if let predecessorID = mutation.predecessorMutationID {
            guard let predecessor = context.mutationsByID[predecessorID] else {
                return .awaitPredecessor(predecessorID)
            }
            guard
                predecessor.originDeviceID == mutation.originDeviceID,
                predecessor.originSequence < mutation.originSequence,
                predecessor.outcome == .applied
            else {
                return .reviewRequired(.predecessorNotApplied)
            }
            if let predecessorBaseGeneration = predecessor.baseCanonicalGeneration {
                guard mutation.baseSnapshotID == predecessor.baseSnapshotID,
                    mutation.baseCanonicalGeneration == predecessorBaseGeneration
                else {
                    return .reviewRequired(.staleCausalBase)
                }
            }
            guard predecessor.resultingHead == context.canonicalHead else {
                return .reviewRequired(.staleCausalBase)
            }
            guard observation(in: mutation, matches: predecessor.resultingHead) else {
                return .reviewRequired(.observedStateDiverged)
            }
            return .apply
        }

        let baseMatches: Bool
        if mutation.baseCanonicalGeneration == 0, mutation.baseSnapshotID == nil {
            baseMatches = context.canonicalHead.canonicalGeneration == 0
        } else {
            baseMatches =
                mutation.baseSnapshotID == context.canonicalHead.snapshotID
                && mutation.baseCanonicalGeneration == context.canonicalHead.canonicalGeneration
        }
        guard baseMatches else {
            return .reviewRequired(.staleCausalBase)
        }
        guard observation(in: mutation, matches: context.canonicalHead) else {
            return .reviewRequired(.observedStateDiverged)
        }
        return .apply
    }

    private static func observation(
        in mutation: TimerMutationEnvelope,
        matches head: TimerLedgerHead
    ) -> Bool {
        mutation.observedRunID == head.activeRunID
            && mutation.observedRunRevision == head.activeRunRevision
    }
}

public enum SnapshotReconciliationDecision: Equatable, Sendable {
    case confirmAlreadyInstalled
    case install
    case reviewRequired(ContractReasonCode)
    case stale
}

public enum TimerSnapshotReconciler {
    public static func classify(
        incoming: TimerLedgerHead,
        installed: TimerLedgerHead?,
        contradictsPendingMutations: Bool
    ) -> SnapshotReconciliationDecision {
        guard let installed else {
            return contradictsPendingMutations
                ? .reviewRequired(.snapshotContradictsPending)
                : .install
        }

        if incoming.canonicalGeneration < installed.canonicalGeneration {
            return .stale
        }
        if incoming.canonicalGeneration == installed.canonicalGeneration {
            return incoming.snapshotID == installed.snapshotID
                ? .confirmAlreadyInstalled
                : .reviewRequired(.snapshotGenerationCollision)
        }
        if contradictsPendingMutations {
            return .reviewRequired(.snapshotContradictsPending)
        }
        return .install
    }
}

public enum ContractStableOrdering {
    public static func segments(_ segments: [TimerSegmentSnapshot]) -> [TimerSegmentSnapshot] {
        segments.sorted { left, right in
            if left.startedAt != right.startedAt {
                return left.startedAt < right.startedAt
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    public static func projects(_ projects: [ProjectSnapshot]) -> [ProjectSnapshot] {
        projects.sorted { left, right in
            if left.name != right.name {
                return left.name < right.name
            }
            return left.id.uuidString < right.id.uuidString
        }
    }

    public static func tags(_ tags: [TagSnapshot]) -> [TagSnapshot] {
        tags.sorted { left, right in
            if left.name != right.name {
                return left.name < right.name
            }
            return left.id.uuidString < right.id.uuidString
        }
    }
}
