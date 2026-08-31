import Foundation

@MainActor
final class SessionCommandService {
    private let repository: any SessionRepository
    private let tagRepository: (any SessionTagRepository)?
    private let dependencies: WellSpentDependencies
    private let overlapDetector = SessionOverlapDetector()

    init(
        repository: any SessionRepository,
        tagRepository: (any SessionTagRepository)? = nil,
        dependencies: WellSpentDependencies
    ) {
        self.repository = repository
        self.tagRepository = tagRepository
        self.dependencies = dependencies
    }

    /// Lets an editor present overlap warnings before save. Mutation commands
    /// repeat the same validation so this preview is never the safety boundary.
    func validateCompletedSession(
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        excludingSessionID: UUID? = nil
    ) throws -> [SessionCommandWarning] {
        let now = dependencies.now
        try validateCompletedInterval(startAt: startAt, endAt: endAt, now: now)
        _ = try requiredProject(id: projectID)
        return try overlapWarnings(
            startAt: startAt,
            endAt: endAt,
            activeEndAt: now,
            excludingSessionID: excludingSessionID
        )
    }

    func createManual(
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        note: String? = nil,
        tagIDs: Set<UUID> = []
    ) throws -> SessionCommandResult {
        let timestamp = dependencies.now
        try validateCompletedInterval(startAt: startAt, endAt: endAt, now: timestamp)
        let project = try requiredProject(id: projectID)
        let warnings = try overlapWarnings(
            startAt: startAt,
            endAt: endAt,
            activeEndAt: timestamp
        )
        let timeZoneID = dependencies.timeZone.identifier
        let session = TimeSessionRecord(
            id: dependencies.makeUUID(),
            workspaceID: project.workspaceID,
            projectID: project.id,
            source: .manual,
            startAt: startAt,
            endAt: endAt,
            startTimeZoneID: timeZoneID,
            endTimeZoneID: timeZoneID,
            note: normalize(note: note),
            createdAt: timestamp,
            updatedAt: timestamp
        )

        repository.insert(session)
        let assignedTags = try replaceTagAssignments(
            session: session,
            requestedTagIDs: tagIDs
        )
        try saveOrRollback()

        return SessionCommandResult(
            session: TimeSessionSnapshot(record: session, tags: assignedTags),
            warnings: warnings
        )
    }

    func editCompleted(
        sessionID: UUID,
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        note: String?,
        tagIDs: Set<UUID>? = nil
    ) throws -> SessionCommandResult {
        let timestamp = dependencies.now
        try validateCompletedInterval(startAt: startAt, endAt: endAt, now: timestamp)
        let session = try requiredSession(id: sessionID)
        guard session.endAt != nil else {
            throw SessionCommandError.completedSessionRequired(sessionID)
        }
        let project = try requiredProject(id: projectID)
        let warnings = try overlapWarnings(
            startAt: startAt,
            endAt: endAt,
            activeEndAt: timestamp,
            excludingSessionID: sessionID
        )
        let normalizedNote = normalize(note: note)
        let existingTagAssignments = try tagRepository?.fetchAssignments(sessionID: sessionID) ?? []
        let existingTagIDs = Set(existingTagAssignments.map(\.tagID))
        let requestedTagIDs = tagIDs ?? existingTagIDs
        let startChanged = session.startAt != startAt
        let endChanged = session.endAt != endAt
        let changed =
            session.projectID != project.id || session.workspaceID != project.workspaceID
            || startChanged || endChanged || session.note != normalizedNote
            || existingTagIDs != requestedTagIDs

        guard changed else {
            return SessionCommandResult(
                session: TimeSessionSnapshot(
                    record: session,
                    tags: snapshots(for: existingTagAssignments)
                ),
                warnings: warnings
            )
        }

        let editedTimeZoneID =
            startChanged || endChanged ? dependencies.timeZone.identifier : nil
        session.workspaceID = project.workspaceID
        session.projectID = project.id
        session.startAt = startAt
        session.endAt = endAt
        if startChanged, let editedTimeZoneID {
            session.startTimeZoneID = editedTimeZoneID
        }
        if endChanged, let editedTimeZoneID {
            session.endTimeZoneID = editedTimeZoneID
        }
        session.note = normalizedNote
        session.updatedAt = timestamp
        let assignedTags = try replaceTagAssignments(
            session: session,
            requestedTagIDs: requestedTagIDs,
            existingAssignments: existingTagAssignments
        )
        try saveOrRollback()

        return SessionCommandResult(
            session: TimeSessionSnapshot(record: session, tags: assignedTags),
            warnings: warnings
        )
    }

    func editActive(
        sessionID: UUID,
        startAt: Date,
        note: String?
    ) throws -> SessionCommandResult {
        let timestamp = dependencies.now
        try validateActiveStart(startAt, now: timestamp)
        let session = try requiredSession(id: sessionID)
        guard session.source == .timer, session.endAt == nil else {
            throw SessionCommandError.activeTimedSessionRequired(sessionID)
        }
        try requireSoleActiveTimedSession(session)
        let warnings = try overlapWarnings(
            startAt: startAt,
            endAt: nil,
            activeEndAt: timestamp,
            excludingSessionID: sessionID
        )
        let normalizedNote = normalize(note: note)
        let startChanged = session.startAt != startAt
        let changed = startChanged || session.note != normalizedNote

        guard changed else {
            return SessionCommandResult(
                session: TimeSessionSnapshot(record: session),
                warnings: warnings
            )
        }

        session.startAt = startAt
        if startChanged {
            session.startTimeZoneID = dependencies.timeZone.identifier
        }
        session.note = normalizedNote
        session.updatedAt = timestamp
        try saveOrRollback()

        return SessionCommandResult(
            session: TimeSessionSnapshot(record: session),
            warnings: warnings
        )
    }

