import Foundation

@MainActor
enum TimerRunReconciler {
    static func reconcile(
        repository: SwiftDataTimerRunRepository
    ) throws -> ActiveTimerRunReconciliationResult {
        let runs = try repository.fetchRuns()
        let sessions = try repository.fetchSessions()
        let runAssignments = try repository.fetchRunTagAssignments()
        let sessionAssignments = try repository.fetchSessionTagAssignments()
        let runIDs = Set(runs.map(\.id))

        var candidateRunIDs = Set<UUID>()
        var segmentIDs = Set<UUID>()
        var reasons = Set<TimerRunReconciliationReason>()

        for session in sessions {
            if session.source == .manual, session.timerRunID != nil {
                segmentIDs.insert(session.id)
                reasons.insert(.unexpectedRunOnManualSession)
            }
            if session.source == .timer {
                guard let timerRunID = session.timerRunID, runIDs.contains(timerRunID) else {
                    if let timerRunID = session.timerRunID { candidateRunIDs.insert(timerRunID) }
                    segmentIDs.insert(session.id)
                    reasons.insert(.missingRun)
                    continue
                }
            }
        }

        let nonEndedRuns = runs.filter { run in
            run.state == .running || run.state == .paused
        }
        if nonEndedRuns.count > 1 {
            candidateRunIDs.formUnion(nonEndedRuns.map(\.id))
            let conflictingRunIDs = Set(nonEndedRuns.map(\.id))
            segmentIDs.formUnion(
                sessions.compactMap { session in
                    guard let runID = session.timerRunID,
                        conflictingRunIDs.contains(runID)
                    else { return nil }
                    return session.id
                }
            )
            reasons.insert(.multipleNonEndedRuns)
        }

        let runAssignmentsByRun = Dictionary(grouping: runAssignments, by: \.timerRunID)
        let sessionAssignmentsBySession = Dictionary(grouping: sessionAssignments, by: \.sessionID)

        for run in runs {
            let ownedSegments =
                sessions
                .filter { $0.timerRunID == run.id }
                .sorted(by: segmentOrder)
            let runReasons = validationReasons(
                run: run,
                segments: ownedSegments,
                runAssignments: runAssignmentsByRun[run.id] ?? [],
                sessionAssignmentsBySession: sessionAssignmentsBySession
            )
            guard !runReasons.isEmpty else { continue }
            candidateRunIDs.insert(run.id)
            segmentIDs.formUnion(ownedSegments.map(\.id))
            reasons.formUnion(runReasons)
        }

        if !reasons.isEmpty {
            return .reviewRequired(
                candidateRunIDs: candidateRunIDs.sorted(by: uuidOrder),
                segmentIDs: segmentIDs.sorted(by: uuidOrder),
                reasons: reasons.sorted { $0.rawValue < $1.rawValue }
            )
        }

        guard let active = nonEndedRuns.first else { return .noActiveRun }
        let snapshot = try repository.snapshot(active)
        switch snapshot.state {
        case .running:
            guard let openSegment = snapshot.currentSegment else {
                return .reviewRequired(
                    candidateRunIDs: [snapshot.id],
                    segmentIDs: snapshot.segments.map(\.id),
                    reasons: [.missingOrExtraOpenSegment]
                )
            }
            return .running(run: snapshot, openSegment: openSegment)
        case .paused:
            return .paused(run: snapshot)
        case .ended:
            return .noActiveRun
        }
    }

    static func structuralValidationReasons(
        run: TimerRunRecord,
        segments: [TimeSessionRecord]
    ) -> Set<TimerRunReconciliationReason> {
        validationReasons(
            run: run,
            segments: segments.sorted(by: segmentOrder),
            runAssignments: [],
            sessionAssignmentsBySession: [:],
            checksAnnotations: false
        )
    }

