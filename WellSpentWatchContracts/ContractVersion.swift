import Foundation

public struct ContractVersion: Codable, Equatable, Hashable, Sendable {
    public let major: UInt16
    public let minor: UInt16

    public init(major: UInt16, minor: UInt16) {
        self.major = major
        self.minor = minor
    }
}

public struct ContractVersionRange: Codable, Equatable, Hashable, Sendable {
    public let minimum: ContractVersion
    public let maximum: ContractVersion
    public let minimumSchemaVersion: UInt16
    public let maximumSchemaVersion: UInt16

    public init(
        minimum: ContractVersion,
        maximum: ContractVersion,
        minimumSchemaVersion: UInt16,
        maximumSchemaVersion: UInt16
    ) {
        self.minimum = minimum
        self.maximum = maximum
        self.minimumSchemaVersion = minimumSchemaVersion
        self.maximumSchemaVersion = maximumSchemaVersion
    }

    public func supports(protocolVersion: ContractVersion, schemaVersion: UInt16) -> Bool {
        protocolVersion.major == minimum.major
            && protocolVersion.major == maximum.major
            && protocolVersion.minor >= minimum.minor
            && protocolVersion.minor <= maximum.minor
            && schemaVersion >= minimumSchemaVersion
            && schemaVersion <= maximumSchemaVersion
    }
}

public enum WellSpentWatchContract {
    public static let protocolVersion = ContractVersion(major: 1, minor: 0)
    public static let schemaVersion: UInt16 = 3
    public static let supportedVersions = ContractVersionRange(
        minimum: ContractVersion(major: 1, minor: 0),
        maximum: ContractVersion(major: 1, minor: 0),
        minimumSchemaVersion: 3,
        maximumSchemaVersion: 3
    )
    public static let maximumMutationBytes = 256 * 1_024
    public static let maximumSnapshotBytes = 1_024 * 1_024
}

public enum ContractCapability: String, Codable, CaseIterable, Hashable, Sendable {
    case acknowledgements
    case annotations
    case causalMutationChain
    case conflictResolution
    case recoveryProposal
    case snapshotReceipts
    case tombstones
}

public enum ContractWireError: String, Error, Codable, Equatable, Hashable, Sendable {
    case digestMismatch = "digest_mismatch"
    case invalidEnvelope = "invalid_envelope"
    case malformedPayload = "malformed_payload"
    case payloadTooLarge = "payload_too_large"
    case unsupportedAction = "unsupported_action"
    case unsupportedProtocol = "unsupported_protocol"
}

public enum ContractReasonCode: String, Codable, Equatable, Hashable, Sendable {
    case applied
    case digestMismatch = "digest_mismatch"
    case duplicate
    case invalidEnvelope = "invalid_envelope"
    case mutationIdentityCollision = "mutation_identity_collision"
    case originSequenceCollision = "origin_sequence_collision"
    case observedStateDiverged = "observed_state_diverged"
    case predecessorNotApplied = "predecessor_not_applied"
    case snapshotContradictsPending = "snapshot_contradicts_pending"
    case snapshotGenerationCollision = "snapshot_generation_collision"
    case staleCausalBase = "stale_causal_base"
    case unsupportedAction = "unsupported_action"
    case unsupportedProtocol = "unsupported_protocol"
}
