import Foundation
import SwiftData
import SwiftUI
import WellSpentShared

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

@MainActor
final class WellSpentAppModel: ObservableObject {
    @Published private(set) var projects: [ProjectSnapshot] = []
    @Published private(set) var sessions: [TimeSessionSnapshot] = []
    @Published private(set) var sessionTags: [SessionTagSnapshot] = []
    @Published private(set) var activeSession: TimeSessionSnapshot?
    @Published private(set) var startupReconciliation: ActiveSessionReconciliationResult
    @Published private(set) var isPerformingTimerCommand = false
    @Published private(set) var liveActivitiesEnabled = false
    @Published private(set) var liveActivityRecoveryMessage: String?
    @Published private(set) var isLongRunningSession = false
    @Published var completionRoute: CompletionRoute?
    @Published var message: String?

    private let dependencies: WellSpentDependencies
    private let projectCommands: ProjectCommandService
    private let projectQueries: ProjectQueryService
    private let timerCommands: TimerCommandService
    private let sessionCommands: SessionCommandService
    private let sessionRepository: any SessionRepository
    private let sessionTagCommands: SessionTagCommandService
    private let sessionTagRepository: any SessionTagRepository
    private let localDataResetService: WellSpentLocalDataResetService
    private let liveActivityLifecycle: any LiveActivityLifecycle
    private let stopHandoffSuiteName: String
    private let foregroundHandoffPollDelays: [Duration]
    private let showsProjectNameOnLockScreen: () -> Bool
    private let reportingEngine = ReportingEngine()

    init(
        modelContainer: ModelContainer,
        dependencies: WellSpentDependencies,
        startupReconciliation: ActiveSessionReconciliationResult,
        liveActivityLifecycle: (any LiveActivityLifecycle)? = nil,
        stopHandoffSuiteName: String = WellSpentStopHandoff.appGroupIdentifier,
        foregroundHandoffPollDelays: [Duration] = [.milliseconds(250), .milliseconds(500)],
        showsProjectNameOnLockScreen: @escaping () -> Bool = {
            UserDefaults.standard.bool(forKey: AppPreferenceKeys.showProjectNamesOnLockScreen)
        }
    ) {
        let context = ModelContext(modelContainer)
        let projectRepository = SwiftDataProjectRepository(context: context)
        let timerRepository = SwiftDataTimerRepository(context: context)
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
        projectCommands = ProjectCommandService(
            repository: projectRepository,
            dependencies: dependencies
        )
        projectQueries = ProjectQueryService(repository: projectRepository)
        timerCommands = TimerCommandService(
            repository: timerRepository,
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
        let assignedIDs = Set(sessionID.flatMap { session(id: $0)?.tags.map(\.tagID) } ?? [])
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
            let reconciliation = try timerCommands.reconcileActiveState()
            startupReconciliation = reconciliation
            switch reconciliation {
            case .noActiveSession:
                activeSession = nil
            case .active(let session), .reviewRequired(let session, _):
                activeSession = session
            }
            updateLiveActivityStatus()
        } catch {
            present(error)
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
        guard !isPerformingTimerCommand else { return }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }

        do {
            try throwForcedFailureIfRequested()
            if let activeSession, activeSession.projectID != projectID {
                let previousProjection = projection(for: activeSession)
                let result = try timerCommands.switchTimer(to: projectID)
                refresh()
                if case .switched(let completedSession, let newActiveSession) = result {
                    completionRoute = CompletionRoute(
                        sessionID: completedSession.id,
                        kind: .switched
                    )
                    if let previousProjection,
                        let activeProjection = projection(for: newActiveSession)
                    {
                        await performLiveActivityOperation {
                            try await self.liveActivityLifecycle.switchActivity(
                                from: previousProjection,
                                to: activeProjection
                            )
                        }
                    }
                }
            } else {
                let result = try timerCommands.start(projectID: projectID)
                refresh()
                if result.disposition == .started,
                    let projection = projection(for: result.session)
                {
                    await performLiveActivityOperation {
                        try await self.liveActivityLifecycle.start(projection)
                    }
                }
            }
        } catch {
            refresh()
            present(error)
        }
    }

