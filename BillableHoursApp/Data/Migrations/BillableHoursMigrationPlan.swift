import SwiftData

/// Append each released schema and its explicit migration stage here. Version
/// one is the oldest shipped schema, so it intentionally has no incoming stage.
enum BillableHoursMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BillableHoursSchemaV1.self, BillableHoursSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: BillableHoursSchemaV1.self,
                toVersion: BillableHoursSchemaV2.self
            )
        ]
    }
}
