import Foundation

struct SessionTagSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID?
    let name: String
    let status: SessionTagStatus
    let isBuiltIn: Bool
    let createdAt: Date
    let updatedAt: Date

    init(record: SessionTagRecord) {
        id = record.id
        workspaceID = record.workspaceID
        name = record.name
        status = record.status
        isBuiltIn = record.isBuiltIn
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }
}

struct SessionTagAssignmentSnapshot: Identifiable, Equatable, Sendable {
    let tagID: UUID
    let name: String

    var id: UUID { tagID }

    init(tagID: UUID, name: String) {
        self.tagID = tagID
        self.name = name
    }

    init(record: SessionTagAssignmentRecord) {
        tagID = record.tagID
        name = record.nameSnapshot
    }
}

enum SessionTagCommandError: Error, Equatable, Sendable {
    case emptyName
    case duplicateName(String)
    case tagNotFound(UUID)
}
