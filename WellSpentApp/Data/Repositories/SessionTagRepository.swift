import Foundation
import SwiftData

@MainActor
protocol SessionTagRepository: AnyObject {
    func fetchTags() throws -> [SessionTagRecord]
    func fetchTag(id: UUID) throws -> SessionTagRecord?
    func fetchAssignments() throws -> [SessionTagAssignmentRecord]
    func fetchAssignments(sessionID: UUID) throws -> [SessionTagAssignmentRecord]
    func insert(_ tag: SessionTagRecord)
    func insert(_ assignment: SessionTagAssignmentRecord)
    func delete(_ assignment: SessionTagAssignmentRecord)
    func save() throws
    func rollback()
}

@MainActor
final class SwiftDataSessionTagRepository: SessionTagRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    convenience init(modelContainer: ModelContainer) {
        self.init(context: ModelContext(modelContainer))
    }

    func fetchTags() throws -> [SessionTagRecord] {
        try context.fetch(FetchDescriptor<SessionTagRecord>()).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    func fetchTag(id: UUID) throws -> SessionTagRecord? {
        try fetchTags().first { $0.id == id }
    }

    func fetchAssignments() throws -> [SessionTagAssignmentRecord] {
        try context.fetch(FetchDescriptor<SessionTagAssignmentRecord>()).sorted {
            if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
            return $0.tagID.uuidString < $1.tagID.uuidString
        }
    }

    func fetchAssignments(sessionID: UUID) throws -> [SessionTagAssignmentRecord] {
        try fetchAssignments().filter { $0.sessionID == sessionID }
    }

    func insert(_ tag: SessionTagRecord) {
        context.insert(tag)
    }

    func insert(_ assignment: SessionTagAssignmentRecord) {
        context.insert(assignment)
    }

    func delete(_ assignment: SessionTagAssignmentRecord) {
        context.delete(assignment)
    }

    func save() throws {
        try context.save()
    }

    func rollback() {
        context.rollback()
    }
}
