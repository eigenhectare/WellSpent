import Foundation

struct TimerRunSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID?
    let projectID: UUID
    let state: TimerRunState
    let startAt: Date
    let endAt: Date?
    let startTimeZoneID: String
    let endTimeZoneID: String?
    let durationGoalSeconds: Double?
    let note: String?
    let originDeviceID: UUID
    let revision: Int64
    let lastAppliedMutationID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let updatedTimeZoneID: String
    let segments: [TimeSessionSnapshot]
    let tags: [SessionTagAssignmentSnapshot]

    var currentSegment: TimeSessionSnapshot? {
        segments.first { $0.endAt == nil }
    }

    func countedDuration(at date: Date) -> TimeInterval {
        segments.reduce(0) { partial, segment in
            partial + (segment.endAt ?? date).timeIntervalSince(segment.startAt)
        }
    }

    func pausedDuration(at date: Date) -> TimeInterval {
        max(0, (endAt ?? date).timeIntervalSince(startAt) - countedDuration(at: date))
    }

    func goalProgress(at date: Date) -> Double? {
        durationGoalSeconds.map { countedDuration(at: date) / $0 }
    }
}

enum TimerRunStartDisposition: Equatable, Sendable {
    case started
    case alreadyCurrent
    case duplicate
}

struct TimerRunStartResult: Equatable, Sendable {
    let run: TimerRunSnapshot
    let disposition: TimerRunStartDisposition
}

enum TimerRunPauseDisposition: Equatable, Sendable {
    case paused
    case alreadyPaused
    case duplicate
}

struct TimerRunPauseResult: Equatable, Sendable {
    let run: TimerRunSnapshot
    let disposition: TimerRunPauseDisposition
}

enum TimerRunResumeDisposition: Equatable, Sendable {
    case resumed
    case alreadyRunning
    case duplicate
}

struct TimerRunResumeResult: Equatable, Sendable {
    let run: TimerRunSnapshot
    let disposition: TimerRunResumeDisposition
}

enum TimerRunEndDisposition: Equatable, Sendable {
    case ended
    case alreadyEnded
    case duplicate
}

struct TimerRunEndResult: Equatable, Sendable {
    let run: TimerRunSnapshot
    let disposition: TimerRunEndDisposition
}

enum TimerRunSwitchResult: Equatable, Sendable {
    case switched(completed: TimerRunSnapshot, active: TimerRunSnapshot)
    case alreadyCurrent(TimerRunSnapshot)
    case duplicate(completed: TimerRunSnapshot, active: TimerRunSnapshot)
}

enum TimerRunReconciliationReason: String, CaseIterable, Equatable, Sendable {
    case multipleNonEndedRuns
    case unknownState
    case stateEndMismatch
    case missingRun
    case unexpectedRunOnManualSession
    case missingOrExtraOpenSegment
    case mixedProjectOrWorkspace
    case invalidBoundary
    case overlappingSegments
    case annotationDivergence
    case invalidGoal
    case invalidRevision
}

enum ActiveTimerRunReconciliationResult: Equatable, Sendable {
    case noActiveRun
    case running(run: TimerRunSnapshot, openSegment: TimeSessionSnapshot)
    case paused(run: TimerRunSnapshot)
    case reviewRequired(
        candidateRunIDs: [UUID],
        segmentIDs: [UUID],
        reasons: [TimerRunReconciliationReason]
    )
}

enum TimerRunCommandError: Error, Equatable, Sendable {
    case projectNotFound(UUID)
    case projectArchived(UUID)
    case runNotFound(UUID)
    case noActiveRun
    case runRequiresSwitch(runID: UUID, projectID: UUID)
    case runIsNotCurrent(UUID)
    case reviewRequired(runIDs: [UUID], segmentIDs: [UUID])
    case nonIncreasingBoundary(runID: UUID, requestedAt: Date)
    case invalidTimestamp
    case invalidGoal
    case invalidTags([UUID])
    case invalidRevision
    case identityCollision(UUID)
    case endedRunRequired(UUID)
    case deletionRequiresConfirmation
}
