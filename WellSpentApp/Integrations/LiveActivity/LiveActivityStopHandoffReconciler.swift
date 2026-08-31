import Foundation
import WellSpentShared

struct StopHandoffReconciliationResult: Equatable, Sendable {
    let appliedStops: [TimerStopResult]
    let failedSessionIDs: [UUID]
}

@MainActor
struct LiveActivityStopHandoffReconciler {
    let suiteName: String

    func applyPending(
        using stop: (WellSpentStopRequest) throws -> TimerStopResult
    ) throws -> StopHandoffReconciliationResult {
        let requests = try WellSpentStopHandoff.pendingRequests(suiteName: suiteName)
        var appliedStops: [TimerStopResult] = []
        var failedSessionIDs: [UUID] = []

        for request in requests {
            do {
                let result = try stop(request)
                try WellSpentStopHandoff.acknowledge(
                    sessionID: request.sessionID,
                    suiteName: suiteName
                )
                appliedStops.append(result)
            } catch {
                failedSessionIDs.append(request.sessionID)
            }
        }

        return StopHandoffReconciliationResult(
            appliedStops: appliedStops,
            failedSessionIDs: failedSessionIDs
        )
    }
}
