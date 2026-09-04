import Foundation
import SwiftData

/// Adds the durable reconciliation records used to preserve divergent branches,
/// audit explicit resolutions, retain canonical snapshots, and distribute
/// tombstones without changing any v4 domain model.
enum WellSpentSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            WellSpentSchemaV3.ProjectRecord.self,
            WellSpentSchemaV3.TimeSessionRecord.self,
            WellSpentSchemaV3.SessionTagRecord.self,
            WellSpentSchemaV3.SessionTagAssignmentRecord.self,
            WellSpentSchemaV3.TimerRunRecord.self,
            WellSpentSchemaV3.TimerRunTagAssignmentRecord.self,
            WellSpentSchemaV3.TimerOriginRecord.self,
            WellSpentSchemaV4.PhoneSyncMetadataRecord.self,
            WellSpentSchemaV4.PhoneMutationInboxRecord.self,
            WellSpentSchemaV4.PhoneAcknowledgementOutboxRecord.self,
            WellSpentSchemaV4.PhoneSnapshotReceiptRecord.self,
            PhoneCanonicalSnapshotRecord.self,
            PhoneTimerConflictRecord.self,
            PhoneConflictMutationRecord.self,
            PhoneEntityTombstoneRecord.self,
        ]
    }

    @Model
    final class PhoneCanonicalSnapshotRecord {
        var snapshotID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var snapshotData: Data = Data()
        var createdAt: Date = Date()

        init(
            snapshotID: UUID,
            canonicalGeneration: Int64,
            snapshotData: Data,
            createdAt: Date
        ) {
            self.snapshotID = snapshotID
            self.canonicalGeneration = canonicalGeneration
            self.snapshotData = snapshotData
            self.createdAt = createdAt
        }
    }

    @Model
    final class PhoneTimerConflictRecord {
        var conflictID: UUID = UUID()
        var stateRawValue: String = "awaiting_phone_review"
        var reasonCodeRawValue: String = "invalid_envelope"
        var canonicalHeadData: Data = Data()
        var canonicalSnapshotData: Data?
        var involvedRunIDsData: Data = Data()
        var involvedSegmentIDsData: Data = Data()
        var createdAt: Date = Date()
        var resolvedAt: Date?
        var resolutionMutationID: UUID?
        var resolutionPayloadData: Data?
        var resolvedHeadData: Data?

        init(
            conflictID: UUID,
            stateRawValue: String,
            reasonCodeRawValue: String,
            canonicalHeadData: Data,
            canonicalSnapshotData: Data?,
            involvedRunIDsData: Data,
            involvedSegmentIDsData: Data,
            createdAt: Date
        ) {
            self.conflictID = conflictID
            self.stateRawValue = stateRawValue
            self.reasonCodeRawValue = reasonCodeRawValue
            self.canonicalHeadData = canonicalHeadData
            self.canonicalSnapshotData = canonicalSnapshotData
            self.involvedRunIDsData = involvedRunIDsData
            self.involvedSegmentIDsData = involvedSegmentIDsData
            self.createdAt = createdAt
        }
    }

    @Model
    final class PhoneConflictMutationRecord {
        var recordID: UUID = UUID()
        var conflictID: UUID = UUID()
        var mutationID: UUID = UUID()
        var originDeviceID: UUID = UUID()
        var originSequence: Int64 = 0
        var envelopeData: Data = Data()
        var reconstructedBranchData: Data?
        var receivedAt: Date = Date()

        init(
            recordID: UUID,
            conflictID: UUID,
            mutationID: UUID,
            originDeviceID: UUID,
            originSequence: Int64,
            envelopeData: Data,
            reconstructedBranchData: Data?,
            receivedAt: Date
        ) {
            self.recordID = recordID
            self.conflictID = conflictID
            self.mutationID = mutationID
            self.originDeviceID = originDeviceID
            self.originSequence = originSequence
            self.envelopeData = envelopeData
            self.reconstructedBranchData = reconstructedBranchData
            self.receivedAt = receivedAt
        }
    }

    @Model
    final class PhoneEntityTombstoneRecord {
        var tombstoneID: UUID = UUID()
        var entityTypeRawValue: String = "run"
        var entityID: UUID = UUID()
        var canonicalGeneration: Int64 = 0
        var deletedAt: Date = Date()
        var conflictID: UUID?

        init(
            tombstoneID: UUID,
            entityTypeRawValue: String,
            entityID: UUID,
            canonicalGeneration: Int64,
            deletedAt: Date,
            conflictID: UUID?
        ) {
            self.tombstoneID = tombstoneID
            self.entityTypeRawValue = entityTypeRawValue
            self.entityID = entityID
            self.canonicalGeneration = canonicalGeneration
            self.deletedAt = deletedAt
            self.conflictID = conflictID
        }
    }
}

typealias PhoneCanonicalSnapshotRecord = WellSpentSchemaV5.PhoneCanonicalSnapshotRecord
typealias PhoneTimerConflictRecord = WellSpentSchemaV5.PhoneTimerConflictRecord
typealias PhoneConflictMutationRecord = WellSpentSchemaV5.PhoneConflictMutationRecord
typealias PhoneEntityTombstoneRecord = WellSpentSchemaV5.PhoneEntityTombstoneRecord
