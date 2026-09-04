import Foundation

/// A lossless timer-only projection reconstructed from one canonical snapshot
/// and one immutable origin chain. It is persisted with a conflict so review
/// never needs to infer a winner from wall-clock order.
public struct TimerConflictBranchProjection: Codable, Equatable, Sendable {
    public var activeRun: TimerRunSnapshot?
    public var activeRunSegments: [TimerSegmentSnapshot]
    public var recentlyEndedRun: TimerRunSnapshot?
    public var recentlyEndedRunSegments: [TimerSegmentSnapshot]

    public init(
        activeRun: TimerRunSnapshot? = nil,
        activeRunSegments: [TimerSegmentSnapshot] = [],
        recentlyEndedRun: TimerRunSnapshot? = nil,
        recentlyEndedRunSegments: [TimerSegmentSnapshot] = []
    ) {
        self.activeRun = activeRun
        self.activeRunSegments = activeRunSegments
        self.recentlyEndedRun = recentlyEndedRun
        self.recentlyEndedRunSegments = recentlyEndedRunSegments
    }

    public init(snapshot: TimerSnapshotEnvelope) {
        activeRun = snapshot.activeRun
        activeRunSegments = ContractStableOrdering.segments(snapshot.activeRunSegments)
        recentlyEndedRun = snapshot.recentlyEndedRun
        recentlyEndedRunSegments = ContractStableOrdering.segments(
            snapshot.recentlyEndedRunSegments
        )
    }
}

public enum TimerConflictBranchError: String, Error, Equatable, Sendable {
    case invalidAction = "invalid_action"
    case invalidBranch = "invalid_branch"
    case invalidCausalChain = "invalid_causal_chain"
}

public enum TimerConflictBranchReconstructor {
    public static func reconstruct(
        base: TimerSnapshotEnvelope,
        mutations: [TimerMutationEnvelope]
    ) throws -> TimerConflictBranchProjection {
        guard !mutations.isEmpty else { return TimerConflictBranchProjection(snapshot: base) }
        let ordered = mutations.sorted {
            if $0.originSequence != $1.originSequence {
                return $0.originSequence < $1.originSequence
            }
            return $0.mutationID.uuidString < $1.mutationID.uuidString
        }
        guard let origin = ordered.first?.originDeviceID,
            ordered.allSatisfy({ mutation in
                mutation.originDeviceID == origin
                    && mutation.baseSnapshotID == base.ledgerHead.snapshotID
                    && mutation.baseCanonicalGeneration
                        == base.ledgerHead.canonicalGeneration
                    && mutation.hasValidDigest()
            })
        else {
            throw TimerConflictBranchError.invalidCausalChain
        }
        for index in ordered.indices where index > ordered.startIndex {
            guard ordered[index].predecessorMutationID == ordered[index - 1].mutationID,
                ordered[index].originSequence > ordered[index - 1].originSequence
            else {
                throw TimerConflictBranchError.invalidCausalChain
            }
        }

        var projection = TimerConflictBranchProjection(snapshot: base)
        for mutation in ordered {
            try apply(
                mutation,
                projects: base.projects,
                projection: &projection
            )
        }
        try validate(projection)
        return projection
    }

    public static func validateResolution(
        _ payload: ConflictResolutionPayload
    ) throws {
        guard Set(payload.retainedRunIDs).count == payload.retainedRunIDs.count,
            Set(payload.replacementRuns.map(\.id)).count == payload.replacementRuns.count,
            Set(payload.replacementSegments.map(\.id)).count
                == payload.replacementSegments.count,
            Set(payload.retainedRunIDs).isDisjoint(
                with: Set(payload.replacementRuns.map(\.id))
            )
        else {
            throw TimerConflictBranchError.invalidBranch
        }

        let replacementIDs = Set(payload.replacementRuns.map(\.id))
        guard payload.replacementSegments.allSatisfy({ replacementIDs.contains($0.runID) }) else {
            throw TimerConflictBranchError.invalidBranch
        }
        let nonEnded = payload.replacementRuns.filter { $0.state != .ended }
        guard nonEnded.count <= 1 else { throw TimerConflictBranchError.invalidBranch }
        if let chosen = payload.chosenActiveRunID {
            guard nonEnded.map(\.id) == [chosen] || payload.retainedRunIDs.contains(chosen) else {
                throw TimerConflictBranchError.invalidBranch
            }
        } else if !nonEnded.isEmpty {
            throw TimerConflictBranchError.invalidBranch
        }

        for run in payload.replacementRuns {
            let segments = ContractStableOrdering.segments(
                payload.replacementSegments.filter { $0.runID == run.id }
            )
            try validate(run: run, segments: segments)
        }
    }

