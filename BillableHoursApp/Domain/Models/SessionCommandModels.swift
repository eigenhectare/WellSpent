import Foundation

enum SessionCommandWarning: Equatable, Sendable {
    case overlaps(existingSessionIDs: [UUID])
}

struct SessionCommandResult: Equatable, Sendable {
    let session: TimeSessionSnapshot
    let warnings: [SessionCommandWarning]
}

struct SessionDeletionResult: Equatable, Sendable {
    let session: TimeSessionSnapshot
    let deletedAt: Date
}

enum SessionCommandError: Error, Equatable, Sendable {
    case projectNotFound(UUID)
    case sessionNotFound(UUID)
    case invalidTimestamp
    case startIsInFuture(Date)
    case endIsInFuture(Date)
    case endMustFollowStart(startAt: Date, endAt: Date)
    case completedSessionRequired(UUID)
    case activeTimedSessionRequired(UUID)
    case activeSessionReviewRequired(activeSessionIDs: [UUID])
    case deletionRequiresConfirmation
    case activeSessionCannotBeDeleted(UUID)
}
