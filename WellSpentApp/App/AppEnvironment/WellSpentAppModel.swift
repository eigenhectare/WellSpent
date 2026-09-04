import Foundation
import SwiftData
import SwiftUI
import WellSpentShared
import WellSpentWatchContracts

enum CompletionPresentationKind: Equatable, Sendable {
    case stopped
    case switched
    case deepLink
}

struct CompletionRoute: Identifiable, Equatable, Sendable {
    let sessionID: UUID
    let kind: CompletionPresentationKind

    var id: UUID { sessionID }
}

struct ConflictReviewRoute: Identifiable {
    let id: UUID
}

@MainActor
final class WellSpentAppModel: ObservableObject {
    @Published private(set) var projects: [ProjectSnapshot] = []
    @Published private(set) var sessions: [TimeSessionSnapshot] = []
    @Published private(set) var runs: [TimerRunSnapshot] = []
    @Published private(set) var sessionTags: [SessionTagSnapshot] = []
    @Published private(set) var activeRun: TimerRunSnapshot?
    @Published private(set) var activeSession: TimeSessionSnapshot?
    @Published private(set) var startupReconciliation: ActiveTimerRunReconciliationResult
    @Published private(set) var isPerformingTimerCommand = false
    @Published private(set) var liveActivitiesEnabled = false
    @Published private(set) var liveActivityRecoveryMessage: String?
    @Published private(set) var isLongRunningSession = false
    @Published private(set) var requiresOnboardingAfterReset = false
    @Published var completionRoute: CompletionRoute?
    @Published var message: String?
    @Published private(set) var watchSyncOverview = PhoneWatchSyncOverview()
    @Published private(set) var watchConnectionState: IPhoneWatchConnectivityState = .activating
    @Published private(set) var watchSyncNeedsRetry = false
    @Published private(set) var pendingWatchConflicts: [PhoneTimerConflict] = []
    @Published var conflictReviewRoute: ConflictReviewRoute?

    private let dependencies: WellSpentDependencies
    private let projectCommands: ProjectCommandService
    private let projectQueries: ProjectQueryService
    private let timerCommands: TimerRunCommandService
    private let phoneWatchSyncStore: PhoneWatchSyncStore
    private let sessionCommands: SessionCommandService
    private let sessionRepository: any SessionRepository
    private let sessionTagCommands: SessionTagCommandService
    private let sessionTagRepository: any SessionTagRepository
    private let localDataResetService: WellSpentLocalDataResetService
    private let liveActivityLifecycle: any LiveActivityLifecycle
    private let stopHandoffSuiteName: String
    private let foregroundHandoffPollDelays: [Duration]
    private let showsProjectNameOnLockScreen: () -> Bool
    private let makeWatchConnectivity: (PhoneWatchSyncStore) -> IPhoneWatchConnectivityCoordinator
    private let reportingEngine = ReportingEngine()
    private var watchConnectivity: IPhoneWatchConnectivityCoordinator?
    private var liveActivityCanonicalStateAvailable = false
    private var stopHandoffRecoveryMessage: String?
    private var liveActivityOperationID: UUID?

