import Foundation
import WellSpentWatchContracts
import WellSpentWatchStore

enum WatchTimerControlBoundaryError: Error, Equatable {
    case invalidRunState
    case invalidSwitchDestination
}

enum WatchTimerControlOperation: String, Equatable, Sendable {
    case end
    case pause
    case resume
    case switchRun = "switch"

    var progressTitle: String {
        switch self {
        case .end: String(localized: "Ending…")
        case .pause: String(localized: "Pausing…")
        case .resume: String(localized: "Resuming…")
        case .switchRun: String(localized: "Switching…")
        }
    }
}

struct WatchTimerControlFailure: Equatable, Identifiable {
    let operation: WatchTimerControlOperation
    let switchRequest: WatchStartRequest?

    var id: WatchTimerControlOperation { operation }

    var title: String {
        switch operation {
        case .end: String(localized: "Couldn’t end")
        case .pause: String(localized: "Couldn’t pause")
        case .resume: String(localized: "Couldn’t resume")
        case .switchRun: String(localized: "Couldn’t switch")
        }
    }

    var message: String {
        switch operation {
        case .switchRun:
            String(localized: "The original run is unchanged. Try again or keep the current timer.")
        case .end, .pause, .resume:
            String(localized: "The run is unchanged. Try again when you’re ready.")
        }
    }
}

/// Constructs complete TimerRun commands at one captured boundary. The type has
/// no SwiftUI or WatchConnectivity dependency so future App Intents can invoke
/// the same persistence adapter instead of duplicating timer rules.
struct WatchTimerControlBoundary {
    typealias Persist = (TimerMutationAction, Date, String) throws -> WatchCommandCommit

    private let now: () -> Date
    private let timeZoneID: () -> String
    private let makeUUID: () -> UUID

    init(
        now: @escaping () -> Date = Date.init,
        timeZoneID: @escaping () -> String = { TimeZone.autoupdatingCurrent.identifier },
        makeUUID: @escaping () -> UUID = UUID.init
    ) {
        self.now = now
        self.timeZoneID = timeZoneID
        self.makeUUID = makeUUID
    }

    func pause(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        persist: Persist
    ) throws -> WatchCommandCommit {
        guard run.state == .running, let openSegmentID = onlyOpenSegmentID(in: segments) else {
            throw WatchTimerControlBoundaryError.invalidRunState
        }
        return try captureAndPersist(
            .pause(PauseTimerAction(runID: run.id, openSegmentID: openSegmentID)),
            persist: persist
        )
    }

    func resume(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        persist: Persist
    ) throws -> WatchCommandCommit {
        guard run.state == .paused, !segments.isEmpty,
            segments.allSatisfy({ $0.runID == run.id && $0.endedAt != nil })
        else {
            throw WatchTimerControlBoundaryError.invalidRunState
        }
        return try captureAndPersist(
            .resume(ResumeTimerAction(runID: run.id, newSegmentID: makeUUID())),
            persist: persist
        )
    }

    func end(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        persist: Persist
    ) throws -> WatchCommandCommit {
        guard run.state != .ended else {
            throw WatchTimerControlBoundaryError.invalidRunState
        }
        let openSegmentID: UUID?
        switch run.state {
        case .running:
            guard let current = onlyOpenSegmentID(in: segments) else {
                throw WatchTimerControlBoundaryError.invalidRunState
            }
            openSegmentID = current
        case .paused:
            guard !segments.isEmpty,
                segments.allSatisfy({ $0.runID == run.id && $0.endedAt != nil })
            else {
                throw WatchTimerControlBoundaryError.invalidRunState
            }
            openSegmentID = nil
        case .ended:
            throw WatchTimerControlBoundaryError.invalidRunState
        }
        return try captureAndPersist(
            .end(EndTimerAction(runID: run.id, openSegmentID: openSegmentID)),
            persist: persist
        )
    }

    func switchRun(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        request: WatchStartRequest,
        persist: Persist
    ) throws -> WatchCommandCommit {
        guard run.state != .ended, request.project.id != run.projectID else {
            throw WatchTimerControlBoundaryError.invalidSwitchDestination
        }
        let openSegmentID: UUID?
        switch run.state {
        case .running:
            guard let current = onlyOpenSegmentID(in: segments) else {
                throw WatchTimerControlBoundaryError.invalidRunState
            }
            openSegmentID = current
        case .paused:
            guard !segments.isEmpty,
                segments.allSatisfy({ $0.runID == run.id && $0.endedAt != nil })
            else {
                throw WatchTimerControlBoundaryError.invalidRunState
            }
            openSegmentID = nil
        case .ended:
            throw WatchTimerControlBoundaryError.invalidRunState
        }

        return try captureAndPersist(
            .switch(
                SwitchTimerAction(
                    fromRunID: run.id,
                    openSegmentID: openSegmentID,
                    toRunID: makeUUID(),
                    toSegmentID: makeUUID(),
                    projectID: request.project.id,
                    durationGoalSeconds: request.durationGoalSeconds
                )
            ),
            persist: persist
        )
    }

    private func captureAndPersist(
        _ action: TimerMutationAction,
        persist: Persist
    ) throws -> WatchCommandCommit {
        try persist(action, now(), timeZoneID())
    }

    private func onlyOpenSegmentID(in segments: [TimerSegmentSnapshot]) -> UUID? {
        let openSegments = segments.filter { $0.endedAt == nil }
        guard openSegments.count == 1 else { return nil }
        return openSegments[0].id
    }
}
