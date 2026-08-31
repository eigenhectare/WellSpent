import Foundation
import SwiftData

enum ProjectStatus: String, CaseIterable, Codable, Sendable {
    case active
    case archived
}

enum TimeSessionSource: String, CaseIterable, Codable, Sendable {
    case timer
    case manual
}

/// The first shipped SwiftData schema. Models are nested so a later schema can
/// define its own model types without mutating the historical v1 definition.
enum BillableHoursSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ProjectRecord.self, TimeSessionRecord.self]
    }

    @Model
    final class ProjectRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var name: String = ""
        var colorToken: String?
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
            status: ProjectStatus = .active,
            createdAt: Date = Date(),
            updatedAt: Date = Date()
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.name = name
            self.colorToken = colorToken
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
}
