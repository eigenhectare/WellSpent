import Foundation

public struct TimerLedgerHead: Codable, Equatable, Hashable, Sendable {
    public let snapshotID: UUID
    public let canonicalGeneration: UInt64
    public let activeRunID: UUID?
    public let activeRunRevision: Int64?
    public let headMutationID: UUID?

    public init(
        snapshotID: UUID,
        canonicalGeneration: UInt64,
        activeRunID: UUID?,
        activeRunRevision: Int64?,
        headMutationID: UUID?
    ) {
        self.snapshotID = snapshotID
        self.canonicalGeneration = canonicalGeneration
        self.activeRunID = activeRunID
        self.activeRunRevision = activeRunRevision
        self.headMutationID = headMutationID
    }
}

public struct ProjectSnapshot: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let workspaceID: UUID?
    public let name: String
    public let colorToken: String?
    public let symbolName: String?

    public init(
        id: UUID,
        workspaceID: UUID?,
        name: String,
        colorToken: String?,
        symbolName: String?
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
        self.colorToken = colorToken
        self.symbolName = symbolName
    }
}

public struct TagSnapshot: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let workspaceID: UUID?
    public let name: String

    public init(id: UUID, workspaceID: UUID?, name: String) {
        self.id = id
        self.workspaceID = workspaceID
        self.name = name
    }
}

public enum TimerRunState: String, Codable, Equatable, Hashable, Sendable {
    case ended
    case paused
    case running
}

public struct TimerRunSnapshot: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let workspaceID: UUID?
    public let projectID: UUID
    public let state: TimerRunState
    public let startedAt: Date
    public let endedAt: Date?
    public let startTimeZoneID: String
    public let endTimeZoneID: String?
    public let durationGoalSeconds: Int?
    public let normalizedNote: String?
    public let tagIDs: [UUID]
    public let originDeviceID: UUID
    public let revision: Int64
    public let lastAppliedMutationID: UUID?
    public let createdAt: Date
    public let updatedAt: Date
    public let updatedTimeZoneID: String

    public init(
        id: UUID,
        workspaceID: UUID?,
        projectID: UUID,
        state: TimerRunState,
        startedAt: Date,
        endedAt: Date?,
        startTimeZoneID: String,
        endTimeZoneID: String?,
        durationGoalSeconds: Int?,
        normalizedNote: String?,
        tagIDs: [UUID],
        originDeviceID: UUID,
        revision: Int64,
        lastAppliedMutationID: UUID?,
        createdAt: Date,
        updatedAt: Date,
        updatedTimeZoneID: String
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.state = state
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startTimeZoneID = startTimeZoneID
        self.endTimeZoneID = endTimeZoneID
        self.durationGoalSeconds = durationGoalSeconds
        self.normalizedNote = normalizedNote
        self.tagIDs = tagIDs
        self.originDeviceID = originDeviceID
        self.revision = revision
        self.lastAppliedMutationID = lastAppliedMutationID
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.updatedTimeZoneID = updatedTimeZoneID
    }
}

public struct TimerSegmentSnapshot: Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public let runID: UUID
    public let workspaceID: UUID?
    public let projectID: UUID
    public let startedAt: Date
    public let endedAt: Date?
    public let startTimeZoneID: String
    public let endTimeZoneID: String?
    public let revision: Int64

    public init(
        id: UUID,
        runID: UUID,
        workspaceID: UUID?,
        projectID: UUID,
        startedAt: Date,
        endedAt: Date?,
        startTimeZoneID: String,
        endTimeZoneID: String?,
        revision: Int64
    ) {
        self.id = id
        self.runID = runID
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.startTimeZoneID = startTimeZoneID
        self.endTimeZoneID = endTimeZoneID
        self.revision = revision
    }
}

public enum TombstoneEntityType: String, Codable, Equatable, Hashable, Sendable {
    case conflictResolution = "conflict_resolution"
    case project
    case run
    case tag
}

public struct EntityTombstone: Codable, Equatable, Hashable, Sendable {
    public let entityType: TombstoneEntityType
    public let entityID: UUID
    public let canonicalGeneration: UInt64
    public let deletedAt: Date

    public init(
        entityType: TombstoneEntityType,
        entityID: UUID,
        canonicalGeneration: UInt64,
        deletedAt: Date
    ) {
        self.entityType = entityType
        self.entityID = entityID
        self.canonicalGeneration = canonicalGeneration
        self.deletedAt = deletedAt
    }
}

public struct TimerTotalsSnapshot: Codable, Equatable, Hashable, Sendable {
    public let todaySeconds: Int
    public let weekSeconds: Int
    public let calculatedAt: Date
    public let calendarTimeZoneID: String

