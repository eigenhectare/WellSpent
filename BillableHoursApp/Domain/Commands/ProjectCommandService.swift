import Foundation

@MainActor
final class ProjectCommandService {
    private let repository: any ProjectRepository
    private let dependencies: BillableHoursDependencies

    init(repository: any ProjectRepository, dependencies: BillableHoursDependencies) {
        self.repository = repository
        self.dependencies = dependencies
    }

    func create(
        name: String,
        colorToken: String? = nil,
        emoji: String? = nil
    ) throws -> ProjectCommandResult {
        let normalizedName = try normalize(name: name)
        let normalizedEmoji = try normalize(emoji: emoji)
        let existingProjects = try repository.fetchProjects()
        let timestamp = dependencies.now
        let project = ProjectRecord(
            id: dependencies.makeUUID(),
            name: normalizedName,
            colorToken: normalize(colorToken: colorToken),
            emoji: normalizedEmoji,
            createdAt: timestamp,
            updatedAt: timestamp
        )

        repository.insert(project)
        try saveOrRollback()

        return ProjectCommandResult(
            project: ProjectSnapshot(record: project),
            warnings: duplicateWarnings(name: normalizedName, in: existingProjects)
        )
    }

    func rename(projectID: UUID, to name: String) throws -> ProjectCommandResult {
        let project = try requiredProject(id: projectID)
        return try update(
            projectID: projectID,
            name: name,
            colorToken: project.colorToken,
            emoji: project.emoji
        )
    }

    func update(
        projectID: UUID,
        name: String,
        colorToken: String?,
        emoji: String?
    ) throws -> ProjectCommandResult {
        let normalizedName = try normalize(name: name)
        let normalizedColorToken = normalize(colorToken: colorToken)
        let normalizedEmoji = try normalize(emoji: emoji)
        let project = try requiredProject(id: projectID)
        let existingProjects = try repository.fetchProjects()
        let warnings = duplicateWarnings(name: normalizedName, in: existingProjects, excluding: projectID)

        guard
            project.name != normalizedName
                || project.colorToken != normalizedColorToken
                || project.emoji != normalizedEmoji
        else {
            return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: warnings)
        }

        project.name = normalizedName
        project.colorToken = normalizedColorToken
        project.emoji = normalizedEmoji
        project.updatedAt = dependencies.now
        try saveOrRollback()

        return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: warnings)
    }

    func archive(projectID: UUID) throws -> ProjectCommandResult {
        let project = try requiredProject(id: projectID)

        guard project.status != .archived else {
            return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: [])
        }

        guard try !repository.hasActiveTimedSession(projectID: projectID) else {
            throw ProjectCommandError.activeTimerMustStopOrSwitch(projectID: projectID)
        }

        project.status = .archived
        project.updatedAt = dependencies.now
        try saveOrRollback()

        return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: [])
    }

    func restore(projectID: UUID) throws -> ProjectCommandResult {
        let project = try requiredProject(id: projectID)
        let existingProjects = try repository.fetchProjects()
        let warnings = duplicateWarnings(name: project.name, in: existingProjects, excluding: projectID)

        guard project.status != .active else {
            return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: warnings)
        }

        project.status = .active
        project.updatedAt = dependencies.now
        try saveOrRollback()

        return ProjectCommandResult(project: ProjectSnapshot(record: project), warnings: warnings)
    }

    private func requiredProject(id: UUID) throws -> ProjectRecord {
        guard let project = try repository.fetchProject(id: id) else {
            throw ProjectCommandError.projectNotFound(id)
        }
        return project
    }

    private func normalize(name: String) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else {
            throw ProjectCommandError.emptyName
        }
        return normalizedName
    }

    private func normalize(colorToken: String?) -> String? {
        guard let colorToken else {
            return nil
        }
        let normalizedToken = colorToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalizedToken.isEmpty ? nil : normalizedToken
    }

    private func normalize(emoji: String?) throws -> String? {
        guard let emoji else { return nil }
        let normalizedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEmoji.isEmpty else { return nil }
        guard normalizedEmoji.count == 1,
            normalizedEmoji.unicodeScalars.contains(where: { $0.properties.isEmoji })
        else {
            throw ProjectCommandError.invalidEmoji
        }
        return normalizedEmoji
    }

    private func duplicateWarnings(
        name: String,
        in projects: [ProjectRecord],
        excluding excludedID: UUID? = nil
    ) -> [ProjectCommandWarning] {
        let duplicateIDs =
            projects
            .filter { $0.id != excludedID && $0.name == name }
            .map(\.id)
            .sorted { $0.uuidString < $1.uuidString }

        guard !duplicateIDs.isEmpty else {
            return []
        }
        return [.exactDuplicate(existingProjectIDs: duplicateIDs)]
    }

    private func saveOrRollback() throws {
        do {
            try repository.save()
        } catch {
            repository.rollback()
            throw error
        }
    }
}
