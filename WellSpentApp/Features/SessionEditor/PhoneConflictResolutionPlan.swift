import Foundation
import WellSpentWatchContracts

enum PhoneConflictChoice: String, CaseIterable, Identifiable {
    case keepPhone, useWatch, keepBoth

    var id: String { rawValue }
    var title: String {
        switch self {
        case .keepPhone: "Keep iPhone version"
        case .useWatch: "Use Watch version"
        case .keepBoth: "Keep both as separate runs"
        }
    }
}

/// Immutable confirmation: the displayed boundaries and IDs are the ones saved.
struct PhoneConflictResolutionPlan: Identifiable {
    let id: UUID
    let conflict: PhoneTimerConflict
    let choice: PhoneConflictChoice
    let payload: ConflictResolutionPayload
    let capturedAt: Date
    let timeZoneID: String
    let explanation: String

    static func latestBranches(_ conflict: PhoneTimerConflict) -> [PhoneConflictBranch] {
        Dictionary(grouping: conflict.branches, by: { $0.mutation.originDeviceID })
            .values.compactMap { $0.max { $0.mutation.originSequence < $1.mutation.originSequence } }
            .sorted { $0.mutation.originDeviceID.uuidString < $1.mutation.originDeviceID.uuidString }
    }

    static func make(
        conflict: PhoneTimerConflict,
        runs: [TimerRunSnapshot],
        choice: PhoneConflictChoice,
        branchID: UUID?,
        at date: Date,
        watchEndAt: Date,
        timeZoneID: String,
        makeUUID: () -> UUID = UUID.init
    ) throws -> Self {
        let involved = Set(conflict.snapshot.involvedRunIDs)
        let canonical = runs.filter { involved.contains($0.id) }
        let unaffected = runs.filter { !involved.contains($0.id) }
        let retained = choice == .useWatch ? [] : canonical.map(\.id)
        var replacements: [WellSpentWatchContracts.TimerRunSnapshot] = []
        var segments: [TimerSegmentSnapshot] = []
        let mutationID = makeUUID()
        if choice != .keepPhone {
            guard let branch = latestBranches(conflict).first(where: { $0.mutation.mutationID == branchID }),
                let projection = branch.projection
            else { throw PhoneConflictResolutionError.invalidResolution }
            let candidates = [projection.recentlyEndedRun, projection.activeRun].compactMap { $0 }
                .filter { involved.contains($0.id) }
            guard !candidates.isEmpty else { throw PhoneConflictResolutionError.invalidResolution }
            for run in candidates {
                let source = (projection.recentlyEndedRunSegments + projection.activeRunSegments)
                    .filter { $0.runID == run.id }
                let mustEnd = choice == .keepBoth && run.state != .ended
                let end = mustEnd ? watchEndAt : run.endedAt
                if mustEnd {
                    guard watchEndAt <= date, watchEndAt > run.startedAt,
                        source.allSatisfy({ watchEndAt >= ($0.endedAt ?? $0.startedAt) }),
                        source.filter({ $0.endedAt == nil }).allSatisfy({ watchEndAt > $0.startedAt })
                    else { throw PhoneConflictResolutionError.invalidResolution }
                }
                let runID = makeUUID()
                replacements.append(
                    WellSpentWatchContracts.TimerRunSnapshot(
                        id: runID, workspaceID: run.workspaceID, projectID: run.projectID,
                        state: mustEnd ? .ended : run.state, startedAt: run.startedAt, endedAt: end,
                        startTimeZoneID: run.startTimeZoneID,
                        endTimeZoneID: mustEnd ? timeZoneID : run.endTimeZoneID,
                        durationGoalSeconds: run.durationGoalSeconds, normalizedNote: run.normalizedNote,
                        tagIDs: run.tagIDs, originDeviceID: run.originDeviceID,
                        revision: 1, lastAppliedMutationID: mutationID,
                        createdAt: run.createdAt, updatedAt: date, updatedTimeZoneID: timeZoneID
                    )
                )
                segments += source.map {
                    TimerSegmentSnapshot(
                        id: makeUUID(), runID: runID, workspaceID: $0.workspaceID,
                        projectID: $0.projectID, startedAt: $0.startedAt,
                        endedAt: mustEnd && $0.endedAt == nil ? watchEndAt : $0.endedAt,
                        startTimeZoneID: $0.startTimeZoneID,
                        endTimeZoneID: mustEnd && $0.endedAt == nil ? timeZoneID : $0.endTimeZoneID,
                        revision: 1
                    )
                }
            }
        }
        let activeIDs =
            (unaffected + canonical.filter { retained.contains($0.id) })
            .filter { $0.state != .ended }.map(\.id)
            + replacements.filter { $0.state != .ended }.map(\.id)
        guard activeIDs.count <= 1 else { throw PhoneConflictResolutionError.invalidResolution }
        let payload = ConflictResolutionPayload(
            chosenActiveRunID: activeIDs.first, retainedRunIDs: retained,
            replacementRuns: replacements, replacementSegments: segments
        )
        try TimerConflictBranchReconstructor.validateResolution(payload)
        let explanation: String =
            switch choice {
            case .keepPhone:
                "The saved iPhone runs keep their exact boundaries, notes, tags, and current state. Watch-only changes will not count in reports. The conflicting versions remain in the audit."
            case .useWatch:
                "The selected Watch version replaces the involved iPhone runs in reports, including its notes, tags, and running or paused state. The superseded version remains in the audit. Other runs are unchanged."
            case .keepBoth:
                "The iPhone runs stay unchanged. The selected Watch version is saved separately; any unfinished Watch run ends at the time shown below. Both versions count fully in reports, including overlapping time."
            }
        return Self(
            id: mutationID, conflict: conflict, choice: choice, payload: payload,
            capturedAt: date, timeZoneID: timeZoneID, explanation: explanation
        )
    }
}
