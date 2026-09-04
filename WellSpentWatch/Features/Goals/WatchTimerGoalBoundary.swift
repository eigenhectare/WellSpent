import Foundation
import WellSpentWatchContracts
import WellSpentWatchStore

@MainActor
struct WatchTimerGoalBoundary {
    var now: () -> Date = Date.init
    var timeZoneID: () -> String = { TimeZone.current.identifier }

    func setGoal(
        _ seconds: Int?, runID: UUID, store: WellSpentWatchStore
    ) throws -> WatchCommandCommit? {
        let state = try store.state()
        guard !state.isBlocked, state.projection.updateGuidance?.updateRequired != true,
            let run = state.projection.activeRun, run.id == runID,
            seconds == nil || (seconds! >= 300 && seconds! <= 28_800 && seconds! % 300 == 0)
        else { throw WatchStoreError.commandInvalid }
        guard run.durationGoalSeconds != seconds else { return nil }
        return try store.performLocalCommand(
            .setGoal(SetTimerGoalAction(runID: runID, durationGoalSeconds: seconds)),
            capturedAt: now(), timeZoneID: timeZoneID())
    }
}
