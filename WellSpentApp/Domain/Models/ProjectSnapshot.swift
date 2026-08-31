import Foundation

struct ProjectSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let workspaceID: UUID?
    let name: String
    let colorToken: String?
    let emoji: String?
    let status: ProjectStatus
    let createdAt: Date
    let updatedAt: Date

    init(record: ProjectRecord) {
        id = record.id
        workspaceID = record.workspaceID
        name = record.name
        colorToken = record.colorToken
        emoji = record.emoji
        status = record.status
        createdAt = record.createdAt
        updatedAt = record.updatedAt
    }

    var displayName: String {
        guard let emoji, !emoji.isEmpty else { return name }
        return "\(emoji) \(name)"
    }
}

enum ProjectCommandWarning: Equatable, Sendable {
    case exactDuplicate(existingProjectIDs: [UUID])
}

struct ProjectCommandResult: Equatable, Sendable {
    let project: ProjectSnapshot
    let warnings: [ProjectCommandWarning]
}

enum ProjectCommandError: Error, Equatable, Sendable {
    case emptyName
    case invalidEmoji
    case projectNotFound(UUID)
    case activeTimerMustStopOrSwitch(projectID: UUID)
}
