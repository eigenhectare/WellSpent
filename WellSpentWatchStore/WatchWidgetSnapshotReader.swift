import Foundation
import SwiftData
import WellSpentWatchContracts

public final class WatchWidgetSnapshotReader {
    private let container: ModelContainer

    public init() throws {
        let storeURL = try WatchStorePersistence.defaultStoreURL()
        container = try WatchStorePersistence.makePersistentContainer(
            storeURL: storeURL,
            allowsSave: false
        )
    }

    init(container: ModelContainer) {
        self.container = container
    }

    public func read() throws -> WatchWidgetState {
        let (context, metadata, projection) = try load()
        let pendingSync =
            try context.fetchCount(FetchDescriptor<WatchOutboxRecord>()) > 0
            || context.fetchCount(FetchDescriptor<WatchSnapshotReceiptRecord>()) > 0
        var recentFetch = FetchDescriptor<WatchRecentProjectRecord>(
            sortBy: [SortDescriptor(\.selectionSequence, order: .reverse)]
        )
        recentFetch.fetchLimit = WatchStoreLimits.maximumRecentProjects
        return WatchWidgetState.make(
            projection: projection,
            pendingSync: pendingSync,
            isBlocked: metadata.blockingReasonRawValue != nil,
            recentProjectIDs: try context.fetch(recentFetch).map(\.projectID),
            commandContext: WatchCommandContext.token(
                originID: metadata.originDeviceID, nextSequence: UInt64(metadata.nextOriginSequence),
                projection: projection)
        )
    }

    public func readProjectChoices() throws -> [WatchWidgetProject] {
        let (_, metadata, projection) = try load()
        guard metadata.blockingReasonRawValue == nil, projection.conflict == nil,
            projection.updateGuidance?.updateRequired != true
        else { return [] }
        return projection.projects.map {
            WatchWidgetProject(id: $0.id, name: projection.showProjectNamesOnSystemSurfaces == true ? $0.name : nil)
        }
    }

    private func load() throws -> (ModelContext, WatchStoreMetadataRecord, WatchCachedProjection) {
        let context = ModelContext(container)
        var metadataFetch = FetchDescriptor<WatchStoreMetadataRecord>()
        metadataFetch.fetchLimit = 2
        let metadataRecords = try context.fetch(metadataFetch)
        guard metadataRecords.count == 1, let metadata = metadataRecords.first,
            metadata.nextOriginSequence > 0,
            let nextSequence = UInt64(exactly: metadata.nextOriginSequence),
            let protocolMajor = UInt16(exactly: metadata.protocolMajor),
            let protocolMinor = UInt16(exactly: metadata.protocolMinor),
            let schemaVersion = UInt16(exactly: metadata.schemaVersion)
        else {
            throw WatchStoreError.corruptStore
        }
        guard metadata.projectionData.count <= WellSpentWatchContract.maximumSnapshotBytes else {
            throw WatchStoreError.corruptStore
        }
        let projection = try ContractWireCodec.decodeCanonical(
            WatchCachedProjection.self,
            from: metadata.projectionData
        )
        _ = nextSequence
        _ = ContractVersion(major: protocolMajor, minor: protocolMinor)
        _ = schemaVersion
        try WatchProjectionReducer.validate(projection)
        return (context, metadata, projection)
    }
}