    func delete(sessionID: UUID, confirmed: Bool) throws -> SessionDeletionResult {
        guard confirmed else {
            throw SessionCommandError.deletionRequiresConfirmation
        }
        let session = try requiredSession(id: sessionID)
        guard session.endAt != nil else {
            throw SessionCommandError.activeSessionCannotBeDeleted(sessionID)
        }

        let deletedAt = dependencies.now
        session.updatedAt = deletedAt
        let tagAssignments = try tagRepository?.fetchAssignments(sessionID: sessionID) ?? []
        let snapshot = TimeSessionSnapshot(
            record: session,
            tags: snapshots(for: tagAssignments)
        )
        for assignment in tagAssignments {
            tagRepository?.delete(assignment)
        }
        repository.delete(session)
        try saveOrRollback()

        return SessionDeletionResult(session: snapshot, deletedAt: deletedAt)
    }

    private func requiredProject(id: UUID) throws -> ProjectRecord {
        guard let project = try repository.fetchProject(id: id) else {
            throw SessionCommandError.projectNotFound(id)
        }
        return project
    }

    private func requiredSession(id: UUID) throws -> TimeSessionRecord {
        guard let session = try repository.fetchSession(id: id) else {
            throw SessionCommandError.sessionNotFound(id)
        }
        return session
    }

    private func validateCompletedInterval(startAt: Date, endAt: Date, now: Date) throws {
        try validateTimestamp(startAt)
        try validateTimestamp(endAt)
        guard startAt <= now else {
            throw SessionCommandError.startIsInFuture(startAt)
        }
        guard endAt <= now else {
            throw SessionCommandError.endIsInFuture(endAt)
        }
        guard endAt > startAt else {
            throw SessionCommandError.endMustFollowStart(startAt: startAt, endAt: endAt)
        }
    }

    private func validateActiveStart(_ startAt: Date, now: Date) throws {
        try validateTimestamp(startAt)
        guard startAt <= now else {
            throw SessionCommandError.startIsInFuture(startAt)
        }
    }

    private func validateTimestamp(_ timestamp: Date) throws {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw SessionCommandError.invalidTimestamp
        }
    }

    private func requireSoleActiveTimedSession(_ session: TimeSessionRecord) throws {
        let activeSessions = try repository.fetchSessions().filter {
            $0.source == .timer && $0.endAt == nil
        }
        guard activeSessions.count == 1, activeSessions[0].id == session.id else {
            throw SessionCommandError.activeSessionReviewRequired(
                activeSessionIDs: activeSessions.map(\.id)
            )
        }
    }

    private func overlapWarnings(
        startAt: Date,
        endAt: Date?,
        activeEndAt: Date,
        excludingSessionID: UUID? = nil
    ) throws -> [SessionCommandWarning] {
        let intervals = try repository.fetchSessions().map { session in
            SessionInterval(
                sessionID: session.id,
                startAt: session.startAt,
                endAt: session.endAt
            )
        }
        let overlappingIDs = overlapDetector.overlappingSessionIDs(
            startAt: startAt,
            endAt: endAt,
            in: intervals,
            activeEndAt: activeEndAt,
            excludingSessionID: excludingSessionID
        )

        return overlappingIDs.isEmpty ? [] : [.overlaps(existingSessionIDs: overlappingIDs)]
    }

    private func normalize(note: String?) -> String? {
        guard let note else {
            return nil
        }
        let normalizedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedNote.isEmpty ? nil : normalizedNote
    }

    private func replaceTagAssignments(
        session: TimeSessionRecord,
        requestedTagIDs: Set<UUID>,
        existingAssignments suppliedAssignments: [SessionTagAssignmentRecord]? = nil
    ) throws -> [SessionTagAssignmentSnapshot] {
        guard let tagRepository else {
            if let missingID = requestedTagIDs.first {
                throw SessionTagCommandError.tagNotFound(missingID)
            }
            return []
        }

        let tags = try tagRepository.fetchTags()
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        if let missingID = requestedTagIDs.first(where: { tagsByID[$0] == nil }) {
            throw SessionTagCommandError.tagNotFound(missingID)
        }

        let existingAssignments =
            try suppliedAssignments
            ?? tagRepository.fetchAssignments(sessionID: session.id)
        var retainedTagIDs = Set<UUID>()
        for assignment in existingAssignments {
            if requestedTagIDs.contains(assignment.tagID),
                retainedTagIDs.insert(assignment.tagID).inserted
            {
                continue
            }
            tagRepository.delete(assignment)
        }

        for tag in tags where requestedTagIDs.contains(tag.id) && !retainedTagIDs.contains(tag.id) {
            tagRepository.insert(
                SessionTagAssignmentRecord(
                    id: dependencies.makeUUID(),
                    workspaceID: session.workspaceID,
                    sessionID: session.id,
                    tagID: tag.id,
                    nameSnapshot: tag.name,
                    createdAt: dependencies.now
                )
            )
        }

        return tags.compactMap { tag in
            guard requestedTagIDs.contains(tag.id) else { return nil }
            return SessionTagAssignmentSnapshot(tagID: tag.id, name: tag.name)
        }
    }

    private func snapshots(
        for assignments: [SessionTagAssignmentRecord]
    ) -> [SessionTagAssignmentSnapshot] {
        assignments
            .map(SessionTagAssignmentSnapshot.init(record:))
            .sorted {
                if $0.name != $1.name {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.tagID.uuidString < $1.tagID.uuidString
            }
    }

    private func saveOrRollback() throws {
        do {
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }
    }
}
