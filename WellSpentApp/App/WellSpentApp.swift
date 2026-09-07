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
            let appModel = WellSpentAppModel(
                modelContainer: modelContainer,
                dependencies: dependencies,
                startupReconciliation: startupReconciliation
            )
            _appModel = StateObject(wrappedValue: appModel)

            // App intents can arrive before SwiftUI creates the root view. Install
            // the single-writer bridge during App initialization so a background
            // Live Activity action can reconcile its durable request immediately.
            WellSpentLiveActivityHandoffDispatcher.reconcile = { [weak appModel] in
                await appModel?.retryLiveActivityProjection()
            }
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
    }
}