    private static func validationReasons(
        run: TimerRunRecord,
        segments: [TimeSessionRecord],
        runAssignments: [TimerRunTagAssignmentRecord],
        sessionAssignmentsBySession: [UUID: [SessionTagAssignmentRecord]],
        checksAnnotations: Bool = true
    ) -> Set<TimerRunReconciliationReason> {
        var reasons = Set<TimerRunReconciliationReason>()
        guard let state = run.state else {
            reasons.insert(.unknownState)
            return reasons
        }
        if run.revision < 0 { reasons.insert(.invalidRevision) }
        if let goal = run.durationGoalSeconds, !goal.isFinite || goal <= 0 {
            reasons.insert(.invalidGoal)
        }
        if !isFinite(run.startAt) || run.endAt.map({ !isFinite($0) }) == true {
            reasons.insert(.invalidBoundary)
        }
        if segments.isEmpty || segments.first?.startAt != run.startAt {
            reasons.insert(.invalidBoundary)
        }

        let openSegments = segments.filter { $0.endAt == nil }
        switch state {
        case .running:
            if run.endAt != nil || run.endTimeZoneID != nil {
                reasons.insert(.stateEndMismatch)
            }
            if openSegments.count != 1 || openSegments.first?.id != segments.last?.id {
                reasons.insert(.missingOrExtraOpenSegment)
            }
        case .paused:
            if run.endAt != nil || run.endTimeZoneID != nil {
                reasons.insert(.stateEndMismatch)
            }
            if !openSegments.isEmpty { reasons.insert(.missingOrExtraOpenSegment) }
        case .ended:
            if run.endAt == nil || run.endTimeZoneID == nil {
                reasons.insert(.stateEndMismatch)
            }
            if !openSegments.isEmpty { reasons.insert(.missingOrExtraOpenSegment) }
            if let endAt = run.endAt, let lastEnd = segments.last?.endAt, endAt < lastEnd {
                reasons.insert(.invalidBoundary)
            }
        }

        for (index, segment) in segments.enumerated() {
            if segment.source != .timer || segment.timerRunID != run.id
                || segment.projectID != run.projectID || segment.workspaceID != run.workspaceID
            {
                reasons.insert(.mixedProjectOrWorkspace)
            }
            if !isFinite(segment.startAt)
                || segment.endAt.map({ !isFinite($0) || $0 <= segment.startAt }) == true
            {
                reasons.insert(.invalidBoundary)
            }
            if index > 0, let priorEnd = segments[index - 1].endAt,
                segment.startAt < priorEnd
            {
                reasons.insert(.overlappingSegments)
            }
            if checksAnnotations, segment.note != run.note {
                reasons.insert(.annotationDivergence)
            }
        }

        if checksAnnotations {
            let runTags = tagProjection(runAssignments)
            for segment in segments {
                let segmentTags = tagProjection(sessionAssignmentsBySession[segment.id] ?? [])
                if runTags != segmentTags { reasons.insert(.annotationDivergence) }
            }
        }
        return reasons
    }

    private static func tagProjection(
        _ assignments: [TimerRunTagAssignmentRecord]
    ) -> [UUID: String] {
        assignments.reduce(into: [:]) { result, assignment in
            if result[assignment.tagID] == nil { result[assignment.tagID] = assignment.nameSnapshot }
        }
    }

    private static func tagProjection(
        _ assignments: [SessionTagAssignmentRecord]
    ) -> [UUID: String] {
        assignments.reduce(into: [:]) { result, assignment in
            if result[assignment.tagID] == nil { result[assignment.tagID] = assignment.nameSnapshot }
        }
    }

    private static func segmentOrder(_ first: TimeSessionRecord, _ second: TimeSessionRecord) -> Bool {
        if first.startAt != second.startAt { return first.startAt < second.startAt }
        return uuidOrder(first.id, second.id)
    }

    private static func uuidOrder(_ first: UUID, _ second: UUID) -> Bool {
        first.uuidString < second.uuidString
    }

    private static func isFinite(_ date: Date) -> Bool {
        date.timeIntervalSinceReferenceDate.isFinite
    }
}
