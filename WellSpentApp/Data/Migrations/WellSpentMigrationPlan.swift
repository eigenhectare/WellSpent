import Foundation
import SwiftData

/// Append each released schema and its explicit migration stage here. Version
/// one is the oldest shipped schema, so it intentionally has no incoming stage.
enum WellSpentMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [
            WellSpentSchemaV1.self,
            WellSpentSchemaV2.self,
            WellSpentSchemaV3.self,
            WellSpentSchemaV4.self,
            WellSpentSchemaV5.self,
            WellSpentSchemaV6.self,
        ]
    }

    static var stages: [MigrationStage] {
        [
            .lightweight(
                fromVersion: WellSpentSchemaV1.self,
                toVersion: WellSpentSchemaV2.self
            ),
            migrateV2ToV3,
            .lightweight(
                fromVersion: WellSpentSchemaV3.self,
                toVersion: WellSpentSchemaV4.self
            ),
            .lightweight(
                fromVersion: WellSpentSchemaV4.self,
                toVersion: WellSpentSchemaV5.self
            ),
            .lightweight(
                fromVersion: WellSpentSchemaV5.self,
                toVersion: WellSpentSchemaV6.self
            ),
        ]
    }

    private static let migrateV2ToV3 = MigrationStage.custom(
        fromVersion: WellSpentSchemaV2.self,
        toVersion: WellSpentSchemaV3.self,
        willMigrate: nil,
        didMigrate: { context in
            let sessions = try context.fetch(
                FetchDescriptor<WellSpentSchemaV3.TimeSessionRecord>()
            )
            let assignments = try context.fetch(
                FetchDescriptor<WellSpentSchemaV3.SessionTagAssignmentRecord>()
            )
            let assignmentsBySession = Dictionary(grouping: assignments, by: \.sessionID)

            for session in sessions where session.source == .timer && session.timerRunID == nil {
                let runID = LegacyTimerRunIdentity.runID(for: session.id)
                session.timerRunID = runID
                context.insert(
                    WellSpentSchemaV3.TimerRunRecord(
                        id: runID,
                        workspaceID: session.workspaceID,
                        projectID: session.projectID,
                        state: session.endAt == nil ? .running : .ended,
                        startAt: session.startAt,
                        endAt: session.endAt,
                        startTimeZoneID: session.startTimeZoneID,
                        endTimeZoneID: session.endTimeZoneID,
                        note: session.note,
                        originDeviceID: LegacyTimerRunIdentity.legacyImportOriginDeviceID,
                        revision: 0,
                        createdAt: session.createdAt,
                        updatedAt: session.updatedAt,
                        updatedTimeZoneID: session.endTimeZoneID ?? session.startTimeZoneID
                    )
                )

                for assignment in assignmentsBySession[session.id] ?? [] {
                    context.insert(
                        WellSpentSchemaV3.TimerRunTagAssignmentRecord(
                            id: LegacyTimerRunIdentity.runTagAssignmentID(
                                for: assignment.id
                            ),
                            workspaceID: assignment.workspaceID,
                            timerRunID: runID,
                            tagID: assignment.tagID,
                            nameSnapshot: assignment.nameSnapshot,
                            createdAt: assignment.createdAt
                        )
                    )
                }
            }

            try context.save()
        }
    )
}