    private static func apply(
        _ mutation: TimerMutationEnvelope,
        projects: [ProjectSnapshot],
        projection: inout TimerConflictBranchProjection
    ) throws {
        let at = mutation.capturedAt
        let zone = mutation.capturedTimeZoneID
        guard at.timeIntervalSinceReferenceDate.isFinite, !zone.isEmpty else {
            throw TimerConflictBranchError.invalidAction
        }

        switch mutation.action {
        case .start(let action):
            guard projection.activeRun == nil,
                let project = projects.first(where: { $0.id == action.projectID }),
                validGoal(action.durationGoalSeconds)
            else { throw TimerConflictBranchError.invalidAction }
            projection.activeRun = TimerRunSnapshot(
                id: action.runID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                state: .running,
                startedAt: at,
                endedAt: nil,
                startTimeZoneID: zone,
                endTimeZoneID: nil,
                durationGoalSeconds: action.durationGoalSeconds,
                normalizedNote: nil,
                tagIDs: [],
                originDeviceID: mutation.originDeviceID,
                revision: 1,
                lastAppliedMutationID: mutation.mutationID,
                createdAt: at,
                updatedAt: at,
                updatedTimeZoneID: zone
            )
            projection.activeRunSegments = [
                TimerSegmentSnapshot(
                    id: action.segmentID,
                    runID: action.runID,
                    workspaceID: project.workspaceID,
                    projectID: project.id,
                    startedAt: at,
                    endedAt: nil,
                    startTimeZoneID: zone,
                    endTimeZoneID: nil,
                    revision: 1
                )
            ]

        case .pause(let action):
            guard let run = projection.activeRun,
                run.id == action.runID,
                run.state == .running,
                let index = projection.activeRunSegments.firstIndex(where: {
                    $0.id == action.openSegmentID && $0.endedAt == nil
                }),
                at > projection.activeRunSegments[index].startedAt
            else { throw TimerConflictBranchError.invalidAction }
            projection.activeRunSegments[index] = close(
                projection.activeRunSegments[index], at: at, zone: zone, revision: run.revision + 1
            )
            projection.activeRun = update(
                run,
                state: .paused,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone
            )

        case .resume(let action):
            guard let run = projection.activeRun,
                run.id == action.runID,
                run.state == .paused,
                projection.activeRunSegments.allSatisfy({ $0.endedAt != nil }),
                !projection.activeRunSegments.contains(where: { $0.id == action.newSegmentID }),
                let latestEnd = projection.activeRunSegments.compactMap(\.endedAt).max(),
                at >= latestEnd
            else { throw TimerConflictBranchError.invalidAction }
            let revision = run.revision + 1
            projection.activeRunSegments.append(
                TimerSegmentSnapshot(
                    id: action.newSegmentID,
                    runID: run.id,
                    workspaceID: run.workspaceID,
                    projectID: run.projectID,
                    startedAt: at,
                    endedAt: nil,
                    startTimeZoneID: zone,
                    endTimeZoneID: nil,
                    revision: revision
                )
            )
            projection.activeRun = update(
                run,
                state: .running,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone
            )

        case .switch(let action):
            guard let prior = projection.activeRun,
                prior.id == action.fromRunID,
                let project = projects.first(where: { $0.id == action.projectID }),
                validGoal(action.durationGoalSeconds)
            else { throw TimerConflictBranchError.invalidAction }
            var priorSegments = projection.activeRunSegments
            if prior.state == .running {
                guard let openID = action.openSegmentID,
                    let index = priorSegments.firstIndex(where: {
                        $0.id == openID && $0.endedAt == nil
                    }),
                    at > priorSegments[index].startedAt
                else { throw TimerConflictBranchError.invalidAction }
                priorSegments[index] = close(
                    priorSegments[index], at: at, zone: zone, revision: prior.revision + 1
                )
            } else {
                guard action.openSegmentID == nil,
                    let latestEnd = priorSegments.compactMap(\.endedAt).max(),
                    at >= latestEnd
                else { throw TimerConflictBranchError.invalidAction }
            }
            projection.recentlyEndedRun = end(
                prior,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone
            )
            projection.recentlyEndedRunSegments = priorSegments
            projection.activeRun = TimerRunSnapshot(
                id: action.toRunID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                state: .running,
                startedAt: at,
                endedAt: nil,
                startTimeZoneID: zone,
                endTimeZoneID: nil,
                durationGoalSeconds: action.durationGoalSeconds,
                normalizedNote: nil,
                tagIDs: [],
                originDeviceID: mutation.originDeviceID,
                revision: 1,
                lastAppliedMutationID: mutation.mutationID,
                createdAt: at,
                updatedAt: at,
                updatedTimeZoneID: zone
            )
            projection.activeRunSegments = [
                TimerSegmentSnapshot(
                    id: action.toSegmentID,
                    runID: action.toRunID,
                    workspaceID: project.workspaceID,
                    projectID: project.id,
                    startedAt: at,
                    endedAt: nil,
                    startTimeZoneID: zone,
                    endTimeZoneID: nil,
                    revision: 1
                )
            ]

        case .end(let action):
            guard let run = projection.activeRun, run.id == action.runID else {
                throw TimerConflictBranchError.invalidAction
            }
            var segments = projection.activeRunSegments
            if run.state == .running {
                guard let openID = action.openSegmentID,
                    let index = segments.firstIndex(where: {
                        $0.id == openID && $0.endedAt == nil
                    }),
                    at > segments[index].startedAt
                else { throw TimerConflictBranchError.invalidAction }
                segments[index] = close(
                    segments[index], at: at, zone: zone, revision: run.revision + 1
                )
            } else {
                guard action.openSegmentID == nil,
                    let latestEnd = segments.compactMap(\.endedAt).max(),
                    at >= latestEnd
                else { throw TimerConflictBranchError.invalidAction }
            }
            projection.recentlyEndedRun = end(
                run,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone
            )
            projection.recentlyEndedRunSegments = segments
            projection.activeRun = nil
            projection.activeRunSegments = []

        case .annotate(let action):
            guard let run = matchingRun(id: action.runID, projection: projection) else {
                throw TimerConflictBranchError.invalidAction
            }
            let updated = update(
                run,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone,
                note: action.normalizedNote,
                tagIDs: action.tagIDs
            )
            if projection.activeRun?.id == run.id {
                projection.activeRun = updated
            } else {
                projection.recentlyEndedRun = updated
            }

        case .setGoal(let action):
            guard validGoal(action.durationGoalSeconds),
                let run = projection.activeRun,
                run.id == action.runID
            else { throw TimerConflictBranchError.invalidAction }
            projection.activeRun = update(
                run,
                mutationID: mutation.mutationID,
                at: at,
                zone: zone,
                durationGoalSeconds: action.durationGoalSeconds
            )

        case .recoveryProposal(let action):
            if action.run.state == .ended {
                projection.activeRun = nil
                projection.activeRunSegments = []
                projection.recentlyEndedRun = action.run
                projection.recentlyEndedRunSegments = action.segments
            } else {
                projection.activeRun = action.run
                projection.activeRunSegments = action.segments
            }

        case .resolveConflict:
            throw TimerConflictBranchError.invalidAction
        }
    }

