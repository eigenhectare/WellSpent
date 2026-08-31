import SwiftUI
import UIKit
import WellSpentShared

struct RootView: View {
    private enum Tab: Hashable {
        case track
        case reports
        case settings
    }

    @ObservedObject var model: WellSpentAppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPreferenceKeys.completedOnboarding) private var completedOnboarding = false
    @State private var selectedTab: Tab = .track

    var body: some View {
        TabView(selection: $selectedTab) {
            TrackView(model: model)
                .tabItem {
                    Label("Track", systemImage: "timer")
                }
                .tag(Tab.track)

            ReportsView(model: model)
                .tabItem {
                    Label("Reports", systemImage: "chart.bar")
                }
                .tag(Tab.reports)

            SettingsView(model: model)
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(Tab.settings)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if case .reviewRequired(_, let conflictingSessions) =
                    model.startupReconciliation
                {
                    Label(
                        "Timer recovery needed: \(conflictingSessions.count) earlier "
                            + "session\(conflictingSessions.count == 1 ? "" : "s") require review in Session History.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.footnote.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .foregroundStyle(.primary)
                    .background(.yellow.opacity(0.2))
                    .accessibilityIdentifier("timer-reconciliation-review")
                }

                if let recoveryMessage = model.liveActivityRecoveryMessage {
                    if model.liveActivitiesEnabled {
                        RecoveryActionBanner(
                            message: recoveryMessage,
                            systemImage: "iphone.and.arrow.forward",
                            actionTitle: "Retry",
                            accent: .orange,
                            identifier: "live-activity-recovery",
                            actionIdentifier: "retry-live-activity"
                        ) {
                            Task { await model.retryLiveActivityProjection() }
                        }
                    } else {
                        RecoveryActionBanner(
                            message: recoveryMessage,
                            systemImage: "iphone.and.arrow.forward",
                            actionTitle: "Open iPhone Settings",
                            actionHint: "Opens the WellSpent settings page.",
                            accent: .orange,
                            identifier: "live-activity-recovery",
                            actionIdentifier: "open-live-activity-settings-recovery"
                        ) {
                            guard
                                let settingsURL = URL(
                                    string: UIApplication.openSettingsURLString
                                )
                            else { return }
                            openURL(settingsURL)
                        }
                    }
                }

                if model.isLongRunningSession {
                    RecoveryActionBanner(
                        message:
                            "This timer has continued for more than eight hours. Its saved start time is unchanged; recreate the Lock Screen activity if needed.",
                        systemImage: "clock.badge.exclamationmark",
                        actionTitle: "Recreate",
                        accent: .yellow,
                        identifier: "long-running-timer-warning",
                        actionIdentifier: "recreate-live-activity"
                    ) {
                        Task { await model.retryLiveActivityProjection() }
                    }
                }
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { !completedOnboarding },
                set: { if !$0 { completedOnboarding = true } }
            )
        ) {
            OnboardingView(model: model) {
                completedOnboarding = true
            }
        }
        .sheet(item: $model.completionRoute) { route in
            SessionCompletionView(model: model, route: route)
        }
        .alert(
            "WellSpent",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.dismissMessage() } }
            )
        ) {
            Button("OK") { model.dismissMessage() }
        } message: {
            Text(model.message ?? "")
        }
        .task {
            await model.applicationBecameActive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.applicationBecameActive() }
        }
        .onOpenURL { url in
            if WellSpentDeepLink.isTrackerURL(url) {
                selectedTab = .track
                return
            }
            Task { await model.handle(url: url) }
        }
    }
}

private struct RecoveryActionBanner: View {
    let message: String
    let systemImage: String
    let actionTitle: String
    var actionHint: String? = nil
    let accent: Color
    let identifier: String
    let actionIdentifier: String
    let action: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    messageLabel
                    actionButton
                }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    messageLabel
                    Spacer(minLength: 8)
                    actionButton
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accent)
                .frame(width: 6)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
    }

    private var messageLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .accessibilityHidden(true)
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(.primary)
        .accessibilityElement(children: .combine)
    }

    private var actionButton: some View {
        Button(actionTitle, action: action)
            .font(.footnote.weight(.semibold))
            .buttonStyle(.bordered)
            .tint(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .accessibilityIdentifier(actionIdentifier)
            .accessibilityHint(actionHint ?? "")
    }
}
