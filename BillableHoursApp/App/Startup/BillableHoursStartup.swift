import SwiftData

@MainActor
enum BillableHoursStartup {
    static func reconcileActiveSession(
        in modelContainer: ModelContainer,
        dependencies: BillableHoursDependencies
    ) throws -> ActiveSessionReconciliationResult {
        let repository = SwiftDataTimerRepository(modelContainer: modelContainer)
        let commands = TimerCommandService(repository: repository, dependencies: dependencies)
        return try commands.reconcileActiveState()
    }
}
