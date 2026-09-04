import Foundation
import SwiftData
import WellSpentWatchContracts

enum TimerRunState: String, CaseIterable, Codable, Sendable {
    case running
    case paused
    case ended
}

/// The TimerRun schema keeps every billable interval as a report-authoritative
/// session segment while adding one stable identity for the user-visible timer.
/// References remain scalar so migration and conflict recovery never depend on
/// implicit relationship deletion behavior.
enum WellSpentSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            ProjectRecord.self,
            TimeSessionRecord.self,
            SessionTagRecord.self,
            SessionTagAssignmentRecord.self,
            TimerRunRecord.self,
            TimerRunTagAssignmentRecord.self,
            TimerOriginRecord.self,
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
        var timerRunID: UUID?
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
            timerRunID: UUID? = nil,
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
            self.timerRunID = timerRunID
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

    @Model
    final class TimerRunRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var projectID: UUID = UUID()
        var stateRawValue: String = TimerRunState.running.rawValue
        var startAt: Date = Date()
        var endAt: Date?
        var startTimeZoneID: String = TimeZone.current.identifier
        var endTimeZoneID: String?
        var durationGoalSeconds: Double?
        var note: String?
        var originDeviceID: UUID = UUID()
        var revision: Int64 = 0
        var lastAppliedMutationID: UUID?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var updatedTimeZoneID: String = TimeZone.current.identifier

        var state: TimerRunState? {
            get { TimerRunState(rawValue: stateRawValue) }
            set { stateRawValue = newValue?.rawValue ?? stateRawValue }
        }

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            projectID: UUID,
            state: TimerRunState,
            startAt: Date,
            endAt: Date? = nil,
            startTimeZoneID: String,
            endTimeZoneID: String? = nil,
            durationGoalSeconds: Double? = nil,
            note: String? = nil,
            originDeviceID: UUID,
            revision: Int64,
            lastAppliedMutationID: UUID? = nil,
            createdAt: Date,
            updatedAt: Date,
            updatedTimeZoneID: String
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.projectID = projectID
            stateRawValue = state.rawValue
            self.startAt = startAt
            self.endAt = endAt
            self.startTimeZoneID = startTimeZoneID
            self.endTimeZoneID = endTimeZoneID
            self.durationGoalSeconds = durationGoalSeconds
            self.note = note
            self.originDeviceID = originDeviceID
            self.revision = revision
            self.lastAppliedMutationID = lastAppliedMutationID
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.updatedTimeZoneID = updatedTimeZoneID
        }
    }

    @Model
    final class TimerRunTagAssignmentRecord {
        var id: UUID = UUID()
        var workspaceID: UUID?
        var timerRunID: UUID = UUID()
        var tagID: UUID = UUID()
        var nameSnapshot: String = ""
        var createdAt: Date = Date()

        init(
            id: UUID = UUID(),
            workspaceID: UUID? = nil,
            timerRunID: UUID,
            tagID: UUID,
            nameSnapshot: String,
            createdAt: Date
        ) {
            self.id = id
            self.workspaceID = workspaceID
            self.timerRunID = timerRunID
            self.tagID = tagID
            self.nameSnapshot = nameSnapshot
            self.createdAt = createdAt
        }
    }

    /// One row is created on the first post-v3 local command. Imported runs use
    /// the reserved legacy origin and do not depend on a migration-time clock
    /// or random-number source.
    @Model
    final class TimerOriginRecord {
        var id: UUID = UUID()
        var createdAt: Date = Date()

        init(id: UUID, createdAt: Date) {
            self.id = id
            self.createdAt = createdAt
        }
    }

}

enum LegacyTimerRunIdentity {
    static let namespace = UUID(uuidString: "BC0DD2D9-1690-55E2-8ED4-F3383C6C472D")!
    static let legacyImportOriginDeviceID =
        UUID(uuidString: "00000000-0000-5000-8000-000000000008")!

    static func runID(for sessionID: UUID) -> UUID {
        namespacedUUID(kind: "run", sourceID: sessionID)
    }

    static func runTagAssignmentID(for sessionAssignmentID: UUID) -> UUID {
        namespacedUUID(kind: "run-tag", sourceID: sessionAssignmentID)
    }

    private static func namespacedUUID(kind: String, sourceID: UUID) -> UUID {
        var namespaceBytes = withUnsafeBytes(of: namespace.uuid) { Array($0) }
        namespaceBytes.append(contentsOf: kind.utf8)
        namespaceBytes.append(0)
        namespaceBytes.append(contentsOf: withUnsafeBytes(of: sourceID.uuid) { Array($0) })
        var bytes = Array(SHA256Digest.hashing(Data(namespaceBytes)).bytes.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x50
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(
            uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14],
                bytes[15]
            )
        )
    }
}

typealias ProjectRecord = WellSpentSchemaV3.ProjectRecord
typealias TimeSessionRecord = WellSpentSchemaV3.TimeSessionRecord
typealias SessionTagRecord = WellSpentSchemaV3.SessionTagRecord
typealias SessionTagAssignmentRecord = WellSpentSchemaV3.SessionTagAssignmentRecord
typealias TimerRunRecord = WellSpentSchemaV3.TimerRunRecord
typealias TimerRunTagAssignmentRecord = WellSpentSchemaV3.TimerRunTagAssignmentRecord
typealias TimerOriginRecord = WellSpentSchemaV3.TimerOriginRecord
