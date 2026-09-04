import SwiftData

@MainActor
enum WellSpentStartup {
    /// Compatibility inspection for pre-v3 callers and recovery tooling. The
    /// production app starts from `reconcileActiveRun` below.
    static func reconcileActiveSession(
        in modelContainer: ModelContainer,
        dependencies: WellSpentDependencies
    ) throws -> ActiveSessionReconciliationResult {
        let repository = SwiftDataTimerRepository(modelContainer: modelContainer)
        let commands = TimerCommandService(repository: repository, dependencies: dependencies)
        return try commands.reconcileActiveState()
    }

    static func reconcileActiveRun(
        in modelContainer: ModelContainer,
        dependencies: WellSpentDependencies
    ) throws -> ActiveTimerRunReconciliationResult {
        let repository = SwiftDataTimerRunRepository(modelContainer: modelContainer)
        let commands = TimerRunCommandService(repository: repository, dependencies: dependencies)
        return try commands.reconcileActiveState()
    }
}
