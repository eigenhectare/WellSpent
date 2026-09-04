import Foundation
import WellSpentWatchContracts
import WellSpentWatchStore

@MainActor
struct WatchSystemCommandBoundary {
    var now: () -> Date = Date.init
    var timeZoneID: () -> String = { TimeZone.autoupdatingCurrent.identifier }
    var makeUUID: () -> UUID = UUID.init

    func perform(_ request: WatchSystemRequest, store: WellSpentWatchStore) throws -> WatchCommandCommit? {
        if request.action == .open { return nil }
        let state = try store.state()
        guard state.projection.updateGuidance?.updateRequired != true else {
            throw WatchSystemActionError.updateRequired
        }
        guard !state.isBlocked else { throw WatchSystemActionError.reviewRequired }
        if let context = request.expectedContext, context != WatchCommandContext.token(for: state) {
            throw WatchSystemActionError.staleControl
        }
        let persist: WatchTimerStartBoundary.Persist = { action, date, zone in
            try store.performLocalCommand(action, capturedAt: date, timeZoneID: zone)
        }
        let controls = WatchTimerControlBoundary(now: now, timeZoneID: timeZoneID, makeUUID: makeUUID)
        let run = state.projection.activeRun
        let segments = state.projection.activeRunSegments
        switch request.action {
        case .open: return nil
        case .start:
            let project = try project(for: request, in: state)
            if let run {
                guard run.projectID == project.id else { throw WatchSystemActionError.staleControl }
                return nil
            }
            return try WatchTimerStartBoundary(now: now, timeZoneID: timeZoneID, makeUUID: makeUUID)
                .start(WatchStartRequest(project: project, durationGoalSeconds: nil), persist: persist)
        case .pause:
            guard let run else { throw WatchSystemActionError.staleControl }
            guard run.state != .paused else { return nil }
            return try controls.pause(run: run, segments: segments, persist: persist)
        case .resume:
            guard let run else { throw WatchSystemActionError.staleControl }
            guard run.state != .running else { return nil }
            return try controls.resume(run: run, segments: segments, persist: persist)
        case .switchProject:
            let project = try project(for: request, in: state)
            guard let run else { throw WatchSystemActionError.staleControl }
            guard run.projectID != project.id else { return nil }
            return try controls.switchRun(
                run: run, segments: segments, request: WatchStartRequest(project: project, durationGoalSeconds: nil),
                persist: persist)
        case .end:
            guard let run else { return nil }
            return try controls.end(run: run, segments: segments, persist: persist)
        }
    }

    private func project(for request: WatchSystemRequest, in state: WatchStoreState) throws -> ProjectSnapshot {
        guard let project = state.projection.projects.first(where: { $0.id == request.projectID }) else {
            throw WatchSystemActionError.setupRequired
        }
        return project
    }
}
