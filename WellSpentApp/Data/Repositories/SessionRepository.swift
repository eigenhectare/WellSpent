import Foundation
import SwiftData

@MainActor
protocol SessionRepository: AnyObject {
    func fetchProject(id: UUID) throws -> ProjectRecord?
    func fetchSession(id: UUID) throws -> TimeSessionRecord?
    func fetchSessions() throws -> [TimeSessionRecord]
    func insert(_ session: TimeSessionRecord)
    func delete(_ session: TimeSessionRecord)
    func save() throws
    func rollback()
}

@MainActor
final class SwiftDataSessionRepository: SessionRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(context: ModelContext(modelContainer))
    }

    func fetchProject(id: UUID) throws -> ProjectRecord? {
        try context.fetch(FetchDescriptor<ProjectRecord>()).first { $0.id == id }
    }

    func fetchSession(id: UUID) throws -> TimeSessionRecord? {
        try fetchSessions().first { $0.id == id }
    }

    func fetchSessions() throws -> [TimeSessionRecord] {
        try context.fetch(FetchDescriptor<TimeSessionRecord>()).sorted {
            if $0.startAt != $1.startAt {
                return $0.startAt < $1.startAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func insert(_ session: TimeSessionRecord) {
        context.insert(session)
    }

    func delete(_ session: TimeSessionRecord) {
        context.delete(session)
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }
}
