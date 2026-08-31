import Foundation

@MainActor
final class SessionTagCommandService {
    struct BuiltInTag: Equatable, Sendable {
        let id: UUID
        let name: String
    }

    static let builtInTags: [BuiltInTag] = [
        BuiltInTag(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            name: "meeting"
        ),
        BuiltInTag(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            name: "internal discussion"
        ),
        BuiltInTag(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            name: "collaboration"
        ),
        BuiltInTag(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!,
            name: "solo work"
        ),
    ]

    private let repository: any SessionTagRepository
    private let dependencies: WellSpentDependencies

    init(
        repository: any SessionTagRepository,
        dependencies: WellSpentDependencies
    ) {
        self.repository = repository
        self.dependencies = dependencies
    }

    /// Seeds only when no tag record of any status exists. Archiving every
    /// built-in tag therefore remains stable across subsequent launches.
    func seedBuiltInsIfNeeded() throws {
        guard try repository.fetchTags().isEmpty else { return }
        let timestamp = dependencies.now
        for builtIn in Self.builtInTags {
            repository.insert(
                SessionTagRecord(
                    id: builtIn.id,
                    name: builtIn.name,
                    normalizedName: normalizedKey(builtIn.name),
                    isBuiltIn: true,
                    createdAt: timestamp,
                    updatedAt: timestamp
                )
            )
        }
        try saveOrRollback()
    }

    @discardableResult
    func create(name: String) throws -> SessionTagSnapshot {
        let normalizedName = try normalize(name: name)
        let key = normalizedKey(normalizedName)
        let existing = try repository.fetchTags().first { $0.normalizedName == key }

        if let existing {
            guard existing.status == .archived else {
                throw SessionTagCommandError.duplicateName(existing.name)
            }
            existing.status = .active
            existing.updatedAt = dependencies.now
            try saveOrRollback()
            return SessionTagSnapshot(record: existing)
        }

        let timestamp = dependencies.now
        let tag = SessionTagRecord(
            id: dependencies.makeUUID(),
            name: normalizedName,
            normalizedName: key,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        repository.insert(tag)
        try saveOrRollback()
        return SessionTagSnapshot(record: tag)
    }

    @discardableResult
    func archive(id: UUID) throws -> SessionTagSnapshot {
        guard let tag = try repository.fetchTag(id: id) else {
            throw SessionTagCommandError.tagNotFound(id)
        }
        guard tag.status != .archived else { return SessionTagSnapshot(record: tag) }
        tag.status = .archived
        tag.updatedAt = dependencies.now
        try saveOrRollback()
        return SessionTagSnapshot(record: tag)
    }

    private func normalize(name: String) throws -> String {
        let normalizedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedName.isEmpty else { throw SessionTagCommandError.emptyName }
        return normalizedName
    }

    private func normalizedKey(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
