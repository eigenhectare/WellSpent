import Foundation

public struct StartTimerAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let segmentID: UUID
    public let projectID: UUID
    public let durationGoalSeconds: Int?

    public init(runID: UUID, segmentID: UUID, projectID: UUID, durationGoalSeconds: Int?) {
        self.runID = runID
        self.segmentID = segmentID
        self.projectID = projectID
        self.durationGoalSeconds = durationGoalSeconds
    }
}

public struct PauseTimerAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let openSegmentID: UUID

    public init(runID: UUID, openSegmentID: UUID) {
        self.runID = runID
        self.openSegmentID = openSegmentID
    }
}

public struct ResumeTimerAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let newSegmentID: UUID

    public init(runID: UUID, newSegmentID: UUID) {
        self.runID = runID
        self.newSegmentID = newSegmentID
    }
}

public struct SwitchTimerAction: Codable, Equatable, Hashable, Sendable {
    public let fromRunID: UUID
    public let openSegmentID: UUID?
    public let toRunID: UUID
    public let toSegmentID: UUID
    public let projectID: UUID
    public let durationGoalSeconds: Int?

    public init(
        fromRunID: UUID,
        openSegmentID: UUID?,
        toRunID: UUID,
        toSegmentID: UUID,
        projectID: UUID,
        durationGoalSeconds: Int?
    ) {
        self.fromRunID = fromRunID
        self.openSegmentID = openSegmentID
        self.toRunID = toRunID
        self.toSegmentID = toSegmentID
        self.projectID = projectID
        self.durationGoalSeconds = durationGoalSeconds
    }
}

public struct EndTimerAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let openSegmentID: UUID?

    public init(runID: UUID, openSegmentID: UUID?) {
        self.runID = runID
        self.openSegmentID = openSegmentID
    }
}

public struct AnnotateTimerAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let normalizedNote: String?
    public let tagIDs: [UUID]

    public init(runID: UUID, normalizedNote: String?, tagIDs: [UUID]) {
        self.runID = runID
        self.normalizedNote = normalizedNote
        self.tagIDs = tagIDs
    }
}

public struct SetTimerGoalAction: Codable, Equatable, Hashable, Sendable {
    public let runID: UUID
    public let durationGoalSeconds: Int?

    public init(runID: UUID, durationGoalSeconds: Int?) {
        self.runID = runID
        self.durationGoalSeconds = durationGoalSeconds
    }
}

public struct ConflictResolutionPayload: Codable, Equatable, Sendable {
    public let chosenActiveRunID: UUID?
    public let retainedRunIDs: [UUID]
    public let replacementRuns: [TimerRunSnapshot]
    public let replacementSegments: [TimerSegmentSnapshot]

    public init(
        chosenActiveRunID: UUID?,
        retainedRunIDs: [UUID],
        replacementRuns: [TimerRunSnapshot],
        replacementSegments: [TimerSegmentSnapshot]
    ) {
        self.chosenActiveRunID = chosenActiveRunID
        self.retainedRunIDs = retainedRunIDs
        self.replacementRuns = replacementRuns
        self.replacementSegments = replacementSegments
    }
}

public struct ResolveTimerConflictAction: Codable, Equatable, Sendable {
    public let conflictID: UUID
    public let resolution: ConflictResolutionPayload

    public init(conflictID: UUID, resolution: ConflictResolutionPayload) {
        self.conflictID = conflictID
        self.resolution = resolution
    }
}

public struct TimerRecoveryProposalAction: Codable, Equatable, Sendable {
    public let run: TimerRunSnapshot
    public let segments: [TimerSegmentSnapshot]
    public let priorMutationDigests: [SHA256Digest]

    public init(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        priorMutationDigests: [SHA256Digest]
    ) {
        self.run = run
        self.segments = segments
        self.priorMutationDigests = priorMutationDigests
    }
}

public enum TimerMutationAction: Equatable, Sendable {
    case annotate(AnnotateTimerAction)
    case end(EndTimerAction)
    case pause(PauseTimerAction)
    case recoveryProposal(TimerRecoveryProposalAction)
    case resolveConflict(ResolveTimerConflictAction)
    case resume(ResumeTimerAction)
    case setGoal(SetTimerGoalAction)
    case start(StartTimerAction)
    case `switch`(SwitchTimerAction)
}

