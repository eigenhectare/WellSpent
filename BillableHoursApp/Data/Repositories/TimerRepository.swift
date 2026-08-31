import Foundation
import SwiftData

@MainActor
protocol TimerRepository: AnyObject {
    func fetchProject(id: UUID) throws -> ProjectRecord?
    func fetchSession(id: UUID) throws -> TimeSessionRecord?
    func fetchActiveTimedSessions() throws -> [TimeSessionRecord]
    func insert(_ session: TimeSessionRecord)
    func save() throws
    func rollback()
}

@MainActor
final class SwiftDataTimerRepository: TimerRepository {
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
        try context.fetch(FetchDescriptor<TimeSessionRecord>()).first { $0.id == id }
    }

    func fetchActiveTimedSessions() throws -> [TimeSessionRecord] {
        try context.fetch(FetchDescriptor<TimeSessionRecord>())
            .filter { $0.source == .timer && $0.endAt == nil }
            .sorted {
                if $0.startAt != $1.startAt {
                    return $0.startAt < $1.startAt
                }
                return $0.id.uuidString < $1.id.uuidString
            }
    }

    func insert(_ session: TimeSessionRecord) {
        context.insert(session)
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }
}