    private static func validate(_ projection: TimerConflictBranchProjection) throws {
        if let active = projection.activeRun {
            try validate(run: active, segments: projection.activeRunSegments)
        } else if !projection.activeRunSegments.isEmpty {
            throw TimerConflictBranchError.invalidBranch
        }
        if let ended = projection.recentlyEndedRun {
            try validate(run: ended, segments: projection.recentlyEndedRunSegments)
        } else if !projection.recentlyEndedRunSegments.isEmpty {
            throw TimerConflictBranchError.invalidBranch
        }
    }

    private static func validate(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot]
    ) throws {
        let ordered = ContractStableOrdering.segments(segments)
        guard !ordered.isEmpty,
            ordered.first?.startedAt == run.startedAt,
            ordered.allSatisfy({
                $0.runID == run.id
                    && $0.projectID == run.projectID
                    && $0.workspaceID == run.workspaceID
                    && $0.startedAt.timeIntervalSinceReferenceDate.isFinite
            })
        else { throw TimerConflictBranchError.invalidBranch }
        for index in ordered.indices {
            let segment = ordered[index]
            if let endedAt = segment.endedAt {
                guard endedAt > segment.startedAt, segment.endTimeZoneID != nil else {
                    throw TimerConflictBranchError.invalidBranch
                }
                if index > ordered.startIndex,
                    let priorEnd = ordered[index - 1].endedAt,
                    segment.startedAt < priorEnd
                {
                    throw TimerConflictBranchError.invalidBranch
                }
            }
        }
        let openCount = ordered.filter { $0.endedAt == nil }.count
        switch run.state {
        case .running:
            guard run.endedAt == nil, openCount == 1, ordered.last?.endedAt == nil else {
                throw TimerConflictBranchError.invalidBranch
            }
        case .paused:
            guard run.endedAt == nil, openCount == 0 else {
                throw TimerConflictBranchError.invalidBranch
            }
        case .ended:
            guard let endedAt = run.endedAt,
                run.endTimeZoneID != nil,
                openCount == 0,
                ordered.compactMap(\.endedAt).max().map({ $0 <= endedAt }) == true
            else { throw TimerConflictBranchError.invalidBranch }
        }
    }

    private static func matchingRun(
        id: UUID,
        projection: TimerConflictBranchProjection
    ) -> TimerRunSnapshot? {
        if projection.activeRun?.id == id { return projection.activeRun }
        if projection.recentlyEndedRun?.id == id { return projection.recentlyEndedRun }
        return nil
    }

    private static func close(
        _ segment: TimerSegmentSnapshot,
        at: Date,
        zone: String,
        revision: Int64
    ) -> TimerSegmentSnapshot {
        TimerSegmentSnapshot(
            id: segment.id,
            runID: segment.runID,
            workspaceID: segment.workspaceID,
            projectID: segment.projectID,
            startedAt: segment.startedAt,
            endedAt: at,
            startTimeZoneID: segment.startTimeZoneID,
            endTimeZoneID: zone,
            revision: revision
        )
    }

    private static func end(
        _ run: TimerRunSnapshot,
        mutationID: UUID,
        at: Date,
        zone: String
    ) -> TimerRunSnapshot {
        TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: .ended,
            startedAt: run.startedAt,
            endedAt: at,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: zone,
            durationGoalSeconds: run.durationGoalSeconds,
            normalizedNote: run.normalizedNote,
            tagIDs: run.tagIDs,
            originDeviceID: run.originDeviceID,
            revision: run.revision + 1,
            lastAppliedMutationID: mutationID,
            createdAt: run.createdAt,
            updatedAt: at,
            updatedTimeZoneID: zone
        )
    }

    private static func update(
        _ run: TimerRunSnapshot,
        state: TimerRunState? = nil,
        mutationID: UUID,
        at: Date,
        zone: String,
        note: String?? = nil,
        tagIDs: [UUID]? = nil,
        durationGoalSeconds: Int?? = nil
    ) -> TimerRunSnapshot {
        TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: state ?? run.state,
            startedAt: run.startedAt,
            endedAt: run.endedAt,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: durationGoalSeconds ?? run.durationGoalSeconds,
            normalizedNote: note ?? run.normalizedNote,
            tagIDs: tagIDs ?? run.tagIDs,
            originDeviceID: run.originDeviceID,
            revision: run.revision + 1,
            lastAppliedMutationID: mutationID,
            createdAt: run.createdAt,
            updatedAt: at,
            updatedTimeZoneID: zone
        )
    }

    private static func validGoal(_ seconds: Int?) -> Bool {
        seconds == nil || seconds! > 0
    }
}
