import Foundation
import SwiftData
import WellSpentWatchContracts

@MainActor
public final class WellSpentWatchStore {
    private let container: ModelContainer
    private let context: ModelContext
    private let storeURL: URL?
    private let uuidFactory: () -> UUID
    private let now: () -> Date
    #if DEBUG
        private var beforeSave: () throws -> Void = {}
    #endif

    public static func openDefault() throws -> WellSpentWatchStore {
        let storeURL = try WatchStorePersistence.defaultStoreURL()
        return try WellSpentWatchStore(
            container: WatchStorePersistence.makePersistentContainer(storeURL: storeURL),
            storeURL: storeURL
        )
    }

    init(
        container: ModelContainer,
        storeURL: URL? = nil,
        originDeviceID: UUID? = nil,
        uuidFactory: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) throws {
        self.container = container
        context = ModelContext(container)
        self.storeURL = storeURL
        self.uuidFactory = uuidFactory
        self.now = now
        try bootstrap(preferredOriginDeviceID: originDeviceID)
    }

    static func makeInMemory(
        originDeviceID: UUID = UUID(),
        uuidFactory: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) throws -> WellSpentWatchStore {
        try makeEphemeral(
            originDeviceID: originDeviceID,
            uuidFactory: uuidFactory,
            now: now
        )
    }

    /// Creates a non-persistent store for deterministic previews and UI tests.
    public static func makeEphemeral(
        originDeviceID: UUID = UUID(),
        uuidFactory: @escaping () -> UUID = UUID.init,
        now: @escaping () -> Date = Date.init
    ) throws -> WellSpentWatchStore {
        try WellSpentWatchStore(
            container: WatchStorePersistence.makeInMemoryContainer(),
            originDeviceID: originDeviceID,
            uuidFactory: uuidFactory,
            now: now
        )
    }

