import Foundation
import SwiftData

enum WellSpentPersistence {
    static let storeName = "WellSpentLocal"

    static var schema: Schema {
        Schema(versionedSchema: WellSpentSchemaV2.self)
    }

    static func makePersistentContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? defaultStoreURL()
        try LocalStoragePrivacy.prepareAuthoritativeStore(at: resolvedStoreURL)
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: resolvedStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        let container = try ModelContainer(
            for: schema,
            migrationPlan: WellSpentMigrationPlan.self,
            configurations: [configuration]
        )
        try LocalStoragePrivacy.prepareAuthoritativeStore(at: resolvedStoreURL)
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
            migrationPlan: WellSpentMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static func defaultStoreURL() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return applicationSupportURL.appendingPathComponent("\(storeName).store")
    }
}

enum LocalStoragePrivacy {
    static func prepareAuthoritativeStore(at storeURL: URL) throws {
        let directoryURL = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try protect(directoryURL, protection: .complete)

        guard
            let enumerator = FileManager.default.enumerator(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
        else { return }

        for case let itemURL as URL in enumerator {
            try protect(itemURL, protection: .complete)
        }
    }

    static func isExcludedFromBackup(_ url: URL) throws -> Bool {
        try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true
    }

    private static func protect(_ url: URL, protection: FileProtectionType) throws {
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(resourceValues)

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

@MainActor
final class WellSpentLocalDataResetService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func deleteAllUserData() throws {
        do {
            for assignment in try context.fetch(FetchDescriptor<SessionTagAssignmentRecord>()) {
                context.delete(assignment)
            }
            for tag in try context.fetch(FetchDescriptor<SessionTagRecord>()) {
                context.delete(tag)
            }
            for session in try context.fetch(FetchDescriptor<TimeSessionRecord>()) {
                context.delete(session)
            }
            for project in try context.fetch(FetchDescriptor<ProjectRecord>()) {
                context.delete(project)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
}
