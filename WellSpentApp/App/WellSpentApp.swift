import SwiftData
import SwiftUI
import WellSpentShared

@main
struct WellSpentApp: App {
    private let dependencies: WellSpentDependencies
    private let modelContainer: ModelContainer
    @StateObject private var appModel: WellSpentAppModel
    #if DEBUG
        private let restartFaultFixture: PhoneRestartFaultFixture?
    #endif

    init() {
        do {
            let dependencies = WellSpentDependencies.live
            #if DEBUG
                let restartFaultFixture = try PhoneRestartFaultFixture.requested()
                self.restartFaultFixture = restartFaultFixture
                // SwiftUI may install this App's StateObject even when the
                // fixture view is selected. Its ordinary tag bootstrap must
                // not mutate the database held at a crash checkpoint.
                let modelContainer =
                    try restartFaultFixture == nil
                    ? WellSpentPersistence.makePersistentContainer()
                    : WellSpentPersistence.makeInMemoryContainer()
                if restartFaultFixture == nil {
                    try WellSpentUITestBootstrap.prepare(modelContainer: modelContainer)
                }
            #else
                let modelContainer = try WellSpentPersistence.makePersistentContainer()
            #endif
            self.dependencies = dependencies
            self.modelContainer = modelContainer
            let startupReconciliation = try WellSpentStartup.reconcileActiveRun(
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
            preconditionFailure("Unable to initialize the local data store.")
        }
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if let restartFaultFixture {
                    PhoneRestartFaultFixtureView(fixture: restartFaultFixture)
                } else {
                    applicationRoot
                }
            #else
                applicationRoot
            #endif
        }
        .modelContainer(modelContainer)
    }

    private var applicationRoot: some View {
        RootView(model: appModel)
            .environment(\.wellSpentDependencies, dependencies)
            .task {
                let model = appModel
                WellSpentLiveActivityHandoffDispatcher.reconcile = { [weak model] in
                    await model?.retryLiveActivityProjection()
                }
            }
    }
}
