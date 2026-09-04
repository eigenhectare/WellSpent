import Combine
import Foundation
import WatchKit
import WellSpentWatchContracts
import WellSpentWatchStore
import WidgetKit

@MainActor
final class WellSpentWatchRuntime: ObservableObject {
    static let shared = WellSpentWatchRuntime()

    @Published private(set) var storeAvailability = WatchStoreAvailability.opening
    @Published private(set) var connectivityState = WatchConnectivityState.activating
    @Published private(set) var storeRevision = 0
    @Published private(set) var storeState: WatchStoreState?
    @Published private(set) var failedStartRequest: WatchStartRequest?
    @Published private(set) var controlOperation: WatchTimerControlOperation?
    @Published private(set) var failedControl: WatchTimerControlFailure?
    @Published private(set) var presentedEndedRunID: UUID?
    @Published private(set) var isSavingAnnotation = false
    @Published private(set) var failedAnnotation: WatchTimerAnnotationFailure?
    @Published private(set) var widgetProjectID: UUID?
    @Published private(set) var widgetRouteRevision = 0
    @Published var goalSaveFailed = false

    private(set) lazy var goalAlerts = makeGoalAlerts()

    private(set) var store: WellSpentWatchStore?
    private(set) var connectivity: WatchConnectivityCoordinator?
    private var cancellables: Set<AnyCancellable> = []
    private var isFixtureMode = false
    private var lastWidgetState: WatchWidgetState?

    #if DEBUG
        private var goalSaveFailureInjected = false
        private var controlFailuresInjected = 0
    #endif

