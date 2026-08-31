import ActivityKit
import AppIntents
import Foundation

public struct StopBillableTimerIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop Billable Timer"
    public static let description = IntentDescription(
        "Persist the stop time, end the Live Activity, and open the completion screen.")
    public static let isDiscoverable = false
    public static let openAppWhenRun = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Activity ID")
    public var activityID: String

    public init() {}

    public init(activityID: UUID) {
        self.activityID = activityID.uuidString
    }

    public func perform() async throws -> some IntentResult {
        guard let sessionID = UUID(uuidString: activityID) else {
            throw StopBillableTimerIntentError.invalidActivityID
        }

        let capturedEndTime = Date.now
        let request = try BillableHoursStopHandoff.persist(
            sessionID: sessionID,
            endedAt: capturedEndTime,
            endTimeZoneID: TimeZone.autoupdatingCurrent.identifier
        )

        for activity in Activity<BillableHoursActivityAttributes>.activities
        where activity.attributes.activityID == sessionID {
            let currentState = activity.content.state
            let finalState = BillableHoursActivityAttributes.ContentState(
                phase: .stopped,
                endedAt: request.endedAt,
                projectName: currentState.projectName,
                showsProjectName: currentState.showsProjectName
            )
            let finalContent = ActivityContent(state: finalState, staleDate: nil)
            await activity.end(finalContent, dismissalPolicy: .default)
        }

        return .result()
    }
}

public enum StopBillableTimerIntentError: LocalizedError {
    case invalidActivityID

    public var errorDescription: String? {
        "The Live Activity identifier is invalid."
    }
}
