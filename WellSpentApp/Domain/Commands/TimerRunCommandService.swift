import Foundation

/// The iPhone's persist-first boundary for every TimerRun transition. All
/// records touched by one logical command share one ModelContext save.
@MainActor
final class TimerRunCommandService {
    private let repository: SwiftDataTimerRunRepository
    private let dependencies: WellSpentDependencies

    init(repository: SwiftDataTimerRunRepository, dependencies: WellSpentDependencies) {
        self.repository = repository
        self.dependencies = dependencies
    }

    func reconcileActiveState() throws -> ActiveTimerRunReconciliationResult {
        try TimerRunReconciler.reconcile(repository: repository)
    }

    func allRuns() throws -> [TimerRunSnapshot] {
        var snapshots: [TimerRunSnapshot] = []
        for run in try repository.fetchRuns() where run.state != nil {
            snapshots.append(try repository.snapshot(run))
        }
        return snapshots
    }

    func run(id: UUID) throws -> TimerRunSnapshot? {
        try repository.fetchRun(resolving: id).map(repository.snapshot)
    }

    func start(
        projectID: UUID,
        durationGoalSeconds: Double? = nil,
        mutationID: UUID? = nil,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        runID requestedRunID: UUID? = nil,
        segmentID requestedSegmentID: UUID? = nil,
        originDeviceID requestedOriginDeviceID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunStartResult {
        try ensureNoUnresolvedConflict()
        let active = try activeRun()
        let project = try requiredActiveProject(id: projectID)
        try validate(goal: durationGoalSeconds)

        if let active {
            if active.projectID == projectID {
                return TimerRunStartResult(
                    run: try repository.snapshot(active),
                    disposition: isDuplicate(mutationID, for: active)
                        ? .duplicate : .alreadyCurrent
                )
            }
            throw TimerRunCommandError.runRequiresSwitch(
                runID: active.id,
                projectID: active.projectID
            )
        }

        let boundary = capturedAt ?? dependencies.now
        try validate(timestamp: boundary)
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        let runID = requestedRunID ?? dependencies.makeUUID()
        let segmentID = requestedSegmentID ?? dependencies.makeUUID()
        guard try repository.fetchRun(id: runID) == nil else {
            throw TimerRunCommandError.identityCollision(runID)
        }
        guard try repository.fetchSession(id: segmentID) == nil else {
            throw TimerRunCommandError.identityCollision(segmentID)
        }

        do {
            let originID = try requestedOriginDeviceID ?? localOriginID(createdAt: boundary)
            let run = TimerRunRecord(
                id: runID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                state: .running,
                startAt: boundary,
                startTimeZoneID: zoneID,
                durationGoalSeconds: durationGoalSeconds,
                originDeviceID: originID,
                revision: 1,
                lastAppliedMutationID: mutationID,
                createdAt: boundary,
                updatedAt: boundary,
                updatedTimeZoneID: zoneID
            )
            let segment = TimeSessionRecord(
                id: segmentID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                source: .timer,
                timerRunID: runID,
                startAt: boundary,
                startTimeZoneID: zoneID,
                createdAt: boundary,
                updatedAt: boundary
            )
            repository.insert(run)
            repository.insert(segment)
            try saveIfRequested(saveChanges)
            return TimerRunStartResult(
                run: try repository.snapshot(run),
                disposition: .started
            )
        } catch {
            repository.rollback()
            throw error
        }
    }

    func pause(
        runID: UUID,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        mutationID: UUID? = nil,
        expectedOpenSegmentID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunPauseResult {
        try ensureNoUnresolvedConflict()
        let run = try requiredRun(id: runID)
        if isDuplicate(mutationID, for: run) {
            return TimerRunPauseResult(
                run: try repository.snapshot(run),
                disposition: .duplicate
            )
        }
        guard try requiredCurrentRun().id == run.id else {
            throw TimerRunCommandError.runIsNotCurrent(run.id)
        }
        if run.state == .paused {
            return TimerRunPauseResult(
                run: try repository.snapshot(run),
                disposition: .alreadyPaused
            )
        }
        guard run.state == .running,
            let openSegment = try repository.fetchSegments(runID: run.id).first(where: {
                $0.endAt == nil
            })
        else {
            throw reviewError(runIDs: [run.id], segments: try repository.fetchSegments(runID: run.id))
        }
        if let expectedOpenSegmentID, expectedOpenSegmentID != openSegment.id {
            throw TimerRunCommandError.identityCollision(expectedOpenSegmentID)
        }

        let boundary = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: boundary)
        guard boundary > openSegment.startAt else {
            throw TimerRunCommandError.nonIncreasingBoundary(
                runID: run.id,
                requestedAt: boundary
            )
        }

        do {
            openSegment.endAt = boundary
            openSegment.endTimeZoneID = zoneID
            openSegment.updatedAt = boundary
            run.state = .paused
            try applyMutationMetadata(run, at: boundary, zoneID: zoneID, mutationID: mutationID)
            try saveIfRequested(saveChanges)
            return TimerRunPauseResult(
                run: try repository.snapshot(run),
                disposition: .paused
            )
        } catch {
            repository.rollback()
            throw error
        }
    }

    func resume(
        runID: UUID,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        mutationID: UUID? = nil,
        newSegmentID requestedSegmentID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunResumeResult {
        try ensureNoUnresolvedConflict()
        let run = try requiredRun(id: runID)
        if isDuplicate(mutationID, for: run) {
            return TimerRunResumeResult(
                run: try repository.snapshot(run),
                disposition: .duplicate
            )
        }
        guard try requiredCurrentRun().id == run.id else {
            throw TimerRunCommandError.runIsNotCurrent(run.id)
        }
        if run.state == .running {
            return TimerRunResumeResult(
                run: try repository.snapshot(run),
                disposition: .alreadyRunning
            )
        }
        guard run.state == .paused else {
            throw TimerRunCommandError.runIsNotCurrent(run.id)
        }
        let segments = try repository.fetchSegments(runID: run.id)
        guard let latestEnd = segments.compactMap(\.endAt).max() else {
            throw reviewError(runIDs: [run.id], segments: segments)
        }
        let boundary = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: boundary)
        guard boundary >= latestEnd, boundary >= run.startAt else {
            throw TimerRunCommandError.nonIncreasingBoundary(
                runID: run.id,
                requestedAt: boundary
            )
        }
        let segmentID = requestedSegmentID ?? dependencies.makeUUID()
        guard try repository.fetchSession(id: segmentID) == nil else {
            throw TimerRunCommandError.identityCollision(segmentID)
        }

        do {
            repository.insert(
                TimeSessionRecord(
                    id: segmentID,
                    workspaceID: run.workspaceID,
                    projectID: run.projectID,
                    source: .timer,
                    timerRunID: run.id,
                    startAt: boundary,
                    startTimeZoneID: zoneID,
                    note: run.note,
                    createdAt: boundary,
                    updatedAt: boundary
                )
            )
            run.state = .running
            try applyMutationMetadata(run, at: boundary, zoneID: zoneID, mutationID: mutationID)
            try projectRunTagsToAllSegments(runID: run.id, createdAt: boundary)
            try saveIfRequested(saveChanges)
            return TimerRunResumeResult(
                run: try repository.snapshot(run),
                disposition: .resumed
            )
        } catch {
            repository.rollback()
            throw error
        }
    }

    func switchTimer(
        to projectID: UUID,
        durationGoalSeconds: Double? = nil,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        mutationID: UUID? = nil,
        expectedOpenSegmentID: UUID? = nil,
        toRunID requestedRunID: UUID? = nil,
        toSegmentID requestedSegmentID: UUID? = nil,
        originDeviceID requestedOriginDeviceID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunSwitchResult {
        try ensureNoUnresolvedConflict()
        if let mutationID {
            let matches = try repository.fetchRuns().filter {
                $0.lastAppliedMutationID == mutationID
            }
            if let completed = matches.first(where: { $0.state == .ended }),
                let active = matches.first(where: {
                    $0.state == .running || $0.state == .paused
                })
            {
                return .duplicate(
                    completed: try repository.snapshot(completed),
                    active: try repository.snapshot(active)
                )
            }
        }
        let previous = try requiredCurrentRun()
        let project = try requiredActiveProject(id: projectID)
        try validate(goal: durationGoalSeconds)
        if previous.projectID == projectID {
            return .alreadyCurrent(try repository.snapshot(previous))
        }
        let segments = try repository.fetchSegments(runID: previous.id)
        let boundary = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: boundary)
        if previous.state == .running {
            guard let open = segments.first(where: { $0.endAt == nil }), boundary > open.startAt else {
                throw TimerRunCommandError.nonIncreasingBoundary(
                    runID: previous.id,
                    requestedAt: boundary
                )
            }
            if let expectedOpenSegmentID, expectedOpenSegmentID != open.id {
                throw TimerRunCommandError.identityCollision(expectedOpenSegmentID)
            }
        } else {
            if let expectedOpenSegmentID {
                throw TimerRunCommandError.identityCollision(expectedOpenSegmentID)
            }
            guard let latestEnd = segments.compactMap(\.endAt).max(), boundary >= latestEnd else {
                throw TimerRunCommandError.nonIncreasingBoundary(
                    runID: previous.id,
                    requestedAt: boundary
                )
            }
        }

        let runID = requestedRunID ?? dependencies.makeUUID()
        let segmentID = requestedSegmentID ?? dependencies.makeUUID()
        guard try repository.fetchRun(id: runID) == nil else {
            throw TimerRunCommandError.identityCollision(runID)
        }
        guard try repository.fetchSession(id: segmentID) == nil else {
            throw TimerRunCommandError.identityCollision(segmentID)
        }

        do {
            if let open = segments.first(where: { $0.endAt == nil }) {
                open.endAt = boundary
                open.endTimeZoneID = zoneID
                open.updatedAt = boundary
            }
            previous.state = .ended
            previous.endAt = boundary
            previous.endTimeZoneID = zoneID
            try applyMutationMetadata(
                previous,
                at: boundary,
                zoneID: zoneID,
                mutationID: mutationID
            )

            let originID = try requestedOriginDeviceID ?? localOriginID(createdAt: boundary)
            let active = TimerRunRecord(
                id: runID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                state: .running,
                startAt: boundary,
                startTimeZoneID: zoneID,
                durationGoalSeconds: durationGoalSeconds,
                originDeviceID: originID,
                revision: 1,
                lastAppliedMutationID: mutationID,
                createdAt: boundary,
                updatedAt: boundary,
                updatedTimeZoneID: zoneID
            )
            repository.insert(active)
            repository.insert(
                TimeSessionRecord(
                    id: segmentID,
                    workspaceID: project.workspaceID,
                    projectID: project.id,
                    source: .timer,
                    timerRunID: runID,
                    startAt: boundary,
                    startTimeZoneID: zoneID,
                    createdAt: boundary,
                    updatedAt: boundary
                )
            )
            try saveIfRequested(saveChanges)
            return .switched(
                completed: try repository.snapshot(previous),
                active: try repository.snapshot(active)
            )
        } catch {
            repository.rollback()
            throw error
        }
    }

    func end(
        runID: UUID,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        mutationID: UUID? = nil,
        expectedOpenSegmentID: UUID? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunEndResult {
        try ensureNoUnresolvedConflict()
        let run = try requiredRun(id: runID)
        if isDuplicate(mutationID, for: run) {
            return TimerRunEndResult(
                run: try repository.snapshot(run),
                disposition: .duplicate
            )
        }
        if run.state == .ended {
            return TimerRunEndResult(
                run: try repository.snapshot(run),
                disposition: .alreadyEnded
            )
        }
        guard try requiredCurrentRun().id == run.id else {
            throw TimerRunCommandError.runIsNotCurrent(run.id)
        }

        let segments = try repository.fetchSegments(runID: run.id)
        let boundary = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: boundary)
        if run.state == .running {
            guard let open = segments.first(where: { $0.endAt == nil }), boundary > open.startAt else {
                throw TimerRunCommandError.nonIncreasingBoundary(
                    runID: run.id,
                    requestedAt: boundary
                )
            }
            if let expectedOpenSegmentID, expectedOpenSegmentID != open.id {
                throw TimerRunCommandError.identityCollision(expectedOpenSegmentID)
            }
        } else {
            if let expectedOpenSegmentID {
                throw TimerRunCommandError.identityCollision(expectedOpenSegmentID)
            }
            guard let latestEnd = segments.compactMap(\.endAt).max(), boundary >= latestEnd else {
                throw TimerRunCommandError.nonIncreasingBoundary(
                    runID: run.id,
                    requestedAt: boundary
                )
            }
        }

        do {
            if let open = segments.first(where: { $0.endAt == nil }) {
                open.endAt = boundary
                open.endTimeZoneID = zoneID
                open.updatedAt = boundary
            }
            run.state = .ended
            run.endAt = boundary
            run.endTimeZoneID = zoneID
            try applyMutationMetadata(run, at: boundary, zoneID: zoneID, mutationID: mutationID)
            try saveIfRequested(saveChanges)
            return TimerRunEndResult(
                run: try repository.snapshot(run),
                disposition: .ended
            )
        } catch {
            repository.rollback()
            throw error
        }
    }

    @discardableResult
    func annotate(
        runID: UUID,
        note: String?,
        tagIDs: Set<UUID>,
        mutationID: UUID? = nil,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunSnapshot {
        try ensureNoUnresolvedConflict()
        let run = try requiredRun(id: runID)
        if isDuplicate(mutationID, for: run) { return try repository.snapshot(run) }
        let segments = try repository.fetchSegments(runID: run.id)
        let structuralReasons = TimerRunReconciler.structuralValidationReasons(
            run: run,
            segments: segments
        )
        guard structuralReasons.isEmpty else {
            throw reviewError(runIDs: [run.id], segments: segments)
        }
        let tags = try repository.fetchTags()
        let tagsByID = Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0) })
        let missing = tagIDs.filter { tagsByID[$0] == nil }.sorted { $0.uuidString < $1.uuidString }
        guard missing.isEmpty else { throw TimerRunCommandError.invalidTags(missing) }
        let normalizedNote = normalize(note)
        let currentTagIDs = Set(try repository.fetchRunTagAssignments(runID: run.id).map(\.tagID))
        let projected = try annotationsAreProjected(
            run: run,
            segments: segments,
            note: normalizedNote,
            tagIDs: tagIDs
        )
        guard run.note != normalizedNote || currentTagIDs != tagIDs || !projected else {
            return try repository.snapshot(run)
        }

