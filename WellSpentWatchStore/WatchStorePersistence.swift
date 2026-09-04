import Foundation
import SwiftData

enum WatchStorePersistence {
    static let appGroupIdentifier = "group.com.drewreilly.wellspent.watch"
    static let storeName = "WellSpentWatchLocal"

    static var schema: Schema {
        Schema(versionedSchema: WatchStoreSchemaV2.self)
    }

    static func makePersistentContainer(
        storeURL: URL? = nil,
        allowsSave: Bool = true
    ) throws -> ModelContainer {
        let resolvedURL = try storeURL ?? defaultStoreURL()
        if allowsSave {
            try WatchLocalStoragePrivacy.prepareStore(at: resolvedURL)
        } else if !FileManager.default.fileExists(atPath: resolvedURL.path) {
            // A gallery/extension read must never create an empty app store.
            throw WatchStoreError.corruptStore
        }
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: resolvedURL,
            allowsSave: allowsSave,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: WatchStoreMigrationPlan.self,
            configurations: [configuration]
        )
        if allowsSave { try WatchLocalStoragePrivacy.prepareStore(at: resolvedURL) }
        return container
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
            groupContainer: .none,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: WatchStoreMigrationPlan.self,
            configurations: [configuration]
        )
    }

    static func defaultStoreURL() throws -> URL {
        guard
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            throw WatchStoreError.corruptStore
        }
        return
            groupURL
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent("\(storeName).store")
    }
}

enum WatchLocalStoragePrivacy {
    static func prepareStore(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try protect(directoryURL)

        guard
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else { return }

        for case let itemURL as URL in enumerator {
            try protect(itemURL)
        }
    }

    static func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    private static func protect(_ url: URL) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(resourceValues)

        let protection = FileProtectionType.completeUntilFirstUserAuthentication
        #if targetEnvironment(simulator)
            try? FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: url.path
            )
        #else
            try FileManager.default.setAttributes(
                [.protectionKey: protection],
                ofItemAtPath: url.path
            )
        #endif
    }
}