    /// Records Watch-local picker recency while keeping the project catalog
    /// entirely phone-authored. Unknown or tombstoned projects are rejected.
    public func recordProjectSelection(projectID: UUID, selectedAt: Date) throws {
        do {
            let metadata = try requiredMetadata()
            guard metadata.blockingReasonRawValue == nil else {
                throw WatchStoreError.blocked
            }
            let projection = try decodeProjection(metadata.projectionData)
            let tombstonedProjectIDs = Set(
                projection.tombstones
                    .filter { $0.entityType == .project }
                    .map(\.entityID)
            )
            guard projection.projects.contains(where: { $0.id == projectID }),
                !tombstonedProjectIDs.contains(projectID)
            else {
                throw WatchStoreError.commandInvalid
            }

            var records = try fetchRecentProjects()
            let nextSequence = try nextRecentProjectSequence(records)
            if let existing = records.first(where: { $0.projectID == projectID }) {
                existing.selectionSequence = nextSequence
                existing.selectedAt = selectedAt
            } else {
                context.insert(
                    WatchRecentProjectRecord(
                        projectID: projectID,
                        selectionSequence: nextSequence,
                        selectedAt: selectedAt
                    )
                )
            }
            records = try fetchRecentProjects().filter { !$0.isDeleted }
            for record in records.dropFirst(WatchStoreLimits.maximumRecentProjects) {
                context.delete(record)
            }
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    #if DEBUG
        func setBeforeSaveForTesting(_ hook: @escaping () throws -> Void) {
            beforeSave = hook
        }

        /// A private app-container store; never opens or resets the live App Group.
        public static func openRestartFixture(at url: URL, originDeviceID: UUID) throws -> WellSpentWatchStore {
            try WellSpentWatchStore(
                container: WatchStorePersistence.makePersistentContainer(storeURL: url),
                storeURL: url, originDeviceID: originDeviceID)
        }
    #endif

    public func state() throws -> WatchStoreState {
        try makeState(metadata: requiredMetadata())
    }

    public func performLocalCommand(
        _ action: TimerMutationAction,
        capturedAt: Date,
        timeZoneID: String
    ) throws -> WatchCommandCommit {
        do {
            let metadata = try requiredMetadata()
            guard metadata.blockingReasonRawValue == nil else {
                throw WatchStoreError.blocked
            }
            let outbox = try fetchOutbox()
            guard outbox.count < WatchStoreLimits.maximumOutboxEntries else {
                throw WatchStoreError.localCapacityExceeded
            }
            guard metadata.nextOriginSequence > 0,
                metadata.nextOriginSequence < Int64.max,
                metadata.installedCanonicalGeneration >= 0
            else {
                throw WatchStoreError.corruptStore
            }

            let originSequence = UInt64(metadata.nextOriginSequence)
            let mutationID = uuidFactory()
            let sourceProjection = try decodeProjection(metadata.projectionData)
            let observedRun = sourceProjection.activeRun
            let envelope = try TimerMutationEnvelope(
                mutationID: mutationID,
                originDeviceID: metadata.originDeviceID,
                originSequence: originSequence,
                capturedAt: capturedAt,
                capturedTimeZoneID: timeZoneID,
                baseSnapshotID: metadata.installedSnapshotID,
                baseCanonicalGeneration: UInt64(metadata.installedCanonicalGeneration),
                predecessorMutationID: metadata.lastLocalMutationID,
                observedRunID: observedRun?.id,
                observedRunRevision: observedRun?.revision,
                action: action
            )
            let updatedProjection = try WatchProjectionReducer.applying(
                action,
                to: sourceProjection,
                mutationID: mutationID,
                originDeviceID: metadata.originDeviceID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
            let envelopeData = try ContractWireCodec.encodeMutation(envelope)

            metadata.projectionData = try encodeProjection(updatedProjection)
            metadata.nextOriginSequence += 1
            metadata.lastLocalMutationID = mutationID
            metadata.updatedAt = capturedAt
            context.insert(
                WatchOutboxRecord(
                    mutationID: mutationID,
                    originDeviceID: metadata.originDeviceID,
                    originSequence: Int64(originSequence),
                    payloadDigestHex: envelope.payloadDigest.hex,
                    envelopeData: envelopeData,
                    createdAt: capturedAt
                )
            )
            try commit()
            return WatchCommandCommit(mutation: envelope, projection: updatedProjection)
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func pendingOutbox() throws -> [WatchOutboxItem] {
        try fetchOutbox().map { record in
            guard record.originSequence > 0, record.attemptCount >= 0,
                let sequence = UInt64(exactly: record.originSequence),
                let attempts = Int(exactly: record.attemptCount)
            else {
                throw WatchStoreError.corruptStore
            }
            return WatchOutboxItem(
                mutationID: record.mutationID,
                originSequence: sequence,
                payloadDigest: try SHA256Digest(hex: record.payloadDigestHex),
                envelopeData: record.envelopeData,
                createdAt: record.createdAt,
                attemptCount: attempts,
                lastAttemptAt: record.lastAttemptAt,
                nextRetryAt: record.nextRetryAt
            )
        }
    }

    public func recordDeliveryAttempt(
        mutationID: UUID,
        attemptedAt: Date,
        nextRetryAt: Date?
    ) throws {
        do {
            guard let record = try fetchOutbox().first(where: { $0.mutationID == mutationID }) else {
                throw WatchStoreError.commandInvalid
            }
            record.attemptCount += 1
            record.lastAttemptAt = attemptedAt
            record.nextRetryAt = nextRetryAt
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func receiveAcknowledgement(_ acknowledgement: MutationAcknowledgement) throws {
        do {
            let metadata = try requiredMetadata()
            if try fetchAcknowledgements().contains(where: {
                $0.acknowledgementID == acknowledgement.acknowledgementID
            }) {
                return
            }
            try applyAcknowledgement(acknowledgement, metadata: metadata)
            try trimAcknowledgements()
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func installSnapshotData(
        _ data: Data,
        contradictsPendingMutations: Bool
    ) throws -> WatchSnapshotInstallResult {
        do {
            let snapshot = try ContractWireCodec.decodeSnapshot(data)
            try validateSnapshotCapacity(snapshot)
            let metadata = try requiredMetadata()
            let installedHead = try decodeProjection(metadata.projectionData).ledgerHead
            let decision = TimerSnapshotReconciler.classify(
                incoming: snapshot.ledgerHead,
                installed: installedHead,
                contradictsPendingMutations: contradictsPendingMutations
            )

            switch decision {
            case .confirmAlreadyInstalled:
                return .confirmed
            case .stale:
                return .stale
            case .reviewRequired(let reasonCode):
                metadata.blockingReasonRawValue = reasonCode.rawValue
                metadata.updatedAt = now()
                try commit()
                return .reviewRequired(reasonCode)
            case .install:
                break
            }

            for acknowledgement in snapshot.recentAcknowledgements {
                let exists = try fetchAcknowledgements().contains(where: {
                    $0.acknowledgementID == acknowledgement.acknowledgementID
                })
                if !exists {
                    try applyAcknowledgement(acknowledgement, metadata: metadata)
                }
            }
            try trimAcknowledgements()

            let hasPendingMutations = !(try fetchOutbox()).isEmpty
            var projection = WatchCachedProjection(snapshot: snapshot)
            if hasPendingMutations {
                let local = try decodeProjection(metadata.projectionData)
                projection.activeRun = local.activeRun
                projection.activeRunSegments = local.activeRunSegments
                projection.recentlyEndedRun = local.recentlyEndedRun
                projection.recentlyEndedRunSegments = local.recentlyEndedRunSegments
            }
            try WatchProjectionReducer.validate(projection)

            metadata.installedSnapshotID = snapshot.ledgerHead.snapshotID
            metadata.installedCanonicalGeneration = try checkedInt64(
                snapshot.ledgerHead.canonicalGeneration
            )
            metadata.canonicalSnapshotData = data
            metadata.projectionData = try encodeProjection(projection)
            try pruneRecentProjects(keeping: Set(projection.projects.map(\.id)))
            if let conflict = snapshot.conflict {
                metadata.blockingReasonRawValue = conflict.reasonCode.rawValue
            } else if snapshot.tombstones.contains(where: {
                $0.entityType == .conflictResolution
            }) {
                metadata.blockingReasonRawValue = nil
            }
            metadata.updatedAt = now()

            let receipt = SnapshotReceipt(
                receiptID: uuidFactory(),
                originDeviceID: metadata.originDeviceID,
                snapshotID: snapshot.ledgerHead.snapshotID,
                canonicalGeneration: snapshot.ledgerHead.canonicalGeneration,
                receivedAt: now()
            )
            try insertSnapshotReceipt(receipt)
            try commit()
            return .installed(receipt)
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func pendingSnapshotReceipts() throws -> [WatchSnapshotReceiptItem] {
        try fetchSnapshotReceipts().map { record in
            guard record.canonicalGeneration >= 0, record.attemptCount >= 0,
                let generation = UInt64(exactly: record.canonicalGeneration),
                let attempts = Int(exactly: record.attemptCount)
            else {
                throw WatchStoreError.corruptStore
            }
            return WatchSnapshotReceiptItem(
                receiptID: record.receiptID,
                snapshotID: record.snapshotID,
                canonicalGeneration: generation,
                receiptData: record.receiptData,
                createdAt: record.createdAt,
                attemptCount: attempts,
                lastAttemptAt: record.lastAttemptAt
            )
        }
    }

    public func recordSnapshotReceiptAttempt(receiptID: UUID, attemptedAt: Date) throws {
        do {
            guard
                let record = try fetchSnapshotReceipts().first(where: { $0.receiptID == receiptID })
            else {
                throw WatchStoreError.commandInvalid
            }
            record.attemptCount += 1
            record.lastAttemptAt = attemptedAt
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func compactSnapshotReceipt(receiptID: UUID) throws {
        do {
            guard
                let record = try fetchSnapshotReceipts().first(where: { $0.receiptID == receiptID })
            else { return }
            context.delete(record)
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    public func eraseAll() throws {
        do {
            for record in try fetchOutbox() { context.delete(record) }
            for record in try fetchAcknowledgements() { context.delete(record) }
            for record in try fetchQuarantine() { context.delete(record) }
            for record in try fetchSnapshotReceipts() { context.delete(record) }
            for record in try fetchRecentProjects() { context.delete(record) }
            for record in try fetchMetadata() { context.delete(record) }
            context.insert(try freshMetadata(originDeviceID: uuidFactory(), createdAt: now()))
            try commit()
        } catch {
            context.rollback()
            throw mapTransactionError(error)
        }
    }

    private func bootstrap(preferredOriginDeviceID: UUID?) throws {
        let metadataRecords = try fetchMetadata()
        guard metadataRecords.count <= 1 else {
            throw WatchStoreError.duplicateIdentity
        }

        if metadataRecords.isEmpty {
            let outbox = try fetchOutbox()
            if let first = outbox.first {
                let recovered = try freshMetadata(
                    originDeviceID: first.originDeviceID,
                    createdAt: first.createdAt
                )
                guard let maximumOriginSequence = outbox.map(\.originSequence).max(),
                    maximumOriginSequence > 0,
                    maximumOriginSequence < Int64.max
                else {
                    throw WatchStoreError.corruptStore
                }
                recovered.nextOriginSequence = maximumOriginSequence + 1
                context.insert(recovered)
                try recoverProjection(metadata: recovered, outbox: outbox)
            } else {
                context.insert(
                    try freshMetadata(
                        originDeviceID: preferredOriginDeviceID ?? uuidFactory(),
                        createdAt: now()
                    )
                )
            }
            try commit()
            return
        }

        let metadata = metadataRecords[0]
        guard metadata.protocolMajor == Int64(WellSpentWatchContract.protocolVersion.major),
            metadata.protocolMinor <= Int64(WellSpentWatchContract.protocolVersion.minor),
            metadata.schemaVersion == Int64(WellSpentWatchContract.schemaVersion),
            metadata.nextOriginSequence > 0,
            metadata.installedCanonicalGeneration >= 0
        else {
            throw WatchStoreError.unsupportedStoreVersion
        }

        do {
            try WatchProjectionReducer.validate(decodeProjection(metadata.projectionData))
            try validateOutbox(metadata: metadata)
        } catch {
            context.rollback()
            let refreshedMetadata = try requiredMetadata()
            try recoverProjection(metadata: refreshedMetadata, outbox: try fetchOutbox())
            try commit()
        }
    }

    private func recoverProjection(
        metadata: WatchStoreMetadataRecord,
        outbox: [WatchOutboxRecord]
    ) throws {
        var projection = WatchCachedProjection()
        if let canonicalData = metadata.canonicalSnapshotData,
            let canonical = try? ContractWireCodec.decodeSnapshot(canonicalData)
        {
            projection = WatchCachedProjection(snapshot: canonical)
            metadata.installedSnapshotID = canonical.ledgerHead.snapshotID
            metadata.installedCanonicalGeneration = try checkedInt64(
                canonical.ledgerHead.canonicalGeneration
            )
        }

        var blocked = false
        for record in outbox.sorted(by: { $0.originSequence < $1.originSequence }) {
            guard !blocked else { continue }
            do {
                let mutation = try ContractWireCodec.decodeMutation(record.envelopeData)
                guard let originSequence = UInt64(exactly: record.originSequence) else {
                    throw WatchStoreError.corruptStore
                }
                guard mutation.mutationID == record.mutationID,
                    mutation.originDeviceID == metadata.originDeviceID,
                    mutation.originSequence == originSequence,
                    mutation.payloadDigest.hex == record.payloadDigestHex
                else {
                    throw WatchStoreError.corruptStore
                }
                projection = try WatchProjectionReducer.applying(
                    mutation.action,
                    to: projection,
                    mutationID: mutation.mutationID,
                    originDeviceID: mutation.originDeviceID,
                    capturedAt: mutation.capturedAt,
                    timeZoneID: mutation.capturedTimeZoneID
                )
            } catch {
                context.insert(
                    WatchQuarantineRecord(
                        mutationID: record.mutationID,
                        reasonRawValue: ContractReasonCode.invalidEnvelope.rawValue,
                        envelopeData: record.envelopeData,
                        acknowledgementData: nil,
                        recordedAt: now()
                    )
                )
                context.delete(record)
                metadata.blockingReasonRawValue = ContractReasonCode.invalidEnvelope.rawValue
                blocked = true
            }
        }
        metadata.projectionData = try encodeProjection(projection)
        metadata.lastLocalMutationID =
            outbox
            .filter { !$0.isDeleted }
            .max(by: { $0.originSequence < $1.originSequence })?.mutationID
        metadata.updatedAt = now()
    }

    private func validateOutbox(metadata: WatchStoreMetadataRecord) throws {
        let outbox = try fetchOutbox()
        guard outbox.count <= WatchStoreLimits.maximumOutboxEntries else {
            throw WatchStoreError.localCapacityExceeded
        }
        var identities = Set<UUID>()
        var sequences = Set<Int64>()
        for record in outbox {
            guard identities.insert(record.mutationID).inserted,
                sequences.insert(record.originSequence).inserted,
                record.originSequence > 0,
                record.originDeviceID == metadata.originDeviceID
            else {
                throw WatchStoreError.duplicateIdentity
            }
            let mutation = try ContractWireCodec.decodeMutation(record.envelopeData)
            guard let originSequence = UInt64(exactly: record.originSequence) else {
                throw WatchStoreError.corruptStore
            }
            guard mutation.mutationID == record.mutationID,
                mutation.originDeviceID == record.originDeviceID,
                mutation.originSequence == originSequence,
                mutation.payloadDigest.hex == record.payloadDigestHex
            else {
                throw WatchStoreError.corruptStore
            }
        }
    }

    private func applyAcknowledgement(
        _ acknowledgement: MutationAcknowledgement,
        metadata: WatchStoreMetadataRecord
    ) throws {
        let acknowledgementData = try ContractWireCodec.encodeCanonical(acknowledgement)
        context.insert(
            WatchAcknowledgementRecord(
                acknowledgementID: acknowledgement.acknowledgementID,
                mutationID: acknowledgement.mutationID,
                outcomeRawValue: acknowledgement.outcome.rawValue,
                acknowledgementData: acknowledgementData,
                receivedAt: acknowledgement.acknowledgedAt
            )
        )

        guard
            let outbox = try fetchOutbox().first(where: {
                $0.mutationID == acknowledgement.mutationID
            })
        else { return }
        guard let outboxOriginSequence = UInt64(exactly: outbox.originSequence) else {
            throw WatchStoreError.corruptStore
        }
        guard acknowledgement.originDeviceID == outbox.originDeviceID,
            acknowledgement.originSequence == outboxOriginSequence
        else {
            metadata.blockingReasonRawValue = ContractReasonCode.mutationIdentityCollision.rawValue
            metadata.updatedAt = acknowledgement.acknowledgedAt
            return
        }

        switch acknowledgement.outcome {
        case .applied, .duplicate:
            context.delete(outbox)
        case .conflict, .invalid, .unsupported:
            guard try fetchQuarantine().count < WatchStoreLimits.maximumQuarantineEntries else {
                throw WatchStoreError.localCapacityExceeded
            }
            context.insert(
                WatchQuarantineRecord(
                    mutationID: outbox.mutationID,
                    reasonRawValue: acknowledgement.reasonCode.rawValue,
                    envelopeData: outbox.envelopeData,
                    acknowledgementData: acknowledgementData,
                    recordedAt: acknowledgement.acknowledgedAt
                )
            )
            context.delete(outbox)
            metadata.blockingReasonRawValue = acknowledgement.reasonCode.rawValue
        }
        let remaining = try fetchOutbox().filter { !$0.isDeleted }
        metadata.lastLocalMutationID =
            remaining.max(by: {
                $0.originSequence < $1.originSequence
            })?.mutationID
        metadata.updatedAt = acknowledgement.acknowledgedAt
    }

    private func insertSnapshotReceipt(_ receipt: SnapshotReceipt) throws {
        let records = try fetchSnapshotReceipts()
        guard records.count < WatchStoreLimits.maximumSnapshotReceipts else {
            throw WatchStoreError.localCapacityExceeded
        }
        context.insert(
            WatchSnapshotReceiptRecord(
                receiptID: receipt.receiptID,
                snapshotID: receipt.snapshotID,
                canonicalGeneration: try checkedInt64(receipt.canonicalGeneration),
                receiptData: try ContractWireCodec.encodeCanonical(receipt),
                createdAt: receipt.receivedAt
            )
        )
    }

    private func trimAcknowledgements() throws {
        let records = try fetchAcknowledgements().sorted { $0.receivedAt < $1.receivedAt }
        let excess = max(0, records.count - WatchStoreLimits.maximumAcknowledgements)
        for record in records.prefix(excess) {
            context.delete(record)
        }
    }

    private func validateSnapshotCapacity(_ snapshot: TimerSnapshotEnvelope) throws {
        guard snapshot.projects.count <= WatchStoreLimits.maximumProjects,
            snapshot.tags.count <= WatchStoreLimits.maximumTags,
            snapshot.tombstones.count <= WatchStoreLimits.maximumTombstones,
            snapshot.recentAcknowledgements.count <= WatchStoreLimits.maximumAcknowledgements
        else {
            throw WatchStoreError.localCapacityExceeded
        }
    }

    private func makeState(metadata: WatchStoreMetadataRecord) throws -> WatchStoreState {
        guard metadata.nextOriginSequence > 0, metadata.installedCanonicalGeneration >= 0,
            let nextSequence = UInt64(exactly: metadata.nextOriginSequence),
            let protocolMajor = UInt16(exactly: metadata.protocolMajor),
            let protocolMinor = UInt16(exactly: metadata.protocolMinor),
            let schemaVersion = UInt16(exactly: metadata.schemaVersion)
        else {
            throw WatchStoreError.corruptStore
        }
        return WatchStoreState(
            originDeviceID: metadata.originDeviceID,
            nextOriginSequence: nextSequence,
            protocolVersion: ContractVersion(major: protocolMajor, minor: protocolMinor),
            schemaVersion: schemaVersion,
            projection: try decodeProjection(metadata.projectionData),
            pendingMutationCount: try fetchOutbox().count,
            quarantinedMutationCount: try fetchQuarantine().count,
            pendingSnapshotReceiptCount: try fetchSnapshotReceipts().count,
            blockingReasonCode: metadata.blockingReasonRawValue,
            recentProjectIDs: try fetchRecentProjects().map(\.projectID)
        )
    }

    private func freshMetadata(originDeviceID: UUID, createdAt: Date) throws
        -> WatchStoreMetadataRecord
    {
        WatchStoreMetadataRecord(
            originDeviceID: originDeviceID,
            nextOriginSequence: 1,
            protocolMajor: Int64(WellSpentWatchContract.protocolVersion.major),
            protocolMinor: Int64(WellSpentWatchContract.protocolVersion.minor),
            schemaVersion: Int64(WellSpentWatchContract.schemaVersion),
            projectionData: try encodeProjection(WatchCachedProjection()),
            createdAt: createdAt
        )
    }

    private func requiredMetadata() throws -> WatchStoreMetadataRecord {
        let records = try fetchMetadata()
        guard records.count == 1, let metadata = records.first else {
            throw WatchStoreError.corruptStore
        }
        return metadata
    }

    private func fetchMetadata() throws -> [WatchStoreMetadataRecord] {
        try context.fetch(FetchDescriptor<WatchStoreMetadataRecord>())
    }

    private func fetchOutbox() throws -> [WatchOutboxRecord] {
        try context.fetch(
            FetchDescriptor<WatchOutboxRecord>(
                sortBy: [SortDescriptor(\.originSequence), SortDescriptor(\.mutationID)]
            )
        )
    }

    private func fetchAcknowledgements() throws -> [WatchAcknowledgementRecord] {
        try context.fetch(FetchDescriptor<WatchAcknowledgementRecord>())
    }

    private func fetchQuarantine() throws -> [WatchQuarantineRecord] {
        try context.fetch(FetchDescriptor<WatchQuarantineRecord>())
    }

    private func fetchSnapshotReceipts() throws -> [WatchSnapshotReceiptRecord] {
        try context.fetch(
            FetchDescriptor<WatchSnapshotReceiptRecord>(
                sortBy: [SortDescriptor(\.canonicalGeneration), SortDescriptor(\.receiptID)]
            )
        )
    }

    private func fetchRecentProjects() throws -> [WatchRecentProjectRecord] {
        try context.fetch(
            FetchDescriptor<WatchRecentProjectRecord>(
                sortBy: [
                    SortDescriptor(\.selectionSequence, order: .reverse),
                    SortDescriptor(\.projectID),
                ]
            )
        )
    }

    private func nextRecentProjectSequence(_ records: [WatchRecentProjectRecord]) throws -> Int64 {
        let maximum = records.map(\.selectionSequence).max() ?? 0
        guard maximum >= 0, maximum < Int64.max else {
            throw WatchStoreError.localCapacityExceeded
        }
        return maximum + 1
    }

    private func pruneRecentProjects(keeping projectIDs: Set<UUID>) throws {
        for record in try fetchRecentProjects() where !projectIDs.contains(record.projectID) {
            context.delete(record)
        }
    }

    private func encodeProjection(_ projection: WatchCachedProjection) throws -> Data {
        do {
            return try ContractWireCodec.encodeCanonical(projection)
        } catch {
            throw WatchStoreError.corruptStore
        }
    }

    private func decodeProjection(_ data: Data) throws -> WatchCachedProjection {
        do {
            return try ContractWireCodec.decodeCanonical(WatchCachedProjection.self, from: data)
        } catch {
            throw WatchStoreError.corruptStore
        }
    }

    private func checkedInt64(_ value: UInt64) throws -> Int64 {
        guard let converted = Int64(exactly: value) else {
            throw WatchStoreError.localCapacityExceeded
        }
        return converted
    }

    private func commit() throws {
        #if DEBUG
            try beforeSave()
        #endif
        do {
            try context.save()
        } catch {
            throw WatchStoreError.saveFailed
        }
        if let storeURL {
            try? WatchLocalStoragePrivacy.prepareStore(at: storeURL)
        }
    }

    private func mapTransactionError(_ error: Error) -> WatchStoreError {
        if let storeError = error as? WatchStoreError {
            return storeError
        }
        if error is ContractWireError {
            return .snapshotRejected
        }
        return .saveFailed
    }
}
