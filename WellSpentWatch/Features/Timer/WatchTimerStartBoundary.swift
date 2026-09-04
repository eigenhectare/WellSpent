import Foundation
import WellSpentWatchContracts
import WellSpentWatchStore

/// Captures the one authoritative Start boundary and constructs the complete
/// command before invoking the Watch-local atomic persistence transaction.
struct WatchTimerStartBoundary {
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

    func start(
        _ request: WatchStartRequest,
        persist: Persist
    ) throws -> WatchCommandCommit {
        let capturedAt = now()
        let capturedTimeZoneID = timeZoneID()
        let action = TimerMutationAction.start(
            StartTimerAction(
                runID: makeUUID(),
                segmentID: makeUUID(),
                projectID: request.project.id,
                durationGoalSeconds: request.durationGoalSeconds
            )
        )
        return try persist(action, capturedAt, capturedTimeZoneID)
    }
}
