import Foundation
import SwiftData

enum SessionTagStatus: String, CaseIterable, Codable, Sendable {
    case active
    case archived
}

/// Adds optional project emoji plus queryable session-tag definitions and
/// assignments. Foreign identifiers remain explicit and relationships remain
/// absent so the model keeps the additive, CloudKit-compatible shape chosen in
/// v1.
enum WellSpentSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectRecord.self,
            TimeSessionRecord.self,
            SessionTagRecord.self,
            SessionTagAssignmentRecord.self,
        ]
    }

    @Model
    final class ProjectRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var name: String = ""
        var colorToken: String?
        var emoji: String?
        var statusRawValue: String = ProjectStatus.active.rawValue
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var status: ProjectStatus {
            get { ProjectStatus(rawValue: statusRawValue) ?? .active }
            set { statusRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            name: String,
            colorToken: String? = nil,
            emoji: String? = nil,
            status: ProjectStatus = .active,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.name = name
            self.colorToken = colorToken
            self.emoji = emoji
            statusRawValue = status.rawValue
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class TimeSessionRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var projectID: UUID = UUID()
        var sourceRawValue: String = TimeSessionSource.timer.rawValue
        var startAt: Date = Date()
        var endAt: Date?
        var startTimeZoneID: String = TimeZone.current.identifier
        var endTimeZoneID: String?
        var note: String?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var source: TimeSessionSource {
            get { TimeSessionSource(rawValue: sourceRawValue) ?? .timer }
            set { sourceRawValue = newValue.rawValue }
        }

        var duration: TimeInterval? {
            endAt.map { $0.timeIntervalSince(startAt) }
        }

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            projectID: UUID,
            source: TimeSessionSource,
            startAt: Date,
            endAt: Date? = nil,
            startTimeZoneID: String,
            endTimeZoneID: String? = nil,
            note: String? = nil,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.projectID = projectID
            sourceRawValue = source.rawValue
            self.startAt = startAt
            self.endAt = endAt
            self.startTimeZoneID = startTimeZoneID
            self.endTimeZoneID = endTimeZoneID
            self.note = note
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class SessionTagRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var name: String = ""
        var normalizedName: String = ""
        var statusRawValue: String = SessionTagStatus.active.rawValue
        var isBuiltIn: Bool = false
        var createdAt: Date = Date()
        var updatedAt: Date = Date()

        var status: SessionTagStatus {
            get { SessionTagStatus(rawValue: statusRawValue) ?? .active }
            set { statusRawValue = newValue.rawValue }
        }

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            name: String,
            normalizedName: String,
            status: SessionTagStatus = .active,
            isBuiltIn: Bool = false,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.name = name
            self.normalizedName = normalizedName
            statusRawValue = status.rawValue
            self.isBuiltIn = isBuiltIn
            self.createdAt = createdAt
            self.updatedAt = updatedAt
        }
    }

    @Model
    final class SessionTagAssignmentRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var sessionID: UUID = UUID()
        var tagID: UUID = UUID()
        var nameSnapshot: String = ""
        var createdAt: Date = Date()

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            sessionID: UUID,
            tagID: UUID,
            nameSnapshot: String,
            createdAt: Date = Date()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.sessionID = sessionID
            self.tagID = tagID
            self.nameSnapshot = nameSnapshot
            self.createdAt = createdAt
        }
    }
}
