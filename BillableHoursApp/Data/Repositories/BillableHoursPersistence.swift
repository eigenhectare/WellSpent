import Foundation
import SwiftData

enum BillableHoursPersistence {
    static let storeName = "BillableHoursLocal"

    static var schema: Schema {
        Schema(versionedSchema: BillableHoursSchemaV2.self)
    }

    static func makePersistentContainer(storeURL: URL? = nil) throws -> ModelContainer {
        let resolvedStoreURL = try storeURL ?? defaultStoreURL()
        let configuration = ModelConfiguration(
            storeName,
            schema: schema,
            url: resolvedStoreURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )

        return try ModelContainer(
            for: schema,
            migrationPlan: BillableHoursMigrationPlan.self,
            configurations: [configuration]
        )
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
            migrationPlan: BillableHoursMigrationPlan.self,
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