        let timestamp = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: timestamp)
        do {
            run.note = normalizedNote
            for segment in segments {
                segment.note = normalizedNote
                segment.updatedAt = timestamp
            }
            try replaceRunTags(run: run, requestedTagIDs: tagIDs, tagsByID: tagsByID, at: timestamp)
            try replaceSegmentTags(
                segments: segments,
                requestedTagIDs: tagIDs,
                tagsByID: tagsByID,
                at: timestamp
            )
            try applyMutationMetadata(run, at: timestamp, zoneID: zoneID, mutationID: mutationID)
            try saveIfRequested(saveChanges)
            return try repository.snapshot(run)
        } catch {
            repository.rollback()
            throw error
        }
    }

    @discardableResult
    func setGoal(
        runID: UUID,
        durationGoalSeconds: Double?,
        mutationID: UUID? = nil,
        capturedAt: Date? = nil,
        timeZoneID: String? = nil,
        saveChanges: Bool = true
    ) throws -> TimerRunSnapshot {
        try ensureNoUnresolvedConflict()
        try validate(goal: durationGoalSeconds)
        let run = try requiredRun(id: runID)
        if isDuplicate(mutationID, for: run) || run.durationGoalSeconds == durationGoalSeconds {
            return try repository.snapshot(run)
        }
        guard run.state != .ended else { throw TimerRunCommandError.runIsNotCurrent(run.id) }
        guard try requiredCurrentRun().id == run.id else {
            throw TimerRunCommandError.runIsNotCurrent(run.id)
        }
        let timestamp = capturedAt ?? dependencies.now
        let zoneID = timeZoneID ?? dependencies.timeZone.identifier
        try validate(timestamp: timestamp)
        do {
            run.durationGoalSeconds = durationGoalSeconds
            try applyMutationMetadata(run, at: timestamp, zoneID: zoneID, mutationID: mutationID)
            try saveIfRequested(saveChanges)
            return try repository.snapshot(run)
        } catch {
            repository.rollback()
            throw error
        }
    }

    func delete(runID: UUID, confirmed: Bool) throws {
        try ensureNoUnresolvedConflict()
        guard confirmed else { throw TimerRunCommandError.deletionRequiresConfirmation }
        let run = try requiredRun(id: runID)
        guard run.state == .ended else { throw TimerRunCommandError.endedRunRequired(run.id) }
        do {
            let segments = try repository.fetchSegments(runID: run.id)
            let segmentIDs = Set(segments.map(\.id))
            for assignment in try repository.fetchSessionTagAssignments()
            where segmentIDs.contains(assignment.sessionID) {
                repository.delete(assignment)
            }
            for assignment in try repository.fetchRunTagAssignments(runID: run.id) {
                repository.delete(assignment)
            }
            for segment in segments { repository.delete(segment) }
            repository.delete(run)
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }
    }

    private func activeRun() throws -> TimerRunRecord? {
        switch try reconcileActiveState() {
        case .noActiveRun:
            return nil
        case .running(let run, _), .paused(let run):
            return try repository.fetchRun(id: run.id)
        case .reviewRequired(let runIDs, let segmentIDs, _):
            throw TimerRunCommandError.reviewRequired(runIDs: runIDs, segmentIDs: segmentIDs)
        }
    }

    private func ensureNoUnresolvedConflict() throws {
        guard try !repository.hasUnresolvedTimerConflict() else {
            throw TimerRunCommandError.reviewRequired(runIDs: [], segmentIDs: [])
        }
    }

    private func requiredCurrentRun() throws -> TimerRunRecord {
        guard let run = try activeRun() else { throw TimerRunCommandError.noActiveRun }
        return run
    }

    private func requiredRun(id: UUID) throws -> TimerRunRecord {
        guard let run = try repository.fetchRun(resolving: id) else {
            throw TimerRunCommandError.runNotFound(id)
        }
        return run
    }

    private func requiredActiveProject(id: UUID) throws -> ProjectRecord {
        guard let project = try repository.fetchProject(id: id) else {
            throw TimerRunCommandError.projectNotFound(id)
        }
        guard project.status == .active else {
            throw TimerRunCommandError.projectArchived(id)
        }
        return project
    }

    private func localOriginID(createdAt: Date) throws -> UUID {
        let origins = try repository.fetchOrigins()
        guard origins.count <= 1 else {
            throw TimerRunCommandError.reviewRequired(runIDs: [], segmentIDs: [])
        }
        if let origin = origins.first { return origin.id }
        let origin = TimerOriginRecord(id: dependencies.makeUUID(), createdAt: createdAt)
        repository.insert(origin)
        return origin.id
    }

    private func applyMutationMetadata(
        _ run: TimerRunRecord,
        at timestamp: Date,
        zoneID: String,
        mutationID: UUID?
    ) throws {
        guard run.revision >= 0, run.revision < Int64.max else {
            throw TimerRunCommandError.invalidRevision
        }
        run.revision += 1
        run.lastAppliedMutationID = mutationID
        run.updatedAt = timestamp
        run.updatedTimeZoneID = zoneID
    }

    private func saveIfRequested(_ saveChanges: Bool) throws {
        if saveChanges {
            try repository.save()
        }
    }

    private func isDuplicate(_ mutationID: UUID?, for run: TimerRunRecord) -> Bool {
        mutationID != nil && run.lastAppliedMutationID == mutationID
    }

    private func validate(timestamp: Date) throws {
        guard timestamp.timeIntervalSinceReferenceDate.isFinite else {
            throw TimerRunCommandError.invalidTimestamp
        }
    }

    private func validate(goal: Double?) throws {
        guard let goal else { return }
        guard goal.isFinite, goal > 0 else { throw TimerRunCommandError.invalidGoal }
    }

    private func normalize(_ note: String?) -> String? {
        guard let note else { return nil }
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func reviewError(
        runIDs: [UUID],
        segments: [TimeSessionRecord]
    ) -> TimerRunCommandError {
        .reviewRequired(
            runIDs: runIDs,
            segmentIDs: segments.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )
    }

    private func annotationsAreProjected(
        run: TimerRunRecord,
        segments: [TimeSessionRecord],
        note: String?,
        tagIDs: Set<UUID>
    ) throws -> Bool {
        guard run.note == note, segments.allSatisfy({ $0.note == note }) else { return false }
        for segment in segments {
            let projectedIDs = Set(
                try repository.fetchSessionTagAssignments(sessionID: segment.id).map(\.tagID)
            )
            if projectedIDs != tagIDs { return false }
        }
        return true
    }

    private func replaceRunTags(
        run: TimerRunRecord,
        requestedTagIDs: Set<UUID>,
        tagsByID: [UUID: SessionTagRecord],
        at timestamp: Date
    ) throws {
        for assignment in try repository.fetchRunTagAssignments(runID: run.id) {
            repository.delete(assignment)
        }
        for tagID in requestedTagIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
            guard let tag = tagsByID[tagID] else { continue }
            repository.insert(
                TimerRunTagAssignmentRecord(
                    id: dependencies.makeUUID(),
                    workspaceID: run.workspaceID,
                    timerRunID: run.id,
                    tagID: tag.id,
                    nameSnapshot: tag.name,
                    createdAt: timestamp
                )
            )
        }
    }

    private func replaceSegmentTags(
        segments: [TimeSessionRecord],
        requestedTagIDs: Set<UUID>,
        tagsByID: [UUID: SessionTagRecord],
        at timestamp: Date
    ) throws {
        let segmentIDs = Set(segments.map(\.id))
        for assignment in try repository.fetchSessionTagAssignments()
        where segmentIDs.contains(assignment.sessionID) {
            repository.delete(assignment)
        }
        for segment in segments {
            for tagID in requestedTagIDs.sorted(by: { $0.uuidString < $1.uuidString }) {
                guard let tag = tagsByID[tagID] else { continue }
                repository.insert(
                    SessionTagAssignmentRecord(
                        id: dependencies.makeUUID(),
                        workspaceID: segment.workspaceID,
                        sessionID: segment.id,
                        tagID: tag.id,
                        nameSnapshot: tag.name,
                        createdAt: timestamp
                    )
                )
            }
        }
    }

    private func projectRunTagsToAllSegments(runID: UUID, createdAt: Date) throws {
        let assignments = try repository.fetchRunTagAssignments(runID: runID)
        guard !assignments.isEmpty else { return }
        let segments = try repository.fetchSegments(runID: runID)
        for segment in segments {
            let existing = Set(
                try repository.fetchSessionTagAssignments(sessionID: segment.id).map(\.tagID)
            )
            for assignment in assignments where !existing.contains(assignment.tagID) {
                repository.insert(
                    SessionTagAssignmentRecord(
                        id: dependencies.makeUUID(),
                        workspaceID: segment.workspaceID,
                        sessionID: segment.id,
                        tagID: assignment.tagID,
                        nameSnapshot: assignment.nameSnapshot,
                        createdAt: createdAt
                    )
                )
            }
        }
    }
}
