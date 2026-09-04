import SwiftUI
import WellSpentWatchContracts
import WellSpentWatchStore

struct WatchRootView: View {
    @ObservedObject var runtime: WellSpentWatchRuntime

    var body: some View {
        Group {
            if runtime.storeAvailability != .ready {
                WatchFoundationView(
                    storeAvailability: runtime.storeAvailability,
                    connectivityState: runtime.connectivityState
                )
            } else if let state = runtime.storeState {
                content(state)
            } else {
                WatchInterruptionView(
                    symbol: "exclamationmark.triangle.fill",
                    title: "Cache unavailable",
                    message: "Open WellSpent on your iPhone, then try again.",
                    identifier: "cache-unavailable"
                )
            }
        }
        .background(Color.black.ignoresSafeArea())
        .onOpenURL(perform: runtime.openWidgetURL)
        .alert("Couldn’t save time goal", isPresented: $runtime.goalSaveFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The timer and its previous goal are unchanged. Open Time Goal to try again.")
        }
        .alert(
            "Couldn’t start",
            isPresented: Binding(
                get: { runtime.failedStartRequest != nil },
                set: { if !$0 { runtime.cancelFailedStart() } }
            )
        ) {
            Button("Try Again") { runtime.retryFailedStart() }
            Button("Cancel", role: .cancel) { runtime.cancelFailedStart() }
        } message: {
            Text("No timer was created. Try again or choose another project.")
        }
        .alert(
            runtime.failedControl?.title ?? String(localized: "Couldn’t update timer"),
            isPresented: Binding(
                get: { runtime.failedControl != nil },
                set: { if !$0 { runtime.cancelFailedControl() } }
            )
        ) {
            Button("Try Again") { runtime.retryFailedControl() }
            Button("Cancel", role: .cancel) { runtime.cancelFailedControl() }
        } message: {
            Text(runtime.failedControl?.message ?? String(localized: "The run is unchanged."))
        }
    }

    @ViewBuilder
    private func content(_ state: WatchStoreState) -> some View {
        if state.projection.updateGuidance?.updateRequired == true {
            WatchInterruptionView(
                symbol: "arrow.down.app.fill",
                title: "Update WellSpent",
                message: "Update WellSpent on your iPhone and Apple Watch to continue.",
                identifier: "update-required"
            )
        } else if state.isBlocked || runtime.connectivityState == .blocked {
            WatchInterruptionView(
                symbol: "exclamationmark.bubble.fill",
                title: "Review on iPhone",
                message:
                    "Your time is preserved. Open WellSpent on iPhone and choose Review Preserved Time. Handoff can take you to this review when available.",
                identifier: "review-required"
            )
            .userActivity(WatchReviewLink.activityType, isActive: state.projection.conflict != nil) { activity in
                activity.title = String(localized: "Review WellSpent timer")
                activity.isEligibleForHandoff = true
                activity.isEligibleForSearch = false
                activity.isEligibleForPublicIndexing = false
                activity.userInfo = state.projection.conflict.map {
                    [WatchReviewLink.conflictIDKey: $0.conflictID.uuidString]
                }
            }
        } else if let run = state.projection.recentlyEndedRun,
            runtime.presentedEndedRunID == run.id
        {
            WatchEndedTimerSummaryView(
                run: run,
                segments: state.projection.recentlyEndedRunSegments,
                project: state.projection.projects.first(where: { $0.id == run.projectID }),
                tags: state.projection.tags,
                pendingSync: pendingCount(state) > 0,
                isReachable: runtime.connectivityState.isReachable,
                isSaving: runtime.isSavingAnnotation,
                failure: runtime.failedAnnotation,
                onSave: runtime.saveEndedRunAnnotation,
                onRetry: runtime.retryFailedAnnotation,
                onDiscardFailure: runtime.discardFailedAnnotation,
                onDone: runtime.dismissEndSummary
            )
        } else if let run = state.projection.activeRun {
            WatchStartedTimerView(
                run: run,
                segments: state.projection.activeRunSegments,
                project: state.projection.projects.first(where: { $0.id == run.projectID }),
                projects: state.projection.projects,
                recentProjectIDs: state.recentProjectIDs,
                totals: state.projection.totals,
                pendingSync: pendingCount(state) > 0,
                isReachable: runtime.connectivityState.isReachable,
                forcePrivacyRedaction: runtime.forcePrivacyRedaction,
                initialPage: runtime.initialMetricPage,
                startsOnControlSurface: runtime.startsOnControlSurface,
                controlOperation: runtime.controlOperation,
                onPauseOrResume: runtime.pauseOrResumeActiveRun,
                onEnd: runtime.endActiveRun,
                onSwitch: { runtime.switchActiveRun(to: $0) },
                onSetGoal: { runtime.setDurationGoal($0, runID: run.id) }
            )
        } else if state.projection.projects.isEmpty {
            if state.projection.ledgerHead == nil {
                WatchInterruptionView(
                    symbol: "iphone.and.arrow.forward",
                    title: "Finish setup",
                    message: "Open WellSpent on your iPhone and create your first project.",
                    identifier: "finish-setup"
                )
            } else {
                WatchInterruptionView(
                    symbol: "folder.badge.plus",
                    title: "No active projects",
                    message: "Create or restore a project in WellSpent on your iPhone.",
                    identifier: "no-projects"
                )
            }
        } else {
            WatchProjectPickerView(
                projects: state.projection.projects,
                recentProjectIDs: state.recentProjectIDs,
                activeDestinationID: state.projection.activeRun?.projectID,
                connectivityState: runtime.connectivityState,
                pendingCount: pendingCount(state),
                onSelect: runtime.selectProject,
                requestedProjectID: runtime.widgetProjectID
            )
            .id(runtime.widgetRouteRevision)
        }
    }

    private func pendingCount(_ state: WatchStoreState) -> Int {
        max(
            state.pendingMutationCount + state.pendingSnapshotReceiptCount,
            runtime.connectivityState.pendingCount
        )
    }
}

private struct WatchInterruptionView: View {
    let symbol: String
    let title: LocalizedStringResource
    let message: LocalizedStringResource
    let identifier: String

    var body: some View {
        ScrollView {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(String(localized: title)). \(String(localized: message))")
        .accessibilityIdentifier("watch.state.\(identifier)")
    }
}

extension WatchConnectivityState {
    var pendingCount: Int {
        guard case .available(_, let pendingCount) = self else { return 0 }
        return pendingCount
    }

    var isReachable: Bool {
        guard case .available(let reachable, _) = self else { return false }
        return reachable
    }
}
