import Foundation
import SwiftData

@MainActor
final class SwiftDataTimerRunRepository {
    private let context: ModelContext
    #if DEBUG
        private var beforeSave: (() throws -> Void)?
    #endif

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(context: ModelContext(modelContainer))
    }

    #if DEBUG
        func setBeforeSaveForTesting(_ hook: (() throws -> Void)?) {
            beforeSave = hook
        }
    #endif

    func fetchProject(id: UUID) throws -> ProjectRecord? {
        try context.fetch(FetchDescriptor<ProjectRecord>()).first { $0.id == id }
    }

    func fetchRun(id: UUID) throws -> TimerRunRecord? {
        try fetchRuns().first { $0.id == id }
    }

    func fetchRunIncludingSuperseded(id: UUID) throws -> TimerRunRecord? {
        try fetchAllRunsIncludingSuperseded().first { $0.id == id }
    }

    func fetchRun(resolving identity: UUID) throws -> TimerRunRecord? {
        if let run = try fetchRun(id: identity) { return run }
        guard
            let runID = try context.fetch(FetchDescriptor<TimeSessionRecord>())
                .first(where: { $0.id == identity })?.timerRunID
        else { return nil }
        return try fetchRun(id: runID)
    }

    func fetchRuns() throws -> [TimerRunRecord] {
        let superseded = try supersededRunIDs()
        return try fetchAllRunsIncludingSuperseded().filter { !superseded.contains($0.id) }
    }

    func fetchAllRunsIncludingSuperseded() throws -> [TimerRunRecord] {
        try context.fetch(FetchDescriptor<TimerRunRecord>()).sorted {
            if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func fetchSessions() throws -> [TimeSessionRecord] {
        let superseded = try supersededRunIDs()
        return try fetchAllSessionsIncludingSuperseded().filter { session in
            guard let runID = session.timerRunID else { return true }
            return !superseded.contains(runID)
        }
    }

    func fetchAllSessionsIncludingSuperseded() throws -> [TimeSessionRecord] {
        try context.fetch(FetchDescriptor<TimeSessionRecord>()).sorted {
            if $0.startAt != $1.startAt { return $0.startAt < $1.startAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func fetchSession(id: UUID) throws -> TimeSessionRecord? {
        try fetchSessions().first { $0.id == id }
    }

    func fetchSegments(runID: UUID) throws -> [TimeSessionRecord] {
        try fetchSessions().filter { $0.timerRunID == runID }
    }

    func fetchTags() throws -> [SessionTagRecord] {
        try context.fetch(FetchDescriptor<SessionTagRecord>()).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func fetchSessionTagAssignments() throws -> [SessionTagAssignmentRecord] {
        try context.fetch(FetchDescriptor<SessionTagAssignmentRecord>())
    }

    func fetchSessionTagAssignments(sessionID: UUID) throws -> [SessionTagAssignmentRecord] {
        try fetchSessionTagAssignments().filter { $0.sessionID == sessionID }
    }

    func fetchRunTagAssignments() throws -> [TimerRunTagAssignmentRecord] {
        try context.fetch(FetchDescriptor<TimerRunTagAssignmentRecord>())
    }

    func fetchRunTagAssignments(runID: UUID) throws -> [TimerRunTagAssignmentRecord] {
        try fetchRunTagAssignments().filter { $0.timerRunID == runID }
    }

    func fetchOrigins() throws -> [TimerOriginRecord] {
        try context.fetch(FetchDescriptor<TimerOriginRecord>())
    }

    func hasUnresolvedTimerConflict() throws -> Bool {
        try context.fetch(FetchDescriptor<PhoneTimerConflictRecord>()).contains {
            $0.stateRawValue == PhoneTimerConflictStatus.awaitingPhoneReview.rawValue
        }
    }

    func snapshot(_ run: TimerRunRecord) throws -> TimerRunSnapshot {
        guard let state = run.state else {
            throw TimerRunCommandError.reviewRequired(runIDs: [run.id], segmentIDs: [])
        }
        let assignmentsBySession = Dictionary(
            grouping: try fetchSessionTagAssignments(),
            by: \.sessionID
        )
        let segments = try fetchSegments(runID: run.id).map { segment in
            TimeSessionSnapshot(
                record: segment,
                tags: (assignmentsBySession[segment.id] ?? []).map(
                    SessionTagAssignmentSnapshot.init(record:)
                )
            )
        }
        let tags = try fetchRunTagAssignments(runID: run.id)
            .map {
                SessionTagAssignmentSnapshot(tagID: $0.tagID, name: $0.nameSnapshot)
            }
            .sorted {
                if $0.name != $1.name {
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
                return $0.tagID.uuidString < $1.tagID.uuidString
            }
        return TimerRunSnapshot(
            id: run.id,
            workspaceID: run.workspaceID,
            projectID: run.projectID,
            state: state,
            startAt: run.startAt,
            endAt: run.endAt,
            startTimeZoneID: run.startTimeZoneID,
            endTimeZoneID: run.endTimeZoneID,
            durationGoalSeconds: run.durationGoalSeconds,
            note: run.note,
            originDeviceID: run.originDeviceID,
            revision: run.revision,
            lastAppliedMutationID: run.lastAppliedMutationID,
            createdAt: run.createdAt,
            updatedAt: run.updatedAt,
            updatedTimeZoneID: run.updatedTimeZoneID,
            segments: segments,
            tags: tags
        )
    }

    func insert(_ run: TimerRunRecord) { context.insert(run) }
    func insert(_ session: TimeSessionRecord) { context.insert(session) }
    func insert(_ assignment: TimerRunTagAssignmentRecord) { context.insert(assignment) }
    func insert(_ assignment: SessionTagAssignmentRecord) { context.insert(assignment) }
    func insert(_ origin: TimerOriginRecord) { context.insert(origin) }
    func delete(_ run: TimerRunRecord) { context.delete(run) }
    func delete(_ session: TimeSessionRecord) { context.delete(session) }
    func delete(_ assignment: TimerRunTagAssignmentRecord) { context.delete(assignment) }
    func delete(_ assignment: SessionTagAssignmentRecord) { context.delete(assignment) }

    func save() throws {
        #if DEBUG
            try beforeSave?()
        #endif
        try context.save()
    }

    func rollback() {
        context.rollback()
    }

    private func supersededRunIDs() throws -> Set<UUID> {
        Set(
            try context.fetch(FetchDescriptor<PhoneEntityTombstoneRecord>())
                .filter { $0.entityTypeRawValue == "run" }
                .map(\.entityID)
        )
    }
}
