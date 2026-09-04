import Foundation
import SwiftData

@MainActor
protocol ProjectRepository: AnyObject {
    func fetchProjects() throws -> [ProjectRecord]
    func fetchProject(id: UUID) throws -> ProjectRecord?
    func hasActiveTimedSession(projectID: UUID) throws -> Bool
    func insert(_ project: ProjectRecord)
    func save() throws
    func rollback()
}

@MainActor
final class SwiftDataProjectRepository: ProjectRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(context: ModelContext(modelContainer))
    }

    func fetchProjects() throws -> [ProjectRecord] {
        try context.fetch(FetchDescriptor<ProjectRecord>())
    }

    func fetchProject(id: UUID) throws -> ProjectRecord? {
        try fetchProjects().first { $0.id == id }
    }

    func hasActiveTimedSession(projectID: UUID) throws -> Bool {
        let hasNonEndedRun = try context.fetch(FetchDescriptor<TimerRunRecord>()).contains {
            $0.projectID == projectID && $0.state != .ended
        }
        if hasNonEndedRun { return true }

        // Compatibility for a pre-v3 row that has not yet been wrapped in a
        // TimerRun (for example, an invalid fixture retained for review).
        return try context.fetch(FetchDescriptor<TimeSessionRecord>()).contains {
            $0.projectID == projectID && $0.source == .timer && $0.endAt == nil
        }
    }

    func insert(_ project: ProjectRecord) {
        context.insert(project)
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }
}
