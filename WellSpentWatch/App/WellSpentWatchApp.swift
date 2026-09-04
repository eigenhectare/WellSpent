import SwiftUI

@main
struct WellSpentWatchApp: App {
    @WKApplicationDelegateAdaptor(WellSpentWatchApplicationDelegate.self)
    private var applicationDelegate
    @StateObject private var runtime = WellSpentWatchRuntime.shared
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
        private let restartFaultFixture: WatchRestartFaultFixture?
    #endif

    init() {
        #if DEBUG
            do {
                restartFaultFixture = try WatchRestartFaultFixture.requested()
            } catch {
                preconditionFailure("Unable to initialize the isolated restart fixture.")
            }
        #endif
        WatchSystemActionDispatcher.execute = { request in
            try WellSpentWatchRuntime.shared.performSystemRequest(request)
        }
        WellSpentWatchShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
                if let restartFaultFixture {
                    WatchRestartFaultFixtureView(fixture: restartFaultFixture)
                } else {
                    applicationRoot
                }
            #else
                applicationRoot
            #endif
        }
    }

    private var applicationRoot: some View {
        rootView
            #if DEBUG
                .modifier(WatchAccessibilityFixtureEnvironment())
            #endif
            .environmentObject(runtime.goalAlerts)
            .task {
                runtime.activate()
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    runtime.activate()
                } else {
                    runtime.goalAlerts.leaveForeground()
                }
            }
    }

    @ViewBuilder
    private var rootView: some View {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-widget-family") {
                WatchWidgetPreviewSurface(runtime: runtime)
            } else {
                WatchRootView(runtime: runtime)
            }
        #else
            WatchRootView(runtime: runtime)
        #endif
    }
}
