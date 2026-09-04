import Foundation
import WellSpentWatchContracts

enum WatchProjectionReducer {
    static func applying(
        _ action: TimerMutationAction,
        to source: WatchCachedProjection,
        mutationID: UUID,
        originDeviceID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws -> WatchCachedProjection {
        guard capturedAt.timeIntervalSinceReferenceDate.isFinite, !timeZoneID.isEmpty else {
            throw WatchStoreError.commandInvalid
        }

        var projection = source
        switch action {
        case .start(let payload):
            try start(
                payload,
                projection: &projection,
                mutationID: mutationID,
                originDeviceID: originDeviceID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .pause(let payload):
            try pause(
                payload,
                projection: &projection,
                mutationID: mutationID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .resume(let payload):
            try resume(
                payload,
                projection: &projection,
                mutationID: mutationID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .switch(let payload):
            try switchRun(
                payload,
                projection: &projection,
                mutationID: mutationID,
                originDeviceID: originDeviceID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .end(let payload):
            try end(
                payload,
                projection: &projection,
                mutationID: mutationID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .annotate(let payload):
            try annotate(
                payload,
                projection: &projection,
                mutationID: mutationID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .setGoal(let payload):
            try setGoal(
                payload,
                projection: &projection,
                mutationID: mutationID,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        case .recoveryProposal, .resolveConflict:
            throw WatchStoreError.commandInvalid
        }

        try validate(projection)
        return projection
    }

    static func validate(_ projection: WatchCachedProjection) throws {
        guard projection.projects.count <= WatchStoreLimits.maximumProjects,
            projection.tags.count <= WatchStoreLimits.maximumTags,
            projection.tombstones.count <= WatchStoreLimits.maximumTombstones
        else {
            throw WatchStoreError.localCapacityExceeded
        }

        try validateRecentlyEnded(projection)

        guard let run = projection.activeRun else {
            guard projection.activeRunSegments.isEmpty else {
                throw WatchStoreError.corruptStore
            }
            return
        }

        guard run.state != .ended, run.endedAt == nil, run.endTimeZoneID == nil,
            !projection.activeRunSegments.isEmpty,
            projection.activeRunSegments.allSatisfy({
                $0.runID == run.id
                    && $0.projectID == run.projectID
                    && $0.workspaceID == run.workspaceID
            })
        else {
            throw WatchStoreError.corruptStore
        }

        let segments = ContractStableOrdering.segments(projection.activeRunSegments)
        guard segments.first?.startedAt == run.startedAt else {
            throw WatchStoreError.corruptStore
        }
        for (index, segment) in segments.enumerated() {
            if let end = segment.endedAt {
                guard end > segment.startedAt, segment.endTimeZoneID != nil else {
                    throw WatchStoreError.corruptStore
                }
                if index + 1 < segments.count {
                    guard segments[index + 1].startedAt >= end else {
                        throw WatchStoreError.corruptStore
                    }
                }
            } else if index != segments.count - 1 {
                throw WatchStoreError.corruptStore
            }
        }

        let openSegments = segments.filter { $0.endedAt == nil }
        switch run.state {
        case .running:
            guard openSegments.count == 1 else {
                throw WatchStoreError.corruptStore
            }
        case .paused:
            guard openSegments.isEmpty else {
                throw WatchStoreError.corruptStore
            }
        case .ended:
            throw WatchStoreError.corruptStore
        }
    }

    private static func validateRecentlyEnded(_ projection: WatchCachedProjection) throws {
        guard let run = projection.recentlyEndedRun else {
            guard projection.recentlyEndedRunSegments.isEmpty else {
                throw WatchStoreError.corruptStore
            }
            return
        }
        guard run.state == .ended, run.endedAt != nil, run.endTimeZoneID != nil,
            !projection.recentlyEndedRunSegments.isEmpty,
            projection.recentlyEndedRunSegments.allSatisfy({ segment in
                guard let endedAt = segment.endedAt else { return false }
                return segment.runID == run.id
                    && segment.projectID == run.projectID
                    && segment.workspaceID == run.workspaceID
                    && segment.endTimeZoneID != nil
                    && endedAt > segment.startedAt
            })
        else {
            throw WatchStoreError.corruptStore
        }
        let segments = ContractStableOrdering.segments(projection.recentlyEndedRunSegments)
        guard segments.first?.startedAt == run.startedAt else {
            throw WatchStoreError.corruptStore
        }
        for index in 0..<(segments.count - 1) {
            guard let end = segments[index].endedAt, segments[index + 1].startedAt >= end else {
                throw WatchStoreError.corruptStore
            }
        }
    }

    private static func start(
        _ action: StartTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        originDeviceID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard projection.activeRun == nil, projection.activeRunSegments.isEmpty,
            let project = projection.projects.first(where: { $0.id == action.projectID }),
            validGoal(action.durationGoalSeconds),
            action.runID != projection.recentlyEndedRun?.id,
            !projection.recentlyEndedRunSegments.contains(where: { $0.id == action.segmentID })
        else {
            throw WatchStoreError.commandInvalid
        }

        projection.activeRun = TimerRunSnapshot(
            id: action.runID,
            workspaceID: project.workspaceID,
            projectID: project.id,
            state: .running,
            startedAt: capturedAt,
            endedAt: nil,
            startTimeZoneID: timeZoneID,
            endTimeZoneID: nil,
            durationGoalSeconds: action.durationGoalSeconds,
            normalizedNote: nil,
            tagIDs: [],
            originDeviceID: originDeviceID,
            revision: 1,
            lastAppliedMutationID: mutationID,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            updatedTimeZoneID: timeZoneID
        )
        projection.activeRunSegments = [
            TimerSegmentSnapshot(
                id: action.segmentID,
                runID: action.runID,
                workspaceID: project.workspaceID,
                projectID: project.id,
                startedAt: capturedAt,
                endedAt: nil,
                startTimeZoneID: timeZoneID,
                endTimeZoneID: nil,
                revision: 1
            )
        ]
    }

    private static func pause(
        _ action: PauseTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard let run = projection.activeRun, run.id == action.runID, run.state == .running,
            let segmentIndex = projection.activeRunSegments.firstIndex(where: {
                $0.id == action.openSegmentID && $0.endedAt == nil
            }),
            projection.activeRunSegments.filter({ $0.endedAt == nil }).count == 1,
            capturedAt > projection.activeRunSegments[segmentIndex].startedAt
        else {
            throw WatchStoreError.commandInvalid
        }

        projection.activeRunSegments[segmentIndex] = closing(
            projection.activeRunSegments[segmentIndex],
            at: capturedAt,
            timeZoneID: timeZoneID
        )
        projection.activeRun = updating(
            run,
            state: .paused,
            mutationID: mutationID,
            at: capturedAt,
            timeZoneID: timeZoneID
        )
    }

    private static func resume(
        _ action: ResumeTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard let run = projection.activeRun, run.id == action.runID, run.state == .paused,
            projection.activeRunSegments.allSatisfy({ $0.endedAt != nil }),
            !projection.activeRunSegments.contains(where: { $0.id == action.newSegmentID }),
            let latestEnd = projection.activeRunSegments.compactMap(\.endedAt).max(),
            capturedAt >= latestEnd
        else {
            throw WatchStoreError.commandInvalid
        }

        projection.activeRunSegments.append(
            TimerSegmentSnapshot(
                id: action.newSegmentID,
                runID: run.id,
                workspaceID: run.workspaceID,
                projectID: run.projectID,
                startedAt: capturedAt,
                endedAt: nil,
                startTimeZoneID: timeZoneID,
                endTimeZoneID: nil,
                revision: 1
            )
        )
        projection.activeRunSegments = ContractStableOrdering.segments(
            projection.activeRunSegments
        )
        projection.activeRun = updating(
            run,
            state: .running,
            mutationID: mutationID,
            at: capturedAt,
            timeZoneID: timeZoneID
        )
    }

    private static func switchRun(
        _ action: SwitchTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        originDeviceID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard let oldRun = projection.activeRun, oldRun.id == action.fromRunID,
            oldRun.projectID != action.projectID,
            let newProject = projection.projects.first(where: { $0.id == action.projectID }),
            validGoal(action.durationGoalSeconds), action.toRunID != oldRun.id,
            !projection.activeRunSegments.contains(where: { $0.id == action.toSegmentID })
        else {
            throw WatchStoreError.commandInvalid
        }

        var endedSegments = projection.activeRunSegments
        switch oldRun.state {
        case .running:
            guard let openSegmentID = action.openSegmentID,
                let index = endedSegments.firstIndex(where: {
                    $0.id == openSegmentID && $0.endedAt == nil
                }),
                endedSegments.filter({ $0.endedAt == nil }).count == 1,
                capturedAt > endedSegments[index].startedAt
            else {
                throw WatchStoreError.commandInvalid
            }
            endedSegments[index] = closing(
                endedSegments[index],
                at: capturedAt,
                timeZoneID: timeZoneID
            )
        case .paused:
            guard action.openSegmentID == nil,
                let latestEnd = endedSegments.compactMap(\.endedAt).max(),
                capturedAt >= latestEnd
            else {
                throw WatchStoreError.commandInvalid
            }
        case .ended:
            throw WatchStoreError.commandInvalid
        }

        projection.recentlyEndedRun = ending(
            oldRun,
            mutationID: mutationID,
            at: capturedAt,
            timeZoneID: timeZoneID
        )
        projection.recentlyEndedRunSegments = ContractStableOrdering.segments(endedSegments)
        projection.activeRun = TimerRunSnapshot(
            id: action.toRunID,
            workspaceID: newProject.workspaceID,
            projectID: newProject.id,
            state: .running,
            startedAt: capturedAt,
            endedAt: nil,
            startTimeZoneID: timeZoneID,
            endTimeZoneID: nil,
            durationGoalSeconds: action.durationGoalSeconds,
            normalizedNote: nil,
            tagIDs: [],
            originDeviceID: originDeviceID,
            revision: 1,
            lastAppliedMutationID: mutationID,
            createdAt: capturedAt,
            updatedAt: capturedAt,
            updatedTimeZoneID: timeZoneID
        )
        projection.activeRunSegments = [
            TimerSegmentSnapshot(
                id: action.toSegmentID,
                runID: action.toRunID,
                workspaceID: newProject.workspaceID,
                projectID: newProject.id,
                startedAt: capturedAt,
                endedAt: nil,
                startTimeZoneID: timeZoneID,
                endTimeZoneID: nil,
                revision: 1
            )
        ]
    }

    private static func end(
        _ action: EndTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard let run = projection.activeRun, run.id == action.runID else {
            throw WatchStoreError.commandInvalid
        }
        var segments = projection.activeRunSegments
        switch run.state {
        case .running:
            guard let openSegmentID = action.openSegmentID,
                let index = segments.firstIndex(where: {
                    $0.id == openSegmentID && $0.endedAt == nil
                }),
                segments.filter({ $0.endedAt == nil }).count == 1,
                capturedAt > segments[index].startedAt
            else {
                throw WatchStoreError.commandInvalid
            }
            segments[index] = closing(segments[index], at: capturedAt, timeZoneID: timeZoneID)
        case .paused:
            guard action.openSegmentID == nil,
                let latestEnd = segments.compactMap(\.endedAt).max(),
                capturedAt >= latestEnd
            else {
                throw WatchStoreError.commandInvalid
            }
        case .ended:
            throw WatchStoreError.commandInvalid
        }

        projection.recentlyEndedRun = ending(
            run,
            mutationID: mutationID,
            at: capturedAt,
            timeZoneID: timeZoneID
        )
        projection.recentlyEndedRunSegments = ContractStableOrdering.segments(segments)
        projection.activeRun = nil
        projection.activeRunSegments = []
    }

    private static func annotate(
        _ action: AnnotateTimerAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        let normalizedTags = Array(Set(action.tagIDs)).sorted {
            $0.uuidString < $1.uuidString
        }
        let targetRun =
            projection.activeRun?.id == action.runID
            ? projection.activeRun
            : (projection.recentlyEndedRun?.id == action.runID
                ? projection.recentlyEndedRun
                : nil)
        let allowedTagIDs = Set(projection.tags.map(\.id)).union(targetRun?.tagIDs ?? [])
        guard normalizedTags == action.tagIDs.sorted(by: { $0.uuidString < $1.uuidString }),
            Set(normalizedTags).isSubset(of: allowedTagIDs),
            validNote(action.normalizedNote)
        else {
            throw WatchStoreError.commandInvalid
        }

        if let run = projection.activeRun, run.id == action.runID {
            guard run.normalizedNote != action.normalizedNote || run.tagIDs != normalizedTags else {
                throw WatchStoreError.commandInvalid
            }
            projection.activeRun = updatingAnnotation(
                run,
                note: action.normalizedNote,
                tagIDs: normalizedTags,
                mutationID: mutationID,
                at: capturedAt,
                timeZoneID: timeZoneID
            )
        } else if let run = projection.recentlyEndedRun, run.id == action.runID {
            guard run.normalizedNote != action.normalizedNote || run.tagIDs != normalizedTags else {
                throw WatchStoreError.commandInvalid
            }
            projection.recentlyEndedRun = updatingAnnotation(
                run,
                note: action.normalizedNote,
                tagIDs: normalizedTags,
                mutationID: mutationID,
                at: capturedAt,
                timeZoneID: timeZoneID
            )
        } else {
            throw WatchStoreError.commandInvalid
        }
    }

    private static func setGoal(
        _ action: SetTimerGoalAction,
        projection: inout WatchCachedProjection,
        mutationID: UUID,
        capturedAt: Date,
        timeZoneID: String
    ) throws {
        guard let run = projection.activeRun, run.id == action.runID,
            validGoal(action.durationGoalSeconds), run.durationGoalSeconds != action.durationGoalSeconds
        else {
            throw WatchStoreError.commandInvalid
        }
        projection.activeRun = rebuilding(
            run,
            state: run.state,
            endedAt: run.endedAt,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: action.durationGoalSeconds,
            normalizedNote: run.normalizedNote,
            tagIDs: run.tagIDs,
            mutationID: mutationID,
            at: capturedAt,
            timeZoneID: timeZoneID
        )
    }

    private static func validGoal(_ goal: Int?) -> Bool {
        goal == nil || goal! > 0
    }

    private static func validNote(_ note: String?) -> Bool {
        guard let note else { return true }
        return !note.isEmpty
            && note == note.trimmingCharacters(in: .whitespacesAndNewlines)
            && note.count <= 1_000
    }

    private static func closing(
        _ segment: TimerSegmentSnapshot,
        at date: Date,
        timeZoneID: String
    ) -> TimerSegmentSnapshot {
        TimerSegmentSnapshot(
            id: segment.id,
            runID: segment.runID,
            workspaceID: segment.workspaceID,
            projectID: segment.projectID,
            startedAt: segment.startedAt,
            endedAt: date,
            startTimeZoneID: segment.startTimeZoneID,
            endTimeZoneID: timeZoneID,
            revision: segment.revision + 1
        )
    }

    private static func updating(
        _ run: TimerRunSnapshot,
        state: TimerRunState,
        mutationID: UUID,
        at date: Date,
        timeZoneID: String
    ) -> TimerRunSnapshot {
        rebuilding(
            run,
            state: state,
            endedAt: run.endedAt,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: run.durationGoalSeconds,
            normalizedNote: run.normalizedNote,
            tagIDs: run.tagIDs,
            mutationID: mutationID,
            at: date,
            timeZoneID: timeZoneID
        )
    }

    private static func ending(
        _ run: TimerRunSnapshot,
        mutationID: UUID,
        at date: Date,
        timeZoneID: String
    ) -> TimerRunSnapshot {
        rebuilding(
            run,
            state: .ended,
            endedAt: date,
            endTimeZoneID: timeZoneID,
            durationGoalSeconds: run.durationGoalSeconds,
            normalizedNote: run.normalizedNote,
            tagIDs: run.tagIDs,
            mutationID: mutationID,
            at: date,
            timeZoneID: timeZoneID
        )
    }

    private static func updatingAnnotation(
        _ run: TimerRunSnapshot,
        note: String?,
        tagIDs: [UUID],
        mutationID: UUID,
        at date: Date,
        timeZoneID: String
    ) -> TimerRunSnapshot {
        rebuilding(
            run,
            state: run.state,
            endedAt: run.endedAt,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: run.durationGoalSeconds,
            normalizedNote: note,
            tagIDs: tagIDs,
            mutationID: mutationID,
            at: date,
            timeZoneID: timeZoneID
        )
    }

    private static func rebuilding(
        _ run: TimerRunSnapshot,
        state: TimerRunState,
        endedAt: Date?,
        endTimeZoneID: String?,
        durationGoalSeconds: Int?,
        normalizedNote: String?,
        tagIDs: [UUID],
        mutationID: UUID,
        at date: Date,
        timeZoneID: String
    ) -> TimerRunSnapshot {
        TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: state,
            startedAt: run.startedAt,
            endedAt: endedAt,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: endTimeZoneID,
            durationGoalSeconds: durationGoalSeconds,
            normalizedNote: normalizedNote,
            tagIDs: tagIDs,
            originDeviceID: run.originDeviceID,
            revision: run.revision + 1,
            lastAppliedMutationID: mutationID,
            createdAt: run.createdAt,
            updatedAt: date,
            updatedTimeZoneID: timeZoneID
        )
    }
}