    func stopActiveTimer() async {
        guard let sessionID = activeSession?.id, !isPerformingTimerCommand else { return }
        let activeProjection = activeSession.flatMap { projection(for: $0) }
        isPerformingTimerCommand = true
        defer { isPerformingTimerCommand = false }

        do {
            try throwForcedFailureIfRequested()
            let result = try timerCommands.stop(sessionID: sessionID)
            refresh()
            completionRoute = CompletionRoute(sessionID: result.session.id, kind: .stopped)
            if let activeProjection, let endedAt = result.session.endAt {
                await performLiveActivityOperation {
                    try await self.liveActivityLifecycle.stop(activeProjection, endedAt: endedAt)
                }
            }
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
        guard let session = session(id: sessionID), let endAt = session.endAt else {
            message = "That completed session is no longer available."
            return false
        }

        do {
            try throwForcedFailureIfRequested()
            _ = try sessionCommands.editCompleted(
                sessionID: sessionID,
                projectID: session.projectID,
                startAt: session.startAt,
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
            _ = try sessionCommands.delete(sessionID: id, confirmed: true)
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

        var liveActivityEnded = true
        do {
            try await liveActivityLifecycle.reconcile(with: nil)
        } catch {
            liveActivityEnded = false
        }

        do {
            try WellSpentStopHandoff.clear(suiteName: stopHandoffSuiteName)
            try WellSpentSpikeStorage.clearSpikeData(suiteName: stopHandoffSuiteName)
            try localDataResetService.deleteAllUserData()
            UserDefaults.standard.removeObject(forKey: AppPreferenceKeys.completedOnboarding)
            UserDefaults.standard.removeObject(
                forKey: AppPreferenceKeys.showProjectNamesOnLockScreen
            )
            completionRoute = nil
            liveActivityRecoveryMessage = nil
            try sessionTagCommands.seedBuiltInsIfNeeded()
            refresh()
            message =
                liveActivityEnded
                ? "All WellSpent activity data was deleted from this iPhone."
                : "All WellSpent activity data was deleted. iOS may briefly retain the old Lock Screen card."
            return true
        } catch {
            refresh()
            message = "All local data could not be deleted. No data was sent anywhere. Try again."
            return false
        }
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
        guard let sessionID = WellSpentDeepLink.completionActivityID(from: url) else {
            message = "That link is not supported."
            return
        }
        _ = applyPendingStopRequests()
        refresh()
        guard let session = session(id: sessionID), session.endAt != nil else {
            message = "The linked completed session could not be found."
            return
        }
        completionRoute = CompletionRoute(sessionID: session.id, kind: .deepLink)
    }

    func applicationBecameActive() async {
        let appliedImmediately = applyPendingStopRequests()
        refresh()
        await reconcileLiveActivityProjection()

        guard !appliedImmediately, activeSession != nil else { return }
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
        await reconcileLiveActivityProjection()
    }

    func dismissMessage() {
        message = nil
    }

    private func applyPendingStopRequests() -> Bool {
        do {
            let result = try LiveActivityStopHandoffReconciler(
                suiteName: stopHandoffSuiteName
            ).applyPending { request in
                try timerCommands.stop(
                    sessionID: request.sessionID,
                    capturedAt: request.endedAt,
                    endTimeZoneID: request.endTimeZoneID
                )
            }
            if let lastApplied = result.appliedStops.last {
                completionRoute = CompletionRoute(
                    sessionID: lastApplied.session.id,
                    kind: .deepLink
                )
            }
            if !result.failedSessionIDs.isEmpty {
                liveActivityRecoveryMessage =
                    "The Lock Screen stop is safely queued. Open the app and retry after reviewing timer recovery."
            }
            return !result.appliedStops.isEmpty
        } catch {
            liveActivityRecoveryMessage =
                "The Lock Screen handoff is unavailable. Your in-app timer remains authoritative."
            return false
        }
    }

    private func reconcileLiveActivityProjection() async {
        let activeProjection = activeSession.flatMap { projection(for: $0) }
        await performLiveActivityOperation {
            try await self.liveActivityLifecycle.reconcile(with: activeProjection)
        }
        updateLiveActivityStatus()
    }

    private func performLiveActivityOperation(
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            liveActivityRecoveryMessage = nil
        } catch LiveActivityLifecycleError.activitiesDisabled {
            liveActivityRecoveryMessage =
                "Your timer is saved, but Live Activities are disabled. Enable them in Settings or continue in the app."
        } catch {
            liveActivityRecoveryMessage =
                "Your timer is saved, but the Lock Screen activity is out of date. Retry from the app."
        }
        updateLiveActivityStatus()
    }

    private func projection(for session: TimeSessionSnapshot) -> LiveActivityProjection? {
        guard let project = project(id: session.projectID) else { return nil }
        return LiveActivityProjection(
            sessionID: session.id,
            startedAt: session.startAt,
            projectName: project.displayName,
            showsProjectName: showsProjectNameOnLockScreen(),
            requestedAt: dependencies.now
        )
    }

    private func updateLiveActivityStatus() {
        liveActivitiesEnabled = liveActivityLifecycle.activitiesEnabled
        isLongRunningSession =
            activeSession.map {
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
