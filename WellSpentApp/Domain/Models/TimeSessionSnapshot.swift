import Foundation

struct TimeSessionSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID?
    let projectID: UUID
    let source: TimeSessionSource
    let startAt: Date
    let endAt: Date?
    let startTimeZoneID: String
    let endTimeZoneID: String?
    let note: String?
    let tags: [SessionTagAssignmentSnapshot]
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        workspaceID: UUID? = nil,
        projectID: UUID,
        source: TimeSessionSource,
        startAt: Date,
        endAt: Date?,
        startTimeZoneID: String,
        endTimeZoneID: String? = nil,
        note: String? = nil,
        tags: [SessionTagAssignmentSnapshot] = [],
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.workspaceID = workspaceID
        self.projectID = projectID
        self.source = source
        self.startAt = startAt
        self.endAt = endAt
        self.startTimeZoneID = startTimeZoneID
        self.endTimeZoneID = endTimeZoneID
        self.note = note
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(
        record: TimeSessionRecord,
        tags: [SessionTagAssignmentSnapshot] = []
    ) {
        id = record.id
        workspaceID = record.workspaceID
        projectID = record.projectID
        source = record.source
        startAt = record.startAt
        endAt = record.endAt
        startTimeZoneID = record.startTimeZoneID
        endTimeZoneID = record.endTimeZoneID
        note = record.note
        self.tags = tags
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }
}

enum TimerStartDisposition: Equatable, Sendable {
    case started
    case alreadyActive
}

struct TimerStartResult: Equatable, Sendable {
    let session: TimeSessionSnapshot
    let disposition: TimerStartDisposition
}

enum TimerSwitchResult: Equatable, Sendable {
    case switched(completedSession: TimeSessionSnapshot, activeSession: TimeSessionSnapshot)
    case alreadyActive(TimeSessionSnapshot)
}

enum TimerStopDisposition: Equatable, Hashable, Sendable {
    case stopped
    case alreadyStopped
}

struct TimerStopResult: Equatable, Sendable {
    let session: TimeSessionSnapshot
    let disposition: TimerStopDisposition
}

enum ActiveSessionReconciliationResult: Equatable, Sendable {
    case noActiveSession
    case active(TimeSessionSnapshot)
    case reviewRequired(
        activeSession: TimeSessionSnapshot,
        conflictingSessions: [TimeSessionSnapshot]
    )
}

enum TimerCommandError: Error, Equatable, Sendable {
    case projectNotFound(UUID)
    case projectArchived(UUID)
    case sessionNotFound(UUID)
    case sessionIsNotTimed(UUID)
    case noActiveTimedSession
    case sessionIsNotActive(UUID)
    case activeSessionRequiresSwitch(sessionID: UUID, projectID: UUID)
    case activeSessionReviewRequired(activeSessionID: UUID, conflictingSessionIDs: [UUID])
    case nonIncreasingBoundary(sessionID: UUID, startAt: Date, requestedEndAt: Date)
}
