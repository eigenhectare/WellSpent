import Foundation
import WellSpentShared

struct StopHandoffReconciliationResult: Equatable, Sendable {
    let appliedStops: [TimerStopResult]
    let failedSessionIDs: [UUID]
}

struct TimerRunStopHandoffReconciliationResult: Equatable, Sendable {
    let appliedStops: [TimerRunEndResult]
    let failedSessionIDs: [UUID]
    let rejectedRunIDs: [UUID]
}

enum LiveActivityStopRejection: Error {
    case obsolete
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

    func applyPendingRuns(
        using end: (WellSpentStopRequest) throws -> TimerRunEndResult
    ) throws -> TimerRunStopHandoffReconciliationResult {
        let requests = try WellSpentStopHandoff.pendingRequests(suiteName: suiteName)
        var appliedStops: [TimerRunEndResult] = []
        var failedSessionIDs: [UUID] = []
        var rejectedRunIDs: [UUID] = []

        for request in requests {
            do {
                let result = try end(request)
                try WellSpentStopHandoff.acknowledge(
                    sessionID: request.sessionID,
                    suiteName: suiteName
                )
                appliedStops.append(result)
            } catch LiveActivityStopRejection.obsolete {
                // A stale action cannot be retried against a different revision.
                // Its removal acknowledges rejection, not a successful stop.
                do {
                    try WellSpentStopHandoff.acknowledge(sessionID: request.sessionID, suiteName: suiteName)
                    rejectedRunIDs.append(request.sessionID)
                } catch {
                    failedSessionIDs.append(request.sessionID)
                }
            } catch {
                failedSessionIDs.append(request.sessionID)
            }
        }
        return TimerRunStopHandoffReconciliationResult(
            appliedStops: appliedStops,
            failedSessionIDs: failedSessionIDs,
            rejectedRunIDs: rejectedRunIDs
        )
    }
}
