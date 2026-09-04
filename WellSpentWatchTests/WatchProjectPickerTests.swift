import Foundation
import Testing
import WellSpentWatchContracts

@testable import WellSpentWatch

struct WatchProjectPickerTests {
    private let projectA = ProjectSnapshot(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000001")!,
        workspaceID: nil,
        name: "A",
        colorToken: "blue",
        symbolName: "folder"
    )
    private let projectB = ProjectSnapshot(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!,
        workspaceID: nil,
        name: "B",
        colorToken: "green",
        symbolName: nil
    )
    private let projectC = ProjectSnapshot(
        id: UUID(uuidString: "20000000-0000-0000-0000-000000000003")!,
        workspaceID: nil,
        name: "C",
        colorToken: "orange",
        symbolName: "🧠"
    )

    @Test
    func activeDestinationThenRecentsThenStableCatalogOrder() {
        let ordered = WatchProjectPickerModel.orderedProjects(
            [projectA, projectB, projectC],
            activeDestinationID: projectC.id,
            recentProjectIDs: [projectB.id, projectC.id]
        )

        #expect(ordered.map(\.id) == [projectC.id, projectB.id, projectA.id])
    }

    @Test
    func unknownAndDuplicateRecentIDsNeverDuplicateOrInventProjects() {
        let ordered = WatchProjectPickerModel.orderedProjects(
            [projectA, projectB],
            activeDestinationID: nil,
            recentProjectIDs: [UUID(), projectB.id, projectB.id]
        )

        #expect(ordered.map(\.id) == [projectB.id, projectA.id])
    }

    @Test
    func startRequestPreservesOpenAndGoalChoices() {
        let open = WatchStartRequest(project: projectA, durationGoalSeconds: nil)
        let goal = WatchStartRequest(project: projectA, durationGoalSeconds: 1_800)

        #expect(open.goalDescription == "Open timer")
        #expect(goal.goalDescription == "30 minute goal")
    }
}
