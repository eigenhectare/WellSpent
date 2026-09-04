import Foundation
import SwiftData

enum WatchStoreSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            MetadataRecord.self,
            OutboxRecord.self,
            AcknowledgementRecord.self,
            QuarantineRecord.self,
            SnapshotReceiptRecord.self,
        ]
    }

    @Model
    final class MetadataRecord {
        var singletonKey: String = "store"
        var originDeviceID: UUID = UUID()
        var nextOriginSequence: Int64 = 1
        var protocolMajor: Int64 = 1
        var protocolMinor: Int64 = 0
        var schemaVersion: Int64 = 3
        var installedSnapshotID: UUID?
        var installedCanonicalGeneration: Int64 = 0
        var canonicalSnapshotData: Data?
        var projectionData: Data = Data()
        var lastLocalMutationID: UUID?
        var blockingReasonRawValue: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        init(
            originDeviceID: UUID,
            nextOriginSequence: Int64,
            protocolMajor: Int64,
            protocolMinor: Int64,
            schemaVersion: Int64,
            projectionData: Data,
            createdAt: Date
        ) {
            self.originDeviceID = originDeviceID
            self.nextOriginSequence = nextOriginSequence
            self.protocolMajor = protocolMajor
            self.protocolMinor = protocolMinor
            self.schemaVersion = schemaVersion
            self.projectionData = projectionData
            self.createdAt = createdAt
            updatedAt = createdAt
        }
    }

    @Model
    final class OutboxRecord {
        var mutationID: UUID = UUID()
        var originDeviceID: UUID = UUID()
        var originSequence: Int64 = 0
        var payloadDigestHex: String = ""
        var envelopeData: Data = Data()
        var createdAt: Date = Date()
        var attemptCount: Int64 = 0
        var lastAttemptAt: Date?
        var nextRetryAt: Date?

        init(
            mutationID: UUID,
            originDeviceID: UUID,
            originSequence: Int64,
            payloadDigestHex: String,
            envelopeData: Data,
            createdAt: Date
        ) {
            self.mutationID = mutationID
            self.originDeviceID = originDeviceID
            self.originSequence = originSequence
            self.payloadDigestHex = payloadDigestHex
            self.envelopeData = envelopeData
            self.createdAt = createdAt
        }
    }

    @Model
    final class AcknowledgementRecord {
        var acknowledgementID: UUID = UUID()
        var mutationID: UUID = UUID()
        var outcomeRawValue: String = ""
        var acknowledgementData: Data = Data()
        var receivedAt: Date = Date()

        init(
            acknowledgementID: UUID,
            mutationID: UUID,
            outcomeRawValue: String,
            acknowledgementData: Data,
            receivedAt: Date
        ) {
            self.acknowledgementID = acknowledgementID
            self.mutationID = mutationID
            self.outcomeRawValue = outcomeRawValue
            self.acknowledgementData = acknowledgementData
            self.receivedAt = receivedAt
        }
    }

    @Model
    final class QuarantineRecord {
        var quarantineID: UUID = UUID()
        var mutationID: UUID?
        var reasonRawValue: String = ""
        var envelopeData: Data = Data()
        var acknowledgementData: Data?
        var recordedAt: Date = Date()

        init(
            quarantineID: UUID = UUID(),
            mutationID: UUID?,
            reasonRawValue: String,
            envelopeData: Data,
            acknowledgementData: Data?,
            recordedAt: Date
        ) {
            self.quarantineID = quarantineID
            self.mutationID = mutationID
            self.reasonRawValue = reasonRawValue
            self.envelopeData = envelopeData
            self.acknowledgementData = acknowledgementData
            self.recordedAt = recordedAt
        }
    }

    @Model
    final class SnapshotReceiptRecord {
        var receiptID: UUID = UUID()
        var snapshotID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var receiptData: Data = Data()
        var createdAt: Date = Date()
        var attemptCount: Int64 = 0
        var lastAttemptAt: Date?

        init(
            receiptID: UUID,
            snapshotID: UUID,
            canonicalGeneration: Int64,
            receiptData: Data,
            createdAt: Date
        ) {
            self.receiptID = receiptID
            self.snapshotID = snapshotID
            self.canonicalGeneration = canonicalGeneration
            self.receiptData = receiptData
            self.createdAt = createdAt
        }
    }
}

/// Adds Watch-local project recency without changing the phone-authored catalog.
/// The existing v1 records are reused verbatim so the migration is additive.
enum WatchStoreSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WatchStoreSchemaV1.MetadataRecord.self,
            WatchStoreSchemaV1.OutboxRecord.self,
            WatchStoreSchemaV1.AcknowledgementRecord.self,
            WatchStoreSchemaV1.QuarantineRecord.self,
            WatchStoreSchemaV1.SnapshotReceiptRecord.self,
            RecentProjectRecord.self,
        ]
    }

    @Model
    final class RecentProjectRecord {
        var projectID: UUID = UUID()
        var selectionSequence: Int64 = 0
        var selectedAt: Date = Date()

        init(projectID: UUID, selectionSequence: Int64, selectedAt: Date) {
            self.projectID = projectID
            self.selectionSequence = selectionSequence
            self.selectedAt = selectedAt
        }
    }
}

enum WatchStoreMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WatchStoreSchemaV1.self, WatchStoreSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WatchStoreSchemaV1.self,
                toVersion: WatchStoreSchemaV2.self
            )
        ]
    }
}

typealias WatchStoreMetadataRecord = WatchStoreSchemaV1.MetadataRecord
typealias WatchOutboxRecord = WatchStoreSchemaV1.OutboxRecord
typealias WatchAcknowledgementRecord = WatchStoreSchemaV1.AcknowledgementRecord
typealias WatchQuarantineRecord = WatchStoreSchemaV1.QuarantineRecord
typealias WatchSnapshotReceiptRecord = WatchStoreSchemaV1.SnapshotReceiptRecord
typealias WatchRecentProjectRecord = WatchStoreSchemaV2.RecentProjectRecord
