import AppIntents
import Foundation

public struct StopWellSpentTimerIntent: LiveActivityIntent {
    public static let title: LocalizedStringResource = "Stop WellSpent Timer"
    public static let description = IntentDescription(
        "Save a stop request and open WellSpent to finish saving the timer.")
    public static let isDiscoverable = false
    public static let openAppWhenRun = true
    public static let authenticationPolicy: IntentAuthenticationPolicy = .requiresLocalDeviceAuthentication

    @Parameter(title: "Activity ID")
    public var activityID: String

    @Parameter(title: "Run revision")
    public var expectedRevision: Int?

    public init() {}

    public init(activityID: UUID, revision: Int64? = nil) {
        self.activityID = activityID.uuidString
        self.expectedRevision = revision.flatMap { Int(exactly: $0) }
    }

    public func perform() async throws -> some IntentResult {
        guard let sessionID = UUID(uuidString: activityID) else {
            throw StopWellSpentTimerIntentError.invalidActivityID
        }

        let capturedEndTime = Date.now
        try WellSpentStopHandoff.persist(
            sessionID: sessionID,
            endedAt: capturedEndTime,
            endTimeZoneID: TimeZone.autoupdatingCurrent.identifier,
            expectedRevision: expectedRevision.map(Int64.init)
        )

        // The host applies this durable request to SwiftData first. Only its
        // canonical projection reconciler may end or update ActivityKit. A
        // queued request is not evidence that a timer was successfully stopped.
        await WellSpentLiveActivityHandoffDispatcher.reconcile?()

        return .result()
    }
}

/// LiveActivityIntent normally executes in its containing app. The app installs
/// this bridge when its model is ready; cold-launch/other-process execution is
/// still safe because the protected handoff remains durable until acknowledged.
@MainActor
public enum WellSpentLiveActivityHandoffDispatcher {
    public static var reconcile: (@MainActor () async -> Void)?
}

public enum StopWellSpentTimerIntentError: LocalizedError {
    case invalidActivityID

    public var errorDescription: String? {
        "The Live Activity identifier is invalid."
    }
}
