import SwiftData

/// Append each released schema and its explicit migration stage here. Version
/// one is the oldest shipped schema, so it intentionally has no incoming stage.
enum WellSpentMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [WellSpentSchemaV1.self, WellSpentSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WellSpentSchemaV1.self,
                toVersion: WellSpentSchemaV2.self
            )
        ]
    }
}
