import SwiftData
import SwiftUI

@main
struct WellSpentApp: App {
    private let dependencies: WellSpentDependencies
    private let modelContainer: ModelContainer
    @StateObject private var appModel: WellSpentAppModel

    init() {
        do {
            let dependencies = WellSpentDependencies.live
            let modelContainer = try WellSpentPersistence.makePersistentContainer()
            #if DEBUG
                try WellSpentUITestBootstrap.prepare(modelContainer: modelContainer)
            #endif
            self.dependencies = dependencies
            self.modelContainer = modelContainer
            let startupReconciliation = try WellSpentStartup.reconcileActiveSession(
                in: modelContainer,
                dependencies: dependencies
            )
            _appModel = StateObject(
                wrappedValue: WellSpentAppModel(
                    modelContainer: modelContainer,
                    dependencies: dependencies,
                    startupReconciliation: startupReconciliation
                )
            )
        } catch {
            preconditionFailure("Unable to initialize the local data store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: appModel)
                .environment(\.wellSpentDependencies, dependencies)
        }
        .modelContainer(modelContainer)
    }
}