    init(
        modelContainer: ModelContainer,
        dependencies: WellSpentDependencies,
        startupReconciliation: ActiveTimerRunReconciliationResult,
        liveActivityLifecycle: (any LiveActivityLifecycle)? = nil,
        stopHandoffSuiteName: String = WellSpentStopHandoff.appGroupIdentifier,
        foregroundHandoffPollDelays: [Duration] = [.milliseconds(250), .milliseconds(500)],
        makeWatchConnectivity: @escaping (PhoneWatchSyncStore) -> IPhoneWatchConnectivityCoordinator = {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("UITEST_") }) {
                    return IPhoneWatchConnectivityCoordinator(
                        syncStore: $0, session: UITestDisconnectedWatchSession())
                }
            #endif
            return IPhoneWatchConnectivityCoordinator(syncStore: $0)
        },
        showsProjectNameOnLockScreen: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: AppPreferenceKeys.showProjectNamesOnLockScreen)
        }
    ) {
        let context = ModelContext(modelContainer)
        let projectRepository = SwiftDataProjectRepository(context: context)
        let timerRepository = SwiftDataTimerRunRepository(context: context)
        let sessionRepository = SwiftDataSessionRepository(context: context)
        let sessionTagRepository = SwiftDataSessionTagRepository(context: context)

        self.dependencies = dependencies
        self.startupReconciliation = startupReconciliation
        self.sessionRepository = sessionRepository
        self.sessionTagRepository = sessionTagRepository
        localDataResetService = WellSpentLocalDataResetService(context: context)
        self.liveActivityLifecycle =
            liveActivityLifecycle ?? ActivityKitLiveActivityLifecycle()
        self.stopHandoffSuiteName = stopHandoffSuiteName
        self.foregroundHandoffPollDelays = foregroundHandoffPollDelays
        self.showsProjectNameOnLockScreen = showsProjectNameOnLockScreen
        self.makeWatchConnectivity = makeWatchConnectivity
        projectCommands = ProjectCommandService(
            repository: projectRepository,
            dependencies: dependencies
        )
        projectQueries = ProjectQueryService(repository: projectRepository)
        let timerCommands = TimerRunCommandService(
            repository: timerRepository,
            dependencies: dependencies
        )
        self.timerCommands = timerCommands
        phoneWatchSyncStore = PhoneWatchSyncStore(
            context: context,
            timerRepository: timerRepository,
            timerCommands: timerCommands,
            dependencies: dependencies
        )
        sessionCommands = SessionCommandService(
            repository: sessionRepository,
            tagRepository: sessionTagRepository,
            dependencies: dependencies
        )
        sessionTagCommands = SessionTagCommandService(
            repository: sessionTagRepository,
            dependencies: dependencies
        )

        do {
            try sessionTagCommands.seedBuiltInsIfNeeded()
        } catch {
            message = "Session tags could not be prepared. Your timer data is unaffected."
        }

        refresh()
    }

    var activeProjects: [ProjectSnapshot] {
        projects.filter { $0.status == .active }
    }

    var archivedProjects: [ProjectSnapshot] {
        projects.filter { $0.status == .archived }
    }

    var availableSessionTags: [SessionTagSnapshot] {
        sessionTags.filter { $0.status == .active }
    }

    func selectableSessionTags(sessionID: UUID?) -> [SessionTagSnapshot] {
        let assignedIDs = Set(
            sessionID.flatMap {
                run(id: $0)?.tags.map(\.tagID) ?? session(id: $0)?.tags.map(\.tagID)
            } ?? []
        )
        return sessionTags.filter { $0.status == .active || assignedIDs.contains($0.id) }
    }

    var overlappingSessionIDs: Set<UUID> {
        let detector = SessionOverlapDetector()
        let intervals = sessions.map {
            SessionInterval(sessionID: $0.id, startAt: $0.startAt, endAt: $0.endAt)
        }
        return Set(
            detector.detect(in: intervals, activeEndAt: dependencies.now).overlappingSessionIDs
        )
    }

    func project(id: UUID) -> ProjectSnapshot? {
        projects.first { $0.id == id }
    }

    func session(id: UUID) -> TimeSessionSnapshot? {
        sessions.first { $0.id == id }
    }

    func run(id identity: UUID) -> TimerRunSnapshot? {
        if let exact = runs.first(where: { $0.id == identity }) { return exact }
        guard let runID = session(id: identity)?.timerRunID else { return nil }
        return runs.first { $0.id == runID }
    }

    func refresh() {
        do {
            projects = try projectQueries.allProjects()
            sessionTags = try sessionTagRepository.fetchTags().map(SessionTagSnapshot.init(record:))
            let assignmentsBySession = Dictionary(
                grouping: try sessionTagRepository.fetchAssignments(),
                by: \.sessionID
            )
            sessions = try sessionRepository.fetchSessions().map { record in
                TimeSessionSnapshot(
                    record: record,
                    tags: (assignmentsBySession[record.id] ?? [])
                        .map(SessionTagAssignmentSnapshot.init(record:))
                )
            }
            runs = try timerCommands.allRuns()
            let reconciliation = try timerCommands.reconcileActiveState()
            startupReconciliation = reconciliation
            switch reconciliation {
            case .noActiveRun:
                activeRun = nil
                activeSession = nil
            case .running(let run, let openSegment):
                activeRun = run
                activeSession = openSegment
            case .paused(let run):
                activeRun = run
                activeSession = nil
            case .reviewRequired:
                activeRun = nil
                activeSession = nil
            }
            updateLiveActivityStatus()
            liveActivityCanonicalStateAvailable = true
            watchConnectivity?.publishLatestSnapshot()
            refreshWatchStatus()
        } catch {
            liveActivityCanonicalStateAvailable = false
            updateLiveActivityDesiredState()
            present(error)
        }
    }

    func activateWatchConnectivity() {
        if let watchConnectivity {
            watchConnectivity.retryPendingTransfers()
            return
        }
        let coordinator = makeWatchConnectivity(phoneWatchSyncStore)
        coordinator.onCanonicalMutationApplied = { [weak self] in
            guard let self else { return }
            self.refresh()
            Task { @MainActor [weak self] in
                await self?.reconcileLiveActivityProjection()
            }
        }
        coordinator.onStatusChanged = { [weak self] in
            self?.refreshWatchStatus()
            Task { @MainActor [weak self] in
                await self?.reconcileLiveActivityProjection()
            }
        }
        watchConnectivity = coordinator
        coordinator.activate()
        coordinator.retryPendingTransfers()
    }

    var timerCommandsBlocked: Bool {
        if !pendingWatchConflicts.isEmpty { return true }
        if case .reviewRequired = startupReconciliation { return true }
        return false
    }

    func isWatchOrigin(_ run: TimerRunSnapshot) -> Bool {
        watchSyncOverview.watchOriginIDs.contains(run.originDeviceID)
    }

    var watchSyncStatusText: String {
        if !pendingWatchConflicts.isEmpty { return "Review required" }
        if watchSyncNeedsRetry { return "Sync needs retry" }
        if watchSyncOverview.pendingAcknowledgements > 0 { return "Saved on iPhone · Watch confirmation pending" }
        if watchSyncOverview.awaitingSnapshotReceipt { return "Saved on iPhone · Waiting for Watch" }
        if watchSyncOverview.hasWatchHistory { return "Last saved changes confirmed by Watch" }
        switch watchConnectionState {
        case .available: return "Watch connected · Waiting for first confirmation"
        case .activating: return "Checking for Apple Watch"
        case .unavailable: return "No companion Watch available"
        }
    }

    func refreshWatchStatus() {
        do {
            watchSyncOverview = try phoneWatchSyncStore.syncOverview()
            pendingWatchConflicts = try phoneWatchSyncStore.pendingConflicts()
            watchConnectionState = watchConnectivity?.state ?? .unavailable
            watchSyncNeedsRetry = watchConnectivity?.lastDiagnosticCode != nil
        } catch {
            watchSyncNeedsRetry = true
            liveActivityCanonicalStateAvailable = false
        }
        updateLiveActivityDesiredState()
    }

    func retryWatchSync() {
        watchConnectivity?.retryPendingTransfers()
        refreshWatchStatus()
    }

    func openConflictReview(id: UUID) {
        refreshWatchStatus()
        guard pendingWatchConflicts.contains(where: { $0.snapshot.conflictID == id }) else {
            message = "This review is no longer pending. Your saved time is unchanged."
            return
        }
        completionRoute = nil
        conflictReviewRoute = ConflictReviewRoute(id: id)
    }

    func resolveWatchConflict(_ plan: PhoneConflictResolutionPlan) async -> String? {
        guard !isPerformingTimerCommand else { return "Another change is still saving. Try again." }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }
        do {
            guard try phoneWatchSyncStore.pendingConflicts().contains(plan.conflict) else {
                return
                    "The conflict changed while you reviewed it. Close this confirmation and review the latest versions."
            }
            try throwForcedFailureIfRequested()
            _ = try phoneWatchSyncStore.resolveConflict(
                conflictID: plan.conflict.snapshot.conflictID, resolution: plan.payload,
                capturedAt: plan.capturedAt, timeZoneID: plan.timeZoneID, mutationID: plan.id
            )
            refresh()
            await reconcileLiveActivityProjection()
            return nil
        } catch {
            refreshWatchStatus()
            return
                "The resolution could not be saved. Both versions are still preserved and timers remain blocked. Try again."
        }
    }

    @discardableResult
    func createProject(
        name: String,
        colorToken: String?,
        emoji: String? = nil
    ) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            let result = try projectCommands.create(
                name: name,
                colorToken: colorToken,
                emoji: emoji
            )
            refresh()
            presentDuplicateWarningIfNeeded(result.warnings)
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func renameProject(id: UUID, name: String) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            let result = try projectCommands.rename(projectID: id, to: name)
            refresh()
            presentDuplicateWarningIfNeeded(result.warnings)
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func updateProject(
        id: UUID,
        name: String,
        colorToken: String?,
        emoji: String?
    ) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            let result = try projectCommands.update(
                projectID: id,
                name: name,
                colorToken: colorToken,
                emoji: emoji
            )
            refresh()
            presentDuplicateWarningIfNeeded(result.warnings)
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func addSessionTag(name: String) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try sessionTagCommands.create(name: name)
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func removeSessionTag(id: UUID) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try sessionTagCommands.archive(id: id)
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func archiveProject(id: UUID) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try projectCommands.archive(projectID: id)
            refresh()
            message = "Project archived. Its sessions remain in reports."
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func restoreProject(id: UUID) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            let result = try projectCommands.restore(projectID: id)
            refresh()
            presentDuplicateWarningIfNeeded(result.warnings)
            return true
        } catch {
            present(error)
            return false
        }
    }

    func startOrSwitch(to projectID: UUID) async {
        guard !isPerformingTimerCommand, !timerCommandsBlocked else { return }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }

        do {
            try throwForcedFailureIfRequested()
            if let activeRun, activeRun.projectID != projectID {
                let result = try timerCommands.switchTimer(to: projectID)
                refresh()
                if case .switched(let completedRun, _) = result {
                    completionRoute = CompletionRoute(
                        sessionID: completedRun.id,
                        kind: .switched
                    )
                    await reconcileLiveActivityProjection()
                }
            } else if let activeRun, activeRun.state == .paused {
                _ = try timerCommands.resume(runID: activeRun.id)
                refresh()
                await reconcileLiveActivityProjection()
            } else {
                let result = try timerCommands.start(projectID: projectID)
                refresh()
                if result.disposition == .started {
                    await reconcileLiveActivityProjection()
                }
            }
        } catch {
            refresh()
            present(error)
        }
    }

    func stopActiveTimer() async {
        guard let runID = activeRun?.id, !isPerformingTimerCommand, !timerCommandsBlocked else { return }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }

        do {
            try throwForcedFailureIfRequested()
            let result = try timerCommands.end(runID: runID)
            refresh()
            completionRoute = CompletionRoute(sessionID: result.run.id, kind: .stopped)
            await reconcileLiveActivityProjection()
        } catch {
            refresh()
            present(error)
        }
    }

    func pauseActiveTimer() async {
        guard let runID = activeRun?.id, !isPerformingTimerCommand, !timerCommandsBlocked else { return }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }
        do {
            try throwForcedFailureIfRequested()
            _ = try timerCommands.pause(runID: runID)
            refresh()
            await reconcileLiveActivityProjection()
        } catch {
            refresh()
            present(error)
        }
    }

    func resumeActiveTimer() async {
        guard let runID = activeRun?.id, !isPerformingTimerCommand, !timerCommandsBlocked else { return }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }
        do {
            try throwForcedFailureIfRequested()
            _ = try timerCommands.resume(runID: runID)
            refresh()
            await reconcileLiveActivityProjection()
        } catch {
            refresh()
            present(error)
        }
    }

    @discardableResult
    func saveNote(sessionID: UUID, note: String) -> Bool {
        saveSessionDetails(sessionID: sessionID, note: note, tagIDs: nil)
    }

    @discardableResult
    func saveSessionDetails(
        sessionID: UUID,
        note: String,
        tagIDs: Set<UUID>?
    ) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            if let run = run(id: sessionID), run.state == .ended {
                _ = try timerCommands.annotate(
                    runID: run.id,
                    note: note,
                    tagIDs: tagIDs ?? Set(run.tags.map(\.tagID))
                )
            } else if let session = session(id: sessionID), let endAt = session.endAt {
                _ = try sessionCommands.editCompleted(
                    sessionID: sessionID,
                    projectID: session.projectID,
                    startAt: session.startAt,
                    endAt: endAt,
                    note: note,
                    tagIDs: tagIDs
                )
            } else {
                message = "That completed session is no longer available."
                return false
            }
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    func overlapWarnings(
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        excludingSessionID: UUID? = nil
    ) throws -> [SessionCommandWarning] {
        try sessionCommands.validateCompletedSession(
            projectID: projectID,
            startAt: startAt,
            endAt: endAt,
            excludingSessionID: excludingSessionID
        )
    }

    @discardableResult
    func createManualSession(
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        note: String?,
        tagIDs: Set<UUID> = []
    ) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try sessionCommands.createManual(
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                note: note,
                tagIDs: tagIDs
            )
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func editCompletedSession(
        sessionID: UUID,
        projectID: UUID,
        startAt: Date,
        endAt: Date,
        note: String?,
        tagIDs: Set<UUID>? = nil
    ) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try sessionCommands.editCompleted(
                sessionID: sessionID,
                projectID: projectID,
                startAt: startAt,
                endAt: endAt,
                note: note,
                tagIDs: tagIDs
            )
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func editActiveSession(sessionID: UUID, startAt: Date, note: String?) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            _ = try sessionCommands.editActive(
                sessionID: sessionID,
                startAt: startAt,
                note: note
            )
            refresh()
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func deleteSession(id: UUID) -> Bool {
        do {
            try throwForcedFailureIfRequested()
            if let run = run(id: id) {
                try timerCommands.delete(runID: run.id, confirmed: true)
            } else {
                _ = try sessionCommands.delete(sessionID: id, confirmed: true)
            }
            refresh()
            message = "Session deleted. Report totals were recalculated."
            return true
        } catch {
            present(error)
            return false
        }
    }

    @discardableResult
    func deleteAllLocalData() async -> Bool {
        guard !isPerformingTimerCommand else { return false }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }

        do {
            do {
                try WellSpentStopHandoff.clear(suiteName: stopHandoffSuiteName)
            } catch WellSpentStopHandoffError.suiteUnavailable {
                // An unavailable App Group has no shared container to erase.
            }
            do {
                try WellSpentSpikeStorage.clearSpikeData(suiteName: stopHandoffSuiteName)
            } catch WellSpentSpikeStorageError.suiteUnavailable {
                // An unavailable App Group has no shared defaults to erase.
            }
            try localDataResetService.deleteAllUserData()
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.completedOnboarding)
            UserDefaults.standard.removeObject(
                forKey: AppPreferenceKeys.showProjectNamesOnLockScreen
            )
            requiresOnboardingAfterReset = true
            completionRoute = nil
            conflictReviewRoute = nil
            liveActivityRecoveryMessage = nil
            stopHandoffRecoveryMessage = nil
            try sessionTagCommands.seedBuiltInsIfNeeded()
            refresh()
            message = nil
            // Erasure, like a timer command, is authoritative before any
            // asynchronous projection. refresh() synchronously fences old work.
            await reconcileLiveActivityProjection()
            if liveActivityRecoveryMessage != nil {
                liveActivityRecoveryMessage =
                    "All WellSpent activity data was deleted. iOS may briefly retain the old Lock Screen card."
            }
            return true
        } catch {
            refresh()
            message = "All local data could not be deleted. No data was sent anywhere. Try again."
            return false
        }
    }

    func acknowledgeOnboardingAfterReset() {
        requiresOnboardingAfterReset = false
    }

    func reportSegments(for selection: ReportSelection, now: Date? = nil) -> [ReportSegment] {
        reportingEngine.segments(
            for: sessions,
            selection: selection,
            calendar: dependencies.makeCalendar(),
            now: now ?? dependencies.now
        )
    }

    func dayInterval(containing date: Date) -> DateInterval? {
        reportingEngine.dayInterval(containing: date, calendar: dependencies.makeCalendar())
    }

    func weekInterval(containing date: Date) -> DateInterval? {
        reportingEngine.weekInterval(containing: date, calendar: dependencies.makeCalendar())
    }

    func inclusiveDayRange(from startDate: Date, through endDate: Date) -> DateInterval? {
        let calendar = dependencies.makeCalendar()
        let start = calendar.startOfDay(for: startDate)
        guard
            let end = calendar.date(
                byAdding: .day,
                value: 1,
                to: calendar.startOfDay(for: endDate)
            ), end > start
        else {
            return nil
        }
        return DateInterval(start: start, end: end)
    }

    func reportTotal(_ segments: [ReportSegment]) -> TimeInterval {
        reportingEngine.total(of: segments)
    }

    func segmentsByProject(_ segments: [ReportSegment]) -> [UUID: [ReportSegment]] {
        reportingEngine.segmentsByProject(segments)
    }

    func segmentsByDay(_ segments: [ReportSegment]) -> [Date: [ReportSegment]] {
        reportingEngine.segmentsByDay(segments, calendar: dependencies.makeCalendar())
    }

    func handle(url: URL) async {
        if let conflictID = WatchReviewLink.conflictID(from: url) {
            openConflictReview(id: conflictID)
            return
        }
        guard let sessionID = WellSpentDeepLink.completionActivityID(from: url) else {
            message = "That link is not supported."
            return
        }
        _ = applyPendingStopRequests()
        refresh()
        await reconcileLiveActivityProjection()
        if let run = run(id: sessionID), run.state == .ended {
            completionRoute = CompletionRoute(sessionID: run.id, kind: .deepLink)
        } else if session(id: sessionID)?.endAt != nil {
            // A manual-session completion URL remains valid for compatibility
            // with existing shortcuts and UI fixtures.
            completionRoute = CompletionRoute(sessionID: sessionID, kind: .deepLink)
        } else {
            message = "The linked completed session could not be found."
        }
    }

    func applicationBecameActive() async {
        activateWatchConnectivity()
        watchConnectivity?.retryPendingTransfers()
        let appliedImmediately = applyPendingStopRequests()
        refresh()
        await reconcileLiveActivityProjection()

        guard !appliedImmediately, activeRun != nil else { return }
        for delay in foregroundHandoffPollDelays {
            try? await Task.sleep(for: delay)
            if applyPendingStopRequests() {
                refresh()
                await reconcileLiveActivityProjection()
                return
            }
        }
    }

    func retryLiveActivityProjection() async {
        _ = applyPendingStopRequests()
        refresh()
        await reconcileLiveActivityProjection()
    }

    func updateLiveActivityPrivacy() async {
        watchConnectivity?.publishLatestSnapshot()
        await reconcileLiveActivityProjection()
    }

    func dismissMessage() {
        message = nil
    }

    private func applyPendingStopRequests() -> Bool {
        do {
            let result = try LiveActivityStopHandoffReconciler(
                suiteName: stopHandoffSuiteName
            ).applyPendingRuns { request in
                guard let run = try timerCommands.run(id: request.sessionID) else {
                    throw LiveActivityStopRejection.obsolete
                }
                if run.state != .ended, let expectedRevision = request.expectedRevision,
                    run.revision != expectedRevision
                {
                    throw LiveActivityStopRejection.obsolete
                }
                return try timerCommands.end(
                    runID: request.sessionID,
                    capturedAt: request.endedAt,
                    timeZoneID: request.endTimeZoneID
                )
            }
            if let lastApplied = result.appliedStops.last {
                completionRoute = CompletionRoute(
                    sessionID: lastApplied.run.id,
                    kind: .deepLink
                )
            }
            if !result.failedSessionIDs.isEmpty {
                stopHandoffRecoveryMessage =
                    "The Lock Screen stop is safely queued. Open the app and retry after reviewing timer recovery."
            } else {
                stopHandoffRecoveryMessage = nil
            }
            liveActivityRecoveryMessage = stopHandoffRecoveryMessage
            if !result.rejectedRunIDs.isEmpty {
                message =
                    "That Lock Screen action referred to an older timer state. Your saved time is unchanged. Use the current timer controls."
            }
            return !result.appliedStops.isEmpty
        } catch {
            stopHandoffRecoveryMessage =
                "The Lock Screen handoff is unavailable. Your in-app timer remains authoritative."
            liveActivityRecoveryMessage = stopHandoffRecoveryMessage
            return false
        }
    }

    private func reconcileLiveActivityProjection() async {
        updateLiveActivityDesiredState()
        await performLiveActivityOperation {
            try await self.liveActivityLifecycle.reconcile()
        }
        updateLiveActivityStatus()
    }

    private func performLiveActivityOperation(
        _ operation: () async throws -> Void
    ) async {
        let operationID = UUID()
        liveActivityOperationID = operationID
        do {
            try await operation()
            guard liveActivityOperationID == operationID else { return }
            liveActivityRecoveryMessage = stopHandoffRecoveryMessage
        } catch LiveActivityLifecycleError.activitiesDisabled {
            guard liveActivityOperationID == operationID else { return }
            liveActivityRecoveryMessage =
                "Your timer is saved, but Live Activities are disabled. Enable them in Settings or continue in the app."
        } catch LiveActivityLifecycleError.foregroundRequired {
            guard liveActivityOperationID == operationID else { return }
            liveActivityRecoveryMessage =
                "Your timer is saved. Open WellSpent on iPhone to show it on the Lock Screen."
        } catch {
            guard liveActivityOperationID == operationID else { return }
            liveActivityRecoveryMessage =
                "Your timer is saved, but the Lock Screen activity is out of date. Retry from the app."
        }
        updateLiveActivityStatus()
    }

    private func updateLiveActivityDesiredState() {
        let candidates = runs.filter { $0.state != .ended }
        // A conflict with a single known canonical run can show a frozen review
        // card. Multiple active runs must never be arbitrarily selected.
        let current = activeRun ?? (timerCommandsBlocked && candidates.count == 1 ? candidates.first : nil)
        liveActivityLifecycle.setDesiredState(
            LiveActivityDesiredState(
                active: current.map { projection(for: $0) },
                completed: runs.filter { $0.state == .ended }.map { projection(for: $0) },
                isCanonicalStateAvailable: liveActivityCanonicalStateAvailable
            )
        )
    }

    private func projection(for run: TimerRunSnapshot) -> LiveActivityProjection {
        let requiresReview = timerCommandsBlocked && run.state != .ended
        let requestedAt: Date
        if requiresReview {
            let reviewBoundary = pendingWatchConflicts.map(\.createdAt).min() ?? run.updatedAt
            requestedAt = max(run.currentSegment?.startAt ?? run.startAt, reviewBoundary)
        } else {
            requestedAt = dependencies.now
        }
        return LiveActivityProjection(
            sessionID: run.id,
            startedAt: run.startAt,
            projectName: project(id: run.projectID)?.displayName ?? "WellSpent timer",
            showsProjectName: showsProjectNameOnLockScreen(),
            requestedAt: requestedAt,
            phase: run.state,
            countedSeconds: run.countedDuration(at: requestedAt),
            currentSegmentStartedAt: run.currentSegment?.startAt,
            revision: run.revision,
            endedAt: run.endAt,
            requiresReview: requiresReview,
            watchConfirmationPending: watchSyncOverview.pendingAcknowledgements > 0
                || watchSyncOverview.awaitingSnapshotReceipt || watchSyncNeedsRetry
        )
    }

    private func updateLiveActivityStatus() {
        liveActivitiesEnabled = liveActivityLifecycle.activitiesEnabled
        isLongRunningSession =
            activeRun.map {
                dependencies.now.timeIntervalSince($0.startAt)
                    >= ActivityKitLiveActivityLifecycle.systemActiveLifetime
            } ?? false
    }

    private func presentDuplicateWarningIfNeeded(_ warnings: [ProjectCommandWarning]) {
        guard
            warnings.contains(where: {
                if case .exactDuplicate = $0 { return true }
                return false
            })
        else {
            return
        }
        message = "Another project has this exact name. Both projects were kept."
    }

    private func throwForcedFailureIfRequested() throws {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("UITEST_FORCE_COMMAND_ERROR") {
                throw AppPresentationError.forcedTestFailure
            }
        #endif
    }

    private func present(_ error: Error) {
        switch error {
        case TimerRunCommandError.reviewRequired, PhoneConflictResolutionError.invalidResolution:
            message = "Review the preserved timer versions before changing this run. Your saved time is unchanged."
        case ProjectCommandError.emptyName:
            message = "Enter a project name."
        case ProjectCommandError.invalidEmoji:
            message = "Choose one emoji or leave the emoji field empty."
        case SessionTagCommandError.emptyName:
            message = "Enter a tag name."
        case SessionTagCommandError.duplicateName(let name):
            message = "The tag “\(name)” is already available."
        case ProjectCommandError.activeTimerMustStopOrSwitch:
            message = "Stop or switch this active timer before archiving its project."
        case SessionCommandError.endMustFollowStart:
            message = "End time must be later than start time."
        case SessionCommandError.startIsInFuture, SessionCommandError.endIsInFuture:
            message = "Session times cannot be in the future."
        case AppPresentationError.forcedTestFailure:
            message = "The change could not be saved. Your existing data was not changed."
        default:
            message = "The change could not be saved. Try again."
        }
    }
}

private enum AppPresentationError: Error {
    case forcedTestFailure
}
