import SwiftData

@MainActor
enum WellSpentStartup {
    static func reconcileActiveSession(
        in modelContainer: ModelContainer,
        dependencies: WellSpentDependencies
    ) throws -> ActiveSessionReconciliationResult {
        let repository = SwiftDataTimerRepository(modelContainer: modelContainer)
        let commands = TimerCommandService(repository: repository, dependencies: dependencies)
        return try commands.reconcileActiveState()
    }
}
