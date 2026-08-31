import Foundation

@MainActor
final class ProjectQueryService {
    private let repository: any ProjectRepository

    init(repository: any ProjectRepository) {
        self.repository = repository
    }

    func allProjects() throws -> [ProjectSnapshot] {
        try sorted(repository.fetchProjects()).map(ProjectSnapshot.init(record:))
    }

    func activeProjects() throws -> [ProjectSnapshot] {
        try sorted(repository.fetchProjects().filter { $0.status == .active }).map(ProjectSnapshot.init(record:))
    }

    func archivedProjects() throws -> [ProjectSnapshot] {
        try sorted(repository.fetchProjects().filter { $0.status == .archived }).map(ProjectSnapshot.init(record:))
    }

    func project(id: UUID) throws -> ProjectSnapshot? {
        try repository.fetchProject(id: id).map(ProjectSnapshot.init(record:))
    }

    private func sorted(_ projects: [ProjectRecord]) -> [ProjectRecord] {
        projects.sorted {
            if $0.createdAt != $1.createdAt {
                return $0.createdAt < $1.createdAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}
