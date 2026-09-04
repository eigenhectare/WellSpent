import Foundation
import WellSpentWatchContracts

public enum WatchStoreError: String, Error, Equatable, Sendable {
    case blocked = "store_blocked"
    case commandInvalid = "command_invalid"
    case corruptStore = "corrupt_store"
    case duplicateIdentity = "duplicate_identity"
    case localCapacityExceeded = "local_capacity_exceeded"
    case saveFailed = "save_failed"
    case snapshotRejected = "snapshot_rejected"
    case unsupportedStoreVersion = "unsupported_store_version"
}

public enum WatchStoreLimits {
    public static let maximumAcknowledgements = 256
    public static let maximumOutboxEntries = 128
    public static let maximumProjects = 250
    public static let maximumRecentProjects = 250
    public static let maximumQuarantineEntries = 64
    public static let maximumSnapshotReceipts = 32
    public static let maximumTags = 250
    public static let maximumTombstones = 512
}

public struct WatchCachedProjection: Codable, Equatable, Sendable {
    public var ledgerHead: TimerLedgerHead?
    public var projects: [ProjectSnapshot]
    public var tags: [TagSnapshot]
    public var tombstones: [EntityTombstone]
    public var activeRun: TimerRunSnapshot?
    public var activeRunSegments: [TimerSegmentSnapshot]
    public var recentlyEndedRun: TimerRunSnapshot?
    public var recentlyEndedRunSegments: [TimerSegmentSnapshot]
    public var totals: TimerTotalsSnapshot?
    public var conflict: TimerConflictSnapshot?
    public var updateGuidance: MinimumAppVersionGuidance?
    public var showProjectNamesOnSystemSurfaces: Bool?

    public init(
        ledgerHead: TimerLedgerHead? = nil,
        projects: [ProjectSnapshot] = [],
        tags: [TagSnapshot] = [],
        tombstones: [EntityTombstone] = [],
        activeRun: TimerRunSnapshot? = nil,
        activeRunSegments: [TimerSegmentSnapshot] = [],
        recentlyEndedRun: TimerRunSnapshot? = nil,
        recentlyEndedRunSegments: [TimerSegmentSnapshot] = [],
        totals: TimerTotalsSnapshot? = nil,
        conflict: TimerConflictSnapshot? = nil,
        updateGuidance: MinimumAppVersionGuidance? = nil,
        showProjectNamesOnSystemSurfaces: Bool? = nil
    ) {
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
        self.updateGuidance = updateGuidance
        self.showProjectNamesOnSystemSurfaces = showProjectNamesOnSystemSurfaces
    }

    init(snapshot: TimerSnapshotEnvelope) {
        let projectTombstones = Set(
            snapshot.tombstones.filter { $0.entityType == .project }.map(\.entityID)
        )
        let tagTombstones = Set(
            snapshot.tombstones.filter { $0.entityType == .tag }.map(\.entityID)
        )
        let runTombstones = Set(
            snapshot.tombstones.filter { $0.entityType == .run }.map(\.entityID)
        )
        ledgerHead = snapshot.ledgerHead
        projects = ContractStableOrdering.projects(
            snapshot.projects.filter { !projectTombstones.contains($0.id) }
        )
        tags = ContractStableOrdering.tags(
            snapshot.tags.filter { !tagTombstones.contains($0.id) }
        )
        tombstones = snapshot.tombstones
        activeRun = snapshot.activeRun.flatMap {
            runTombstones.contains($0.id) ? nil : $0
        }
        activeRunSegments =
            activeRun == nil
            ? []
            : ContractStableOrdering.segments(
                snapshot.activeRunSegments
            )
        recentlyEndedRun = snapshot.recentlyEndedRun.flatMap {
            runTombstones.contains($0.id) ? nil : $0
        }
        recentlyEndedRunSegments =
            recentlyEndedRun == nil
            ? []
            : ContractStableOrdering.segments(snapshot.recentlyEndedRunSegments)
        totals = snapshot.totals
        conflict = snapshot.conflict
        updateGuidance = snapshot.updateGuidance
        showProjectNamesOnSystemSurfaces = snapshot.showProjectNamesOnSystemSurfaces
    }
}

public struct WatchStoreState: Equatable, Sendable {
    public let originDeviceID: UUID
    public let nextOriginSequence: UInt64
    public let protocolVersion: ContractVersion
    public let schemaVersion: UInt16
    public let projection: WatchCachedProjection
    public let pendingMutationCount: Int
    public let quarantinedMutationCount: Int
    public let pendingSnapshotReceiptCount: Int
    public let blockingReasonCode: String?
    public let recentProjectIDs: [UUID]

    public var isPendingSync: Bool {
        pendingMutationCount > 0 || pendingSnapshotReceiptCount > 0
    }

    public var isBlocked: Bool {
        blockingReasonCode != nil || projection.conflict != nil
    }
}

public struct WatchOutboxItem: Equatable, Sendable {
    public let mutationID: UUID
    public let originSequence: UInt64
    public let payloadDigest: SHA256Digest
    public let envelopeData: Data
    public let createdAt: Date
    public let attemptCount: Int
    public let lastAttemptAt: Date?
    public let nextRetryAt: Date?
}

public struct WatchSnapshotReceiptItem: Equatable, Sendable {
    public let receiptID: UUID
    public let snapshotID: UUID
    public let canonicalGeneration: UInt64
    public let receiptData: Data
    public let createdAt: Date
    public let attemptCount: Int
    public let lastAttemptAt: Date?
}

public struct WatchCommandCommit: Equatable, Sendable {
    public let mutation: TimerMutationEnvelope
    public let projection: WatchCachedProjection
}

public enum WatchSnapshotInstallResult: Equatable, Sendable {
    case confirmed
    case installed(SnapshotReceipt)
    case reviewRequired(ContractReasonCode)
    case stale
}
