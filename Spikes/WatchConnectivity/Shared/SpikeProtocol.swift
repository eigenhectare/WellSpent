import CryptoKit
import Foundation

enum SpikeTransportKind: String, Codable, Sendable {
    case message
    case userInfo
    case applicationContext
    case local
}

enum SpikeActionKind: String, Codable, Sendable {
    case start
    case pause
    case resume
    case end
}

struct SpikeAction: Codable, Equatable, Sendable {
    let kind: SpikeActionKind
    let runID: UUID
    let segmentID: UUID?
    let projectID: UUID?
}

struct SpikeMutationPayload: Codable, Equatable, Sendable {
    static let protocolMajor: UInt16 = 1
    static let protocolMinor: UInt16 = 0
    static let schemaVersion: UInt16 = 1

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
    let action: SpikeAction

    init(
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
        action: SpikeAction
    ) {
        protocolMajor = Self.protocolMajor
        protocolMinor = Self.protocolMinor
        schemaVersion = Self.schemaVersion
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
    }
}

struct SpikeMutationEnvelope: Codable, Equatable, Sendable {
    let payload: SpikeMutationPayload
    let payloadDigest: String

    init(payload: SpikeMutationPayload) throws {
        self.payload = payload
        payloadDigest = try SpikeCodec.digest(payload)
    }

    var hasValidDigest: Bool {
        (try? SpikeCodec.digest(payload)) == payloadDigest
    }
}

enum SpikeAcknowledgementOutcome: String, Codable, Sendable {
    case applied
    case duplicate
    case conflict
    case invalid
    case unsupported

    var blocksMutation: Bool {
        switch self {
        case .applied, .duplicate:
            false
        case .conflict, .invalid, .unsupported:
            true
        }
    }
}

struct SpikeMutationAcknowledgement: Codable, Equatable, Sendable {
    let acknowledgementID: UUID
    let mutationID: UUID
    let originDeviceID: UUID
    let originSequence: UInt64
    let outcome: SpikeAcknowledgementOutcome
    let canonicalSnapshotID: UUID
    let canonicalGeneration: UInt64
    let conflictID: UUID?
    let reasonCode: String
    let acknowledgedAt: Date
}

enum SpikeRunState: String, Codable, Sendable {
    case running
    case paused
}

struct SpikeSnapshot: Codable, Equatable, Sendable {
    let protocolMajor: UInt16
    let protocolMinor: UInt16
    let schemaVersion: UInt16
    let snapshotID: UUID
    let canonicalGeneration: UInt64
    let activeRunID: UUID?
    let activeRunRevision: Int64?
    let activeRunState: SpikeRunState?
    let openSegmentID: UUID?
    let headMutationID: UUID?
    let pendingConflictID: UUID?
    let producedAt: Date
}

struct SpikeSnapshotReceipt: Codable, Equatable, Sendable {
    let receiptID: UUID
    let originDeviceID: UUID
    let snapshotID: UUID
    let canonicalGeneration: UInt64
    let installedAt: Date
}

struct SpikeEvidenceEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let code: String
    let at: Date
    let mutationID: UUID?
    let originSequence: UInt64?
    let transport: SpikeTransportKind
    let canonicalGeneration: UInt64?
    let reachable: Bool
}

enum SpikeInboxStatus: String, Codable, Sendable {
    case received
    case terminal
}

struct SpikeInboxReceipt: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { envelope.payload.mutationID }

    let envelope: SpikeMutationEnvelope
    var status: SpikeInboxStatus
    var acknowledgement: SpikeMutationAcknowledgement?
    let receivedAt: Date
    let receivedTransport: SpikeTransportKind
}

struct SpikePersistentState: Codable, Equatable, Sendable {
    let originDeviceID: UUID
    var nextOriginSequence: UInt64
    var outbox: [SpikeMutationEnvelope]
    var quarantinedOutbox: [SpikeMutationEnvelope]
    var acknowledgements: [SpikeMutationAcknowledgement]
    var inbox: [SpikeInboxReceipt]
    var queuedMutationIDs: Set<UUID>
    var installedSnapshot: SpikeSnapshot?
    var canonicalSnapshot: SpikeSnapshot
    var receivedSnapshotReceipts: [SpikeSnapshotReceipt]
    var localRunID: UUID?
    var localRunRevision: Int64?
    var localRunState: SpikeRunState?
    var localOpenSegmentID: UUID?
    var lastLocalMutationID: UUID?
    var mutationBlocked: Bool
    var events: [SpikeEvidenceEvent]

    static func empty(originDeviceID: UUID = UUID(), now: Date = Date()) -> Self {
        let snapshot = SpikeSnapshot(
            protocolMajor: SpikeMutationPayload.protocolMajor,
            protocolMinor: SpikeMutationPayload.protocolMinor,
            schemaVersion: SpikeMutationPayload.schemaVersion,
            snapshotID: UUID(),
            canonicalGeneration: 0,
            activeRunID: nil,
            activeRunRevision: nil,
            activeRunState: nil,
            openSegmentID: nil,
            headMutationID: nil,
            pendingConflictID: nil,
            producedAt: now
        )
        return Self(
            originDeviceID: originDeviceID,
            nextOriginSequence: 1,
            outbox: [],
            quarantinedOutbox: [],
            acknowledgements: [],
            inbox: [],
            queuedMutationIDs: [],
            installedSnapshot: nil,
            canonicalSnapshot: snapshot,
            receivedSnapshotReceipts: [],
            localRunID: nil,
            localRunRevision: nil,
            localRunState: nil,
            localOpenSegmentID: nil,
            lastLocalMutationID: nil,
            mutationBlocked: false,
            events: []
        )
    }

    mutating func appendEvent(_ event: SpikeEvidenceEvent) {
        events.append(event)
        if events.count > 250 {
            events.removeFirst(events.count - 250)
        }
    }
}

enum SpikeCodec {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func encode<T: Encodable>(_ value: T) throws -> Data {
        try encoder().encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }

    static func digest<T: Encodable>(_ value: T) throws -> String {
        SHA256.hash(data: try encode(value)).map { String(format: "%02x", $0) }.joined()
    }
}

enum SpikeWireKey {
    static let kind = "kind"
    static let payload = "payload"
}

enum SpikeWireKind: String, Sendable {
    case mutation
    case acknowledgement
    case snapshot
    case snapshotReceipt
}
