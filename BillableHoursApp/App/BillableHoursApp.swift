import SwiftData
import SwiftUI

@main
struct BillableHoursApp: App {
    private let dependencies: BillableHoursDependencies
    private let modelContainer: ModelContainer
    @StateObject private var appModel: BillableHoursAppModel

    init() {
        do {
            let dependencies = BillableHoursDependencies.live
            let modelContainer = try BillableHoursPersistence.makePersistentContainer()
            #if DEBUG
                try BillableHoursUITestBootstrap.prepare(modelContainer: modelContainer)
            #endif
            self.dependencies = dependencies
            self.modelContainer = modelContainer
            let startupReconciliation = try BillableHoursStartup.reconcileActiveSession(
                in: modelContainer,
                dependencies: dependencies
            )
            _appModel = StateObject(
                wrappedValue: BillableHoursAppModel(
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
                .environment(\.billableHoursDependencies, dependencies)
        }
        .modelContainer(modelContainer)
    }
}