    var forcePrivacyRedaction: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-ui-test-privacy-redacted")
        #else
            false
        #endif
    }

    var initialMetricPage: Int {
        #if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            guard let flagIndex = arguments.firstIndex(of: "-ui-test-metric-page"),
                arguments.indices.contains(flagIndex + 1),
                let page = Int(arguments[flagIndex + 1])
            else { return 0 }
            return min(max(page, 0), 2)
        #else
            0
        #endif
    }

    var startsOnControlSurface: Bool {
        #if DEBUG
            ProcessInfo.processInfo.arguments.contains("-ui-test-control-surface")
        #else
            false
        #endif
    }

    private init() {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-restart-id") {
                isFixtureMode = true
                return
            }
            if let fixture = WatchUITestFixture.requested {
                // Even a fixture that fails to open must never fall back to
                // live connectivity or the real notification preference store.
                isFixtureMode = true
                do {
                    let (store, connectivityState) = try fixture.makeRuntime()
                    self.store = store
                    self.connectivityState = connectivityState
                    storeAvailability = .ready
                    storeState = try store.state()
                    if fixture.presentsEndSummary {
                        presentedEndedRunID = storeState?.projection.recentlyEndedRun?.id
                    }
                    goalAlerts.update(state: storeState)
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "-ui-test-widget-url"),
                        arguments.indices.contains(index + 1), let url = URL(string: arguments[index + 1])
                    {
                        openWidgetURL(url)
                    }
                    return
                } catch {
                    storeAvailability = .unavailable
                    connectivityState = .unavailable
                    return
                }
            }
        #endif

        do {
            let store = try WellSpentWatchStore.openDefault()
            let connectivity = WatchConnectivityCoordinator(store: store)
            self.store = store
            self.connectivity = connectivity
            storeAvailability = .ready
            refreshStoreState()
            connectivity.$state
                .sink { [weak self] in
                    self?.connectivityState = $0
                    self?.refreshStoreState()
                }
                .store(in: &cancellables)
            connectivity.onStoreChanged = { [weak self] in
                self?.storeRevision += 1
                self?.refreshStoreState()
            }
            connectivity.beforeBackgroundTaskCompletion = { [weak self] in
                await self?.goalAlerts.waitForReconciliation()
            }
        } catch {
            storeAvailability = .unavailable
            connectivityState = .unavailable
            goalAlerts.update(state: nil)
        }
    }

    func activate() {
        goalAlerts.refreshAuthorization()
        guard !isFixtureMode else { return }
        connectivity?.activate()
    }

    private func makeGoalAlerts() -> WatchGoalAlertCoordinator {
        #if DEBUG
            if isFixtureMode {
                let arguments = ProcessInfo.processInfo.arguments
                let preferences: any WatchGoalPreferenceStore =
                    arguments.contains("-ui-test-alerts-settings-failure")
                    ? WatchGoalUnavailablePreferences() : WatchGoalMemoryPreferences()
                return WatchGoalAlertCoordinator(
                    center: WatchGoalFixtureNotifications(
                        denied: arguments.contains("-ui-test-alerts-denied"),
                        permissionFailsOnce: arguments.contains("-ui-test-alerts-permission-failure-once"),
                        schedulingFailsOnce: arguments.contains("-ui-test-alerts-scheduling-failure-once")),
                    preferenceStore: preferences, haptic: {})
            }
        #endif
        let preferenceStore: any WatchGoalPreferenceStore
        if let fileStore = try? WatchGoalFilePreferences() {
            preferenceStore = fileStore
        } else {
            preferenceStore = WatchGoalUnavailablePreferences()
        }
        return WatchGoalAlertCoordinator(
            center: WatchGoalSystemNotifications(), preferenceStore: preferenceStore)
    }

    func setDurationGoal(_ seconds: Int?, runID: UUID) {
        guard let store, controlOperation == nil, !isSavingAnnotation else { return }
        do {
            #if DEBUG
                if isFixtureMode, !goalSaveFailureInjected,
                    ProcessInfo.processInfo.arguments.contains("-ui-test-goal-save-failure-once")
                {
                    goalSaveFailureInjected = true
                    throw CocoaError(.fileWriteNoPermission)
                }
            #endif
            _ = try WatchTimerGoalBoundary().setGoal(seconds, runID: runID, store: store)
            goalSaveFailed = false
            goalAlerts.recordGoal(seconds)
            refreshStoreState()
            connectivity?.retryPendingTransfers(forceDurable: true)
            refreshStoreState()
        } catch {
            goalSaveFailed = true
            refreshStoreState()
        }
    }

    func retryPendingTransfers() {
        connectivity?.retryPendingTransfers(forceDurable: true)
    }

    func selectProject(_ project: ProjectSnapshot, durationGoalSeconds: Int?) {
        widgetProjectID = nil
        let request = WatchStartRequest(
            project: project,
            durationGoalSeconds: durationGoalSeconds
        )
        start(request)
    }

    func retryFailedStart() {
        guard let failedStartRequest else { return }
        start(failedStartRequest)
    }

    func cancelFailedStart() {
        failedStartRequest = nil
    }

    func pauseOrResumeActiveRun() {
        guard let run = storeState?.projection.activeRun else { return }
        beginControl(run.state == .paused ? .resume : .pause)
    }

    func endActiveRun() {
        beginControl(.end)
    }

    func switchActiveRun(to project: ProjectSnapshot, durationGoalSeconds: Int? = nil) {
        beginControl(
            .switchRun,
            switchRequest: WatchStartRequest(
                project: project,
                durationGoalSeconds: durationGoalSeconds
            )
        )
    }

    func retryFailedControl() {
        guard let failedControl else { return }
        self.failedControl = nil
        beginControl(
            failedControl.operation,
            switchRequest: failedControl.switchRequest
        )
    }

    func cancelFailedControl() {
        failedControl = nil
    }

    func dismissEndSummary() {
        guard !isSavingAnnotation else { return }
        failedAnnotation = nil
        presentedEndedRunID = nil
    }

    func saveEndedRunAnnotation(note: String, tagIDs: Set<UUID>) {
        guard let state = storeState, !state.isBlocked,
            let run = state.projection.recentlyEndedRun,
            presentedEndedRunID == run.id
        else { return }
        beginAnnotation(
            run: run,
            draft: WatchTimerAnnotationDraft(note: note, tagIDs: tagIDs),
            availableTags: state.projection.tags
        )
    }

    func retryFailedAnnotation() {
        guard let failure = failedAnnotation, let state = storeState,
            let run = state.projection.recentlyEndedRun,
            run.id == failure.runID,
            presentedEndedRunID == run.id
        else { return }
        failedAnnotation = nil
        beginAnnotation(
            run: run,
            draft: failure.draft,
            availableTags: state.projection.tags
        )
    }

    func discardFailedAnnotation() {
        failedAnnotation = nil
    }

    private func start(_ request: WatchStartRequest) {
        guard let store, storeState?.projection.activeRun == nil, controlOperation == nil else {
            return
        }

        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-start-failure") {
                failedStartRequest = request
                return
            }
        #endif

        let boundary = WatchTimerStartBoundary()
        let commit: WatchCommandCommit
        do {
            commit = try boundary.start(request) { action, capturedAt, timeZoneID in
                try store.performLocalCommand(
                    action,
                    capturedAt: capturedAt,
                    timeZoneID: timeZoneID
                )
            }
        } catch {
            failedStartRequest = request
            refreshStoreState()
            return
        }

        failedStartRequest = nil
        goalAlerts.recordGoal(request.durationGoalSeconds)
        try? store.recordProjectSelection(
            projectID: request.project.id,
            selectedAt: commit.mutation.capturedAt
        )
        donateSystemAction(.init(action: .start, projectID: request.project.id))
        refreshStoreState()
        WKInterfaceDevice.current().play(.start)
        connectivity?.retryPendingTransfers(forceDurable: true)
        refreshStoreState()
    }

    private func beginControl(
        _ operation: WatchTimerControlOperation,
        switchRequest: WatchStartRequest? = nil
    ) {
        guard controlOperation == nil, let state = storeState, !state.isBlocked,
            let run = state.projection.activeRun
        else { return }
        guard operation == .switchRun ? switchRequest != nil : switchRequest == nil else {
            return
        }

        failedControl = nil
        controlOperation = operation
        let segments = state.projection.activeRunSegments
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-test-control-delay") {
                    try? await Task.sleep(for: .seconds(2))
                }
            #endif
            commitControl(
                operation,
                run: run,
                segments: segments,
                switchRequest: switchRequest
            )
        }
    }

    private func commitControl(
        _ operation: WatchTimerControlOperation,
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        switchRequest: WatchStartRequest?
    ) {
        guard controlOperation == operation, let store else { return }

        let failure = WatchTimerControlFailure(
            operation: operation,
            switchRequest: switchRequest
        )
        #if DEBUG
            if shouldInjectControlFailure(operation) {
                controlFailuresInjected += 1
                controlOperation = nil
                failedControl = failure
                return
            }
        #endif

        let boundary = WatchTimerControlBoundary()
        let persist: WatchTimerControlBoundary.Persist = { action, capturedAt, timeZoneID in
            try store.performLocalCommand(
                action,
                capturedAt: capturedAt,
                timeZoneID: timeZoneID
            )
        }
        let commit: WatchCommandCommit
        do {
            switch operation {
            case .pause:
                commit = try boundary.pause(run: run, segments: segments, persist: persist)
            case .resume:
                commit = try boundary.resume(run: run, segments: segments, persist: persist)
            case .end:
                commit = try boundary.end(run: run, segments: segments, persist: persist)
            case .switchRun:
                guard let switchRequest else {
                    throw WatchTimerControlBoundaryError.invalidSwitchDestination
                }
                commit = try boundary.switchRun(
                    run: run,
                    segments: segments,
                    request: switchRequest,
                    persist: persist
                )
            }
        } catch {
            refreshStoreState()
            controlOperation = nil
            failedControl = failure
            return
        }

        if let switchRequest {
            goalAlerts.recordGoal(switchRequest.durationGoalSeconds)
            try? store.recordProjectSelection(
                projectID: switchRequest.project.id,
                selectedAt: commit.mutation.capturedAt
            )
        }
        if operation == .end {
            presentedEndedRunID = commit.projection.recentlyEndedRun?.id
        }
        let systemAction: WatchSystemAction =
            switch operation {
            case .pause: .pause
            case .resume: .resume
            case .end: .end
            case .switchRun: .switchProject
            }
        donateSystemAction(.init(action: systemAction, projectID: switchRequest?.project.id))
        refreshStoreState()
        controlOperation = nil
        playControlHaptic(operation)
        connectivity?.retryPendingTransfers(forceDurable: true)
        refreshStoreState()
    }

    private func beginAnnotation(
        run: TimerRunSnapshot,
        draft: WatchTimerAnnotationDraft,
        availableTags: [TagSnapshot]
    ) {
        guard !isSavingAnnotation, controlOperation == nil else { return }
        failedAnnotation = nil
        isSavingAnnotation = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await Task.yield()
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-ui-test-summary-delay") {
                    try? await Task.sleep(for: .seconds(2))
                }
            #endif
            commitAnnotation(run: run, draft: draft, availableTags: availableTags)
        }
    }

    private func commitAnnotation(
        run: TimerRunSnapshot,
        draft: WatchTimerAnnotationDraft,
        availableTags: [TagSnapshot]
    ) {
        guard isSavingAnnotation, let store else { return }
        let failure = WatchTimerAnnotationFailure(runID: run.id, draft: draft)
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-summary-failure") {
                isSavingAnnotation = false
                failedAnnotation = failure
                return
            }
        #endif

        let boundary = WatchTimerAnnotationBoundary()
        do {
            _ = try boundary.save(
                run: run,
                draft: draft,
                availableTags: availableTags
            ) { action, capturedAt, timeZoneID in
                try store.performLocalCommand(
                    action,
                    capturedAt: capturedAt,
                    timeZoneID: timeZoneID
                )
            }
        } catch {
            refreshStoreState()
            isSavingAnnotation = false
            failedAnnotation = failure
            return
        }

        refreshStoreState()
        isSavingAnnotation = false
        failedAnnotation = nil
        WKInterfaceDevice.current().play(.success)
        connectivity?.retryPendingTransfers(forceDurable: true)
        refreshStoreState()
    }

    private func playControlHaptic(_ operation: WatchTimerControlOperation) {
        switch operation {
        case .pause: WKInterfaceDevice.current().play(.click)
        case .resume, .switchRun: WKInterfaceDevice.current().play(.start)
        case .end: WKInterfaceDevice.current().play(.stop)
        }
    }

    #if DEBUG
        // Only disconnected fixtures may inject failures. A finite count lets
        // UI tests exercise cancellation and a real successful explicit retry;
        // omitting it retains the original persistent-failure fixture.
        private func shouldInjectControlFailure(_ operation: WatchTimerControlOperation) -> Bool {
            guard isFixtureMode, injectedFailureOperation == operation else { return false }
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-test-control-failure-count") else { return true }
            guard arguments.indices.contains(index + 1), let count = Int(arguments[index + 1]), count > 0 else {
                return false
            }
            return controlFailuresInjected < count
        }

        private var injectedFailureOperation: WatchTimerControlOperation? {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-ui-test-control-failure"),
                arguments.indices.contains(index + 1)
            else { return nil }
            return WatchTimerControlOperation(rawValue: arguments[index + 1])
        }
    #endif

    func handleBackgroundTasks(_ tasks: Set<WKRefreshBackgroundTask>) {
        connectivity?.handleBackgroundTasks(tasks)
        if connectivity == nil {
            for task in tasks { task.setTaskCompletedWithSnapshot(false) }
        }
    }

    private func refreshStoreState() {
        guard let store else {
            storeState = nil
            goalAlerts.update(state: nil)
            return
        }
        storeState = try? store.state()
        goalAlerts.update(state: storeState)
        let widgetState = storeState.map {
            WatchWidgetState.make(
                projection: $0.projection,
                pendingSync: $0.isPendingSync,
                isBlocked: $0.isBlocked,
                recentProjectIDs: $0.recentProjectIDs,
                commandContext: WatchCommandContext.token(for: $0)
            )
        }
        if widgetState != lastWidgetState {
            lastWidgetState = widgetState
            if !isFixtureMode {
                WidgetCenter.shared.reloadTimelines(ofKind: WatchWidgetState.kind)
                ControlCenter.shared.reloadControls(ofKind: "WellSpentWatchTimerControl")
            }
        }
        if storeState?.isBlocked == true {
            failedStartRequest = nil
            failedControl = nil
            controlOperation = nil
            failedAnnotation = nil
            isSavingAnnotation = false
            presentedEndedRunID = nil
            widgetProjectID = nil
        }
    }

    func openWidgetURL(_ url: URL) {
        guard let route = WatchWidgetRoute(url: url) else { return }
        refreshStoreState()
        guard let state = storeState else { return }
        widgetRouteRevision += 1
        presentedEndedRunID = nil
        switch route.resolved(in: state.projection, isBlocked: state.isBlocked) {
        case .project(let id): widgetProjectID = id
        case .projects, .run: widgetProjectID = nil
        }
    }

    func performSystemRequest(_ request: WatchSystemRequest) throws -> String {
        guard let store else { throw WatchSystemActionError.unavailable }
        guard controlOperation == nil, !isSavingAnnotation else { throw WatchSystemActionError.busy }
        let commit: WatchCommandCommit?
        do {
            commit = try WatchSystemCommandBoundary().perform(request, store: store)
        } catch let error as WatchSystemActionError {
            throw error
        } catch {
            throw WatchSystemActionError.saveFailed
        }
        if let commit {
            donateSystemAction(request)
            if let projectID = request.projectID, request.action == .start || request.action == .switchProject {
                try? store.recordProjectSelection(projectID: projectID, selectedAt: commit.mutation.capturedAt)
            }
            if request.action == .end {
                presentedEndedRunID = commit.projection.recentlyEndedRun?.id
            } else {
                presentedEndedRunID = nil
            }
        }
        refreshStoreState()
        activate()
        connectivity?.retryPendingTransfers(forceDurable: true)
        refreshStoreState()
        if request.action == .open { return String(localized: "WellSpent is open. Your saved time is unchanged.") }
        if commit == nil {
            return String(localized: "The timer is already in that state. Your saved time is unchanged.")
        }
        if storeState?.isPendingSync == true { return String(localized: "Timer saved on your Watch. Sync is pending.") }
        return String(localized: "Timer saved.")
    }

    private func donateSystemAction(_ request: WatchSystemRequest) {
        guard !isFixtureMode else { return }
        Task { await WatchIntentDonations.record(request) }
    }
}

@MainActor
final class WellSpentWatchApplicationDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        WellSpentWatchRuntime.shared.handleBackgroundTasks(backgroundTasks)
    }
}
