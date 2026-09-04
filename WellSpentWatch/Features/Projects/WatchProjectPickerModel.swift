import Foundation
import WellSpentWatchContracts

struct WatchStartRequest: Equatable, Identifiable {
    let project: ProjectSnapshot
    let durationGoalSeconds: Int?

    var id: UUID { project.id }

    var goalDescription: String {
        guard let durationGoalSeconds else { return "Open timer" }
        let minutes = durationGoalSeconds / 60
        return minutes == 1 ? "1 minute goal" : "\(minutes) minute goal"
    }
}

enum WatchProjectPickerModel {
    static func orderedProjects(
        _ projects: [ProjectSnapshot],
        activeDestinationID: UUID?,
        recentProjectIDs: [UUID]
    ) -> [ProjectSnapshot] {
        let projectsByID = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
        var seen = Set<UUID>()
        var ordered: [ProjectSnapshot] = []

        func append(_ projectID: UUID?) {
            guard let projectID, seen.insert(projectID).inserted,
                let project = projectsByID[projectID]
            else { return }
            ordered.append(project)
        }

        append(activeDestinationID)
        for projectID in recentProjectIDs { append(projectID) }
        for project in projects where seen.insert(project.id).inserted {
            ordered.append(project)
        }
        return ordered
    }
}