extension TimerMutationAction: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case payload
    }

    private enum Kind: String, Codable {
        case annotate
        case end
        case pause
        case recoveryProposal = "recovery_proposal"
        case resolveConflict = "resolve_conflict"
        case resume
        case setGoal = "set_goal"
        case start
        case `switch`
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let rawKind = try container.decode(String.self, forKey: .kind)
        guard let kind = Kind(rawValue: rawKind) else {
            throw ContractWireError.unsupportedAction
        }

        switch kind {
        case .annotate:
            self = .annotate(try container.decode(AnnotateTimerAction.self, forKey: .payload))
        case .end:
            self = .end(try container.decode(EndTimerAction.self, forKey: .payload))
        case .pause:
            self = .pause(try container.decode(PauseTimerAction.self, forKey: .payload))
        case .recoveryProposal:
            self = .recoveryProposal(
                try container.decode(TimerRecoveryProposalAction.self, forKey: .payload)
            )
        case .resolveConflict:
            self = .resolveConflict(
                try container.decode(ResolveTimerConflictAction.self, forKey: .payload)
            )
        case .resume:
            self = .resume(try container.decode(ResumeTimerAction.self, forKey: .payload))
        case .setGoal:
            self = .setGoal(try container.decode(SetTimerGoalAction.self, forKey: .payload))
        case .start:
            self = .start(try container.decode(StartTimerAction.self, forKey: .payload))
        case .switch:
            self = .switch(try container.decode(SwitchTimerAction.self, forKey: .payload))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .annotate(let payload):
            try container.encode(Kind.annotate, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .end(let payload):
            try container.encode(Kind.end, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .pause(let payload):
            try container.encode(Kind.pause, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .recoveryProposal(let payload):
            try container.encode(Kind.recoveryProposal, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .resolveConflict(let payload):
            try container.encode(Kind.resolveConflict, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .resume(let payload):
            try container.encode(Kind.resume, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .setGoal(let payload):
            try container.encode(Kind.setGoal, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .start(let payload):
            try container.encode(Kind.start, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        case .switch(let payload):
            try container.encode(Kind.switch, forKey: .kind)
            try container.encode(payload, forKey: .payload)
        }
    }
}

public struct TimerMutationEnvelope: Codable, Equatable, Sendable {
    public let protocolMajor: UInt16
    public let protocolMinor: UInt16
    public let schemaVersion: UInt16
    public let mutationID: UUID
    public let originDeviceID: UUID
    public let originSequence: UInt64
    public let capturedAt: Date
    public let capturedTimeZoneID: String
    public let baseSnapshotID: UUID?
    public let baseCanonicalGeneration: UInt64
    public let predecessorMutationID: UUID?
    public let observedRunID: UUID?
    public let observedRunRevision: Int64?
    public let action: TimerMutationAction
    public let payloadDigest: SHA256Digest

    public var protocolVersion: ContractVersion {
        ContractVersion(major: protocolMajor, minor: protocolMinor)
    }

    public init(
        protocolVersion: ContractVersion = WellSpentWatchContract.protocolVersion,
        schemaVersion: UInt16 = WellSpentWatchContract.schemaVersion,
        mutationID: UUID,
        originDeviceID: UUID,
        originSequence: UInt64,
        capturedAt: Date,
        capturedTimeZoneID: String,
        baseSnapshotID: UUID?,
        baseCanonicalGeneration: UInt64,
        predecessorMutationID: UUID?,
        observedRunID: UUID?,
        observedRunRevision: Int64?,
        action: TimerMutationAction
    ) throws {
        self.protocolMajor = protocolVersion.major
        self.protocolMinor = protocolVersion.minor
        self.schemaVersion = schemaVersion
        self.mutationID = mutationID
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
        self.capturedAt = capturedAt
        self.capturedTimeZoneID = capturedTimeZoneID
        self.baseSnapshotID = baseSnapshotID
        self.baseCanonicalGeneration = baseCanonicalGeneration
        self.predecessorMutationID = predecessorMutationID
        self.observedRunID = observedRunID
        self.observedRunRevision = observedRunRevision
        self.action = action
        self.payloadDigest = SHA256Digest.hashing(
            try ContractWireCodec.encodeCanonical(
                MutationDigestMaterial(
                    protocolMajor: protocolVersion.major,
                    protocolMinor: protocolVersion.minor,
                    schemaVersion: schemaVersion,
                    mutationID: mutationID,
                    originDeviceID: originDeviceID,
                    originSequence: originSequence,
                    capturedAt: capturedAt,
                    capturedTimeZoneID: capturedTimeZoneID,
                    baseSnapshotID: baseSnapshotID,
                    baseCanonicalGeneration: baseCanonicalGeneration,
                    predecessorMutationID: predecessorMutationID,
                    observedRunID: observedRunID,
                    observedRunRevision: observedRunRevision,
                    action: action
                )
            )
        )
    }

    public func hasValidDigest() -> Bool {
        guard
            let encoded = try? ContractWireCodec.encodeCanonical(
                MutationDigestMaterial(
                    protocolMajor: protocolMajor,
                    protocolMinor: protocolMinor,
                    schemaVersion: schemaVersion,
                    mutationID: mutationID,
                    originDeviceID: originDeviceID,
                    originSequence: originSequence,
                    capturedAt: capturedAt,
                    capturedTimeZoneID: capturedTimeZoneID,
                    baseSnapshotID: baseSnapshotID,
                    baseCanonicalGeneration: baseCanonicalGeneration,
                    predecessorMutationID: predecessorMutationID,
                    observedRunID: observedRunID,
                    observedRunRevision: observedRunRevision,
                    action: action
                )
            )
        else {
            return false
        }
        return payloadDigest == SHA256Digest.hashing(encoded)
    }
}

private struct MutationDigestMaterial: Codable {
    let protocolMajor: UInt16
    let protocolMinor: UInt16
    let schemaVersion: UInt16
    let mutationID: UUID
    let originDeviceID: UUID
    let originSequence: UInt64
    let capturedAt: Date
    let capturedTimeZoneID: String
    let baseSnapshotID: UUID?
    let baseCanonicalGeneration: UInt64
    let predecessorMutationID: UUID?
    let observedRunID: UUID?
    let observedRunRevision: Int64?
    let action: TimerMutationAction
}

public enum MutationOutcome: String, Codable, Equatable, Hashable, Sendable {
    case applied
    case conflict
    case duplicate
    case invalid
    case unsupported
}

public struct MutationAcknowledgement: Codable, Equatable, Hashable, Sendable {
    public let acknowledgementID: UUID
    public let mutationID: UUID
    public let originDeviceID: UUID
    public let originSequence: UInt64
    public let outcome: MutationOutcome
    public let canonicalSnapshotID: UUID
    public let canonicalGeneration: UInt64
    public let conflictID: UUID?
    public let reasonCode: ContractReasonCode
    public let acknowledgedAt: Date

    public init(
        acknowledgementID: UUID,
        mutationID: UUID,
        originDeviceID: UUID,
        originSequence: UInt64,
        outcome: MutationOutcome,
        canonicalSnapshotID: UUID,
        canonicalGeneration: UInt64,
        conflictID: UUID?,
        reasonCode: ContractReasonCode,
        acknowledgedAt: Date
    ) {
        self.acknowledgementID = acknowledgementID
        self.mutationID = mutationID
        self.originDeviceID = originDeviceID
        self.originSequence = originSequence
        self.outcome = outcome
        self.canonicalSnapshotID = canonicalSnapshotID
        self.canonicalGeneration = canonicalGeneration
        self.conflictID = conflictID
        self.reasonCode = reasonCode
        self.acknowledgedAt = acknowledgedAt
    }
}

public struct SnapshotReceipt: Codable, Equatable, Hashable, Sendable {
    public let receiptID: UUID
    public let originDeviceID: UUID
    public let snapshotID: UUID
    public let canonicalGeneration: UInt64
    public let receivedAt: Date

    public init(
        receiptID: UUID,
        originDeviceID: UUID,
        snapshotID: UUID,
        canonicalGeneration: UInt64,
        receivedAt: Date
    ) {
        self.receiptID = receiptID
        self.originDeviceID = originDeviceID
        self.snapshotID = snapshotID
        self.canonicalGeneration = canonicalGeneration
        self.receivedAt = receivedAt
    }
}
