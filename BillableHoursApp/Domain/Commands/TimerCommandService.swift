import Foundation

/// Serializes timer commands on the main actor so two in-process Start calls
/// cannot both observe an empty active-session set.
@MainActor
final class TimerCommandService {
    private let repository: any TimerRepository
    private let dependencies: BillableHoursDependencies

    init(repository: any TimerRepository, dependencies: BillableHoursDependencies) {
        self.repository = repository
        self.dependencies = dependencies
    }

    /// Reconstructs the authoritative active state exclusively from persisted
    /// timestamps. Malformed conflicts are classified, never guessed away.
    func reconcileActiveState() throws -> ActiveSessionReconciliationResult {
        try inspectActiveState().result
    }

    func start(projectID: UUID) throws -> TimerStartResult {
        let activeState = try inspectActiveState()
        guard let project = try repository.fetchProject(id: projectID) else {
            throw TimerCommandError.projectNotFound(projectID)
        }
        guard project.status == .active else {
            throw TimerCommandError.projectArchived(projectID)
        }

        if let activeSession = try usableActiveSession(from: activeState) {
            guard activeSession.projectID == projectID else {
                throw TimerCommandError.activeSessionRequiresSwitch(
                    sessionID: activeSession.id,
                    projectID: activeSession.projectID
                )
            }
            return TimerStartResult(
                session: TimeSessionSnapshot(record: activeSession),
                disposition: .alreadyActive
            )
        }

        let timestamp = dependencies.now
        let session = TimeSessionRecord(
            id: dependencies.makeUUID(),
            workspaceID: project.workspaceID,
            projectID: project.id,
            source: .timer,
            startAt: timestamp,
            startTimeZoneID: dependencies.timeZone.identifier,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        repository.insert(session)
        do {
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }

        return TimerStartResult(
            session: TimeSessionSnapshot(record: session),
            disposition: .started
        )
    }

    func switchTimer(to projectID: UUID) throws -> TimerSwitchResult {
        let activeState = try inspectActiveState()
        guard let project = try repository.fetchProject(id: projectID) else {
            throw TimerCommandError.projectNotFound(projectID)
        }
        guard project.status == .active else {
            throw TimerCommandError.projectArchived(projectID)
        }

        guard let previousSession = try usableActiveSession(from: activeState) else {
            throw TimerCommandError.noActiveTimedSession
        }
        guard previousSession.projectID != projectID else {
            return .alreadyActive(TimeSessionSnapshot(record: previousSession))
        }

        let boundary = dependencies.now
        guard boundary > previousSession.startAt else {
            throw TimerCommandError.nonIncreasingBoundary(
                sessionID: previousSession.id,
                startAt: previousSession.startAt,
                requestedEndAt: boundary
            )
        }
        let boundaryTimeZoneID = dependencies.timeZone.identifier
        let newSession = TimeSessionRecord(
            id: dependencies.makeUUID(),
            workspaceID: project.workspaceID,
            projectID: project.id,
            source: .timer,
            startAt: boundary,
            startTimeZoneID: boundaryTimeZoneID,
            createdAt: boundary,
            updatedAt: boundary
        )

        previousSession.endAt = boundary
        previousSession.endTimeZoneID = boundaryTimeZoneID
        previousSession.updatedAt = boundary
        repository.insert(newSession)

        do {
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }

        return .switched(
            completedSession: TimeSessionSnapshot(record: previousSession),
            activeSession: TimeSessionSnapshot(record: newSession)
        )
    }

    /// Stops the currently active timer for foreground callers. Callers that
    /// already know the session identity should use `stop(sessionID:)` so a
    /// retry can resolve the completed record after it is no longer active.
    func stopActive() throws -> TimerStopResult {
        let activeState = try inspectActiveState()
        guard let activeSession = try usableActiveSession(from: activeState) else {
            throw TimerCommandError.noActiveTimedSession
        }
        return try stopActiveSession(activeSession)
    }

    /// The path-independent idempotency key is the persisted session UUID.
    /// App and App Intent callers must pass the same ID for retry behavior.
    func stop(sessionID: UUID) throws -> TimerStopResult {
        try stopResolved(sessionID: sessionID, capturedBoundary: nil)
    }

    /// Applies a stop timestamp captured by another trusted process. This is
    /// the production App Intent handoff path; retries preserve the first
    /// persisted end timestamp and never sample a replacement `now` value.
    func stop(
        sessionID: UUID,
        capturedAt: Date,
        endTimeZoneID: String
    ) throws -> TimerStopResult {
        try stopResolved(
            sessionID: sessionID,
            capturedBoundary: (capturedAt, endTimeZoneID)
        )
    }

    private func stopResolved(
        sessionID: UUID,
        capturedBoundary: (Date, String)?
    ) throws -> TimerStopResult {
        let activeState = try inspectActiveState()
        guard let session = try repository.fetchSession(id: sessionID) else {
            throw TimerCommandError.sessionNotFound(sessionID)
        }
        guard session.source == .timer else {
            throw TimerCommandError.sessionIsNotTimed(sessionID)
        }
        if session.endAt != nil {
            return TimerStopResult(
                session: TimeSessionSnapshot(record: session),
                disposition: .alreadyStopped
            )
        }

        guard let activeSession = try usableActiveSession(from: activeState) else {
            throw TimerCommandError.noActiveTimedSession
        }
        guard activeSession.id == sessionID else {
            throw TimerCommandError.sessionIsNotActive(sessionID)
        }
        let boundary = capturedBoundary ?? (dependencies.now, dependencies.timeZone.identifier)
        return try stopActiveSession(
            session,
            endAt: boundary.0,
            endTimeZoneID: boundary.1
        )
    }

    private func inspectActiveState() throws -> ActiveSessionInspection {
        let activeSessions = try repository.fetchActiveTimedSessions().sorted {
            if $0.startAt != $1.startAt {
                return $0.startAt < $1.startAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }

        guard let activeSession = activeSessions.last else {
            return ActiveSessionInspection(result: .noActiveSession, activeSession: nil)
        }
        guard activeSessions.count > 1 else {
            return ActiveSessionInspection(
                result: .active(TimeSessionSnapshot(record: activeSession)),
                activeSession: activeSession
            )
        }

        let conflictingSessions = activeSessions.dropLast()
        return ActiveSessionInspection(
            result: .reviewRequired(
                activeSession: TimeSessionSnapshot(record: activeSession),
                conflictingSessions: conflictingSessions.map {
                    TimeSessionSnapshot(record: $0)
                }
            ),
            activeSession: activeSession
        )
    }

    private func usableActiveSession(
        from inspection: ActiveSessionInspection
    ) throws -> TimeSessionRecord? {
        guard
            case .reviewRequired(let activeSession, let conflictingSessions) = inspection.result
        else {
            return inspection.activeSession
        }

        throw TimerCommandError.activeSessionReviewRequired(
            activeSessionID: activeSession.id,
            conflictingSessionIDs: conflictingSessions.map(\.id)
        )
    }

    private func stopActiveSession(_ session: TimeSessionRecord) throws -> TimerStopResult {
        try stopActiveSession(
            session,
            endAt: dependencies.now,
            endTimeZoneID: dependencies.timeZone.identifier
        )
    }

    private func stopActiveSession(
        _ session: TimeSessionRecord,
        endAt: Date,
        endTimeZoneID: String
    ) throws -> TimerStopResult {
        guard endAt > session.startAt else {
            throw TimerCommandError.nonIncreasingBoundary(
                sessionID: session.id,
                startAt: session.startAt,
                requestedEndAt: endAt
            )
        }

        session.endAt = endAt
        session.endTimeZoneID = endTimeZoneID
        session.updatedAt = endAt
        do {
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }

        return TimerStopResult(
            session: TimeSessionSnapshot(record: session),
            disposition: .stopped
        )
    }
}

@MainActor
private struct ActiveSessionInspection {
    let result: ActiveSessionReconciliationResult
    let activeSession: TimeSessionRecord?
}
