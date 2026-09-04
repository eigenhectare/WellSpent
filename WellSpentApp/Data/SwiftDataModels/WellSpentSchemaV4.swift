import Foundation
import SwiftData

/// Adds the durable iPhone-side WatchConnectivity inbox, acknowledgement
/// outbox, canonical snapshot head, and snapshot-receipt journal. The v3 model
/// types are reused verbatim so this version remains a purely additive,
/// lightweight migration.
enum WellSpentSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WellSpentSchemaV3.ProjectRecord.self,
            WellSpentSchemaV3.TimeSessionRecord.self,
            WellSpentSchemaV3.SessionTagRecord.self,
            WellSpentSchemaV3.SessionTagAssignmentRecord.self,
            WellSpentSchemaV3.TimerRunRecord.self,
            WellSpentSchemaV3.TimerRunTagAssignmentRecord.self,
            WellSpentSchemaV3.TimerOriginRecord.self,
            PhoneSyncMetadataRecord.self,
            PhoneMutationInboxRecord.self,
            PhoneAcknowledgementOutboxRecord.self,
            PhoneSnapshotReceiptRecord.self,
        ]
    }

    @Model
    final class PhoneSyncMetadataRecord {
        var singletonKey: String = "phone-sync"
        var snapshotID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var stateSignatureHex: String?
        var headMutationID: UUID?
        var updatedAt: Date = Date()

        init(snapshotID: UUID, updatedAt: Date) {
            self.snapshotID = snapshotID
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class PhoneMutationInboxRecord {
        var mutationID: UUID = UUID()
        var originDeviceID: UUID = UUID()
        var originSequence: Int64 = 0
        var payloadDigestHex: String = ""
        var envelopeData: Data = Data()
        var statusRawValue: String = "received"
        var outcomeRawValue: String?
        var reasonCodeRawValue: String?
        var acknowledgementData: Data?
        var resultingHeadData: Data?
        var receivedAt: Date = Date()
        var completedAt: Date?

        init(
            mutationID: UUID,
            originDeviceID: UUID,
            originSequence: Int64,
            payloadDigestHex: String,
            envelopeData: Data,
            receivedAt: Date
        ) {
            self.mutationID = mutationID
            self.originDeviceID = originDeviceID
            self.originSequence = originSequence
            self.payloadDigestHex = payloadDigestHex
            self.envelopeData = envelopeData
            self.receivedAt = receivedAt
        }
    }

    @Model
    final class PhoneAcknowledgementOutboxRecord {
        var acknowledgementID: UUID = UUID()
        var mutationID: UUID = UUID()
        var originDeviceID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var acknowledgementData: Data = Data()
        var createdAt: Date = Date()
        var attemptCount: Int64 = 0
        var lastAttemptAt: Date?

        init(
            acknowledgementID: UUID,
            mutationID: UUID,
            originDeviceID: UUID,
            canonicalGeneration: Int64,
            acknowledgementData: Data,
            createdAt: Date
        ) {
            self.acknowledgementID = acknowledgementID
            self.mutationID = mutationID
            self.originDeviceID = originDeviceID
            self.canonicalGeneration = canonicalGeneration
            self.acknowledgementData = acknowledgementData
            self.createdAt = createdAt
        }
    }

    @Model
    final class PhoneSnapshotReceiptRecord {
        var receiptID: UUID = UUID()
        var originDeviceID: UUID = UUID()
        var snapshotID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var receiptData: Data = Data()
        var receivedAt: Date = Date()

        init(
            receiptID: UUID,
            originDeviceID: UUID,
            snapshotID: UUID,
            canonicalGeneration: Int64,
            receiptData: Data,
            receivedAt: Date
        ) {
            self.receiptID = receiptID
            self.originDeviceID = originDeviceID
            self.snapshotID = snapshotID
            self.canonicalGeneration = canonicalGeneration
            self.receiptData = receiptData
            self.receivedAt = receivedAt
        }
    }
}

typealias PhoneSyncMetadataRecord = WellSpentSchemaV4.PhoneSyncMetadataRecord
typealias PhoneMutationInboxRecord = WellSpentSchemaV4.PhoneMutationInboxRecord
typealias PhoneAcknowledgementOutboxRecord = WellSpentSchemaV4.PhoneAcknowledgementOutboxRecord
typealias PhoneSnapshotReceiptRecord = WellSpentSchemaV4.PhoneSnapshotReceiptRecord
