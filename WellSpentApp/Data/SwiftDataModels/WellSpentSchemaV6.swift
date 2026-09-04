import Foundation
import SwiftData

/// Content-free erase fence; earlier schema models remain unchanged.
enum WellSpentSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        WellSpentSchemaV5.models + [PhoneDataResetRecord.self]
    }

    @Model
    final class PhoneDataResetRecord {
        var minimumAcceptedGeneration: Int64 = 0

        init(minimumAcceptedGeneration: Int64) {
            self.minimumAcceptedGeneration = minimumAcceptedGeneration
        }
    }
}

typealias PhoneDataResetRecord = WellSpentSchemaV6.PhoneDataResetRecord