    public init(
        todaySeconds: Int,
        weekSeconds: Int,
        calculatedAt: Date,
        calendarTimeZoneID: String
    ) {
        self.todaySeconds = todaySeconds
        self.weekSeconds = weekSeconds
        self.calculatedAt = calculatedAt
        self.calendarTimeZoneID = calendarTimeZoneID
    }
}

public enum TimerConflictState: String, Codable, Equatable, Hashable, Sendable {
    case awaitingPhoneReview = "awaiting_phone_review"
    case resolved
}

public struct TimerConflictSnapshot: Codable, Equatable, Hashable, Sendable {
    public let conflictID: UUID
    public let state: TimerConflictState
    public let reasonCode: ContractReasonCode
    public let involvedRunIDs: [UUID]
    public let involvedSegmentIDs: [UUID]

    public init(
        conflictID: UUID,
        state: TimerConflictState,
        reasonCode: ContractReasonCode,
        involvedRunIDs: [UUID],
        involvedSegmentIDs: [UUID]
    ) {
        self.conflictID = conflictID
        self.state = state
        self.reasonCode = reasonCode
        self.involvedRunIDs = involvedRunIDs
        self.involvedSegmentIDs = involvedSegmentIDs
    }
}

public struct OriginReceiptWatermark: Codable, Equatable, Hashable, Sendable {
    public let originDeviceID: UUID
    public let contiguousSequence: UInt64

    public init(originDeviceID: UUID, contiguousSequence: UInt64) {
        self.originDeviceID = originDeviceID
        self.contiguousSequence = contiguousSequence
    }
}

public struct MinimumAppVersionGuidance: Codable, Equatable, Hashable, Sendable {
    public let minimumPhoneBuild: Int?
    public let minimumWatchBuild: Int?
    public let updateRequired: Bool

    public init(minimumPhoneBuild: Int?, minimumWatchBuild: Int?, updateRequired: Bool) {
        self.minimumPhoneBuild = minimumPhoneBuild
        self.minimumWatchBuild = minimumWatchBuild
        self.updateRequired = updateRequired
    }
}

public struct TimerSnapshotEnvelope: Codable, Equatable, Sendable {
    public let protocolVersion: ContractVersion
    public let schemaVersion: UInt16
    public let supportedVersions: ContractVersionRange
    public let capabilities: [ContractCapability]
    public let ledgerHead: TimerLedgerHead
    public let projects: [ProjectSnapshot]
    public let tags: [TagSnapshot]
    public let tombstones: [EntityTombstone]
    public let activeRun: TimerRunSnapshot?
    public let activeRunSegments: [TimerSegmentSnapshot]
    public let recentlyEndedRun: TimerRunSnapshot?
    public let recentlyEndedRunSegments: [TimerSegmentSnapshot]
    public let totals: TimerTotalsSnapshot
    public let conflict: TimerConflictSnapshot?
    public let recentAcknowledgements: [MutationAcknowledgement]
    public let receiptWatermarks: [OriginReceiptWatermark]
    public let updateGuidance: MinimumAppVersionGuidance
    /// Missing in older v1 snapshots means private, never implicit opt-in.
    public let showProjectNamesOnSystemSurfaces: Bool?

    public init(
        protocolVersion: ContractVersion = WellSpentWatchContract.protocolVersion,
        schemaVersion: UInt16 = WellSpentWatchContract.schemaVersion,
        supportedVersions: ContractVersionRange = WellSpentWatchContract.supportedVersions,
        capabilities: [ContractCapability],
        ledgerHead: TimerLedgerHead,
        projects: [ProjectSnapshot],
        tags: [TagSnapshot],
        tombstones: [EntityTombstone],
        activeRun: TimerRunSnapshot?,
        activeRunSegments: [TimerSegmentSnapshot],
        recentlyEndedRun: TimerRunSnapshot?,
        recentlyEndedRunSegments: [TimerSegmentSnapshot],
        totals: TimerTotalsSnapshot,
        conflict: TimerConflictSnapshot?,
        recentAcknowledgements: [MutationAcknowledgement],
        receiptWatermarks: [OriginReceiptWatermark],
        updateGuidance: MinimumAppVersionGuidance,
        showProjectNamesOnSystemSurfaces: Bool? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.schemaVersion = schemaVersion
        self.supportedVersions = supportedVersions
        self.capabilities = capabilities
        self.ledgerHead = ledgerHead
        self.projects = projects
        self.tags = tags
        self.tombstones = tombstones
        self.activeRun = activeRun
        self.activeRunSegments = activeRunSegments
        self.recentlyEndedRun = recentlyEndedRun
        self.recentlyEndedRunSegments = recentlyEndedRunSegments
        self.totals = totals
        self.conflict = conflict
        self.recentAcknowledgements = recentAcknowledgements
        self.receiptWatermarks = receiptWatermarks
        self.updateGuidance = updateGuidance
        self.showProjectNamesOnSystemSurfaces = showProjectNamesOnSystemSurfaces
    }
}
