import ActivityKit
import Foundation

public struct WellSpentActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case running
            case paused
            case stopped
        }

        public var phase: Phase
        public var endedAt: Date?
        public var projectName: String?
        public var showsProjectName: Bool
        public var countedSeconds: Double?
        public var currentSegmentStartedAt: Date?
        public var revision: Int64?
        /// Optional for decoding activities created before the paired app.
        public var requiresReview: Bool?
        public var watchConfirmationPending: Bool?

        public var canStop: Bool { phase != .stopped && requiresReview != true }

        public var syncStatusText: String? {
            if requiresReview == true { return "Review on iPhone" }
            if watchConfirmationPending == true { return "Watch confirmation pending" }
            return nil
        }

        public var statusText: String {
            if requiresReview == true { return "Review required" }
            switch phase {
            case .running:
                return "Running"
            case .paused:
                return "Paused"
            case .stopped:
                return "Stopped"
            }
        }

        public var displayLabel: String {
            guard showsProjectName, requiresReview != true,
                let projectName,
                !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "WellSpent timer"
            }
            return projectName
        }

        public var stopAccessibilityLabel: String {
            showsProjectName ? "Stop \(displayLabel) timer" : "Stop WellSpent timer"
        }

        public func destinationURL(runID: UUID) -> URL {
            phase == .stopped && requiresReview != true
                ? WellSpentDeepLink.completionURL(for: runID) : WellSpentDeepLink.trackerURL
        }

        /// Date-based system text advances without waking a widget every second.
        public func timerAnchor(legacyStartedAt: Date) -> Date? {
            guard phase == .running, requiresReview != true else { return nil }
            guard let currentSegmentStartedAt else { return countedSeconds == nil ? legacyStartedAt : nil }
            return currentSegmentStartedAt.addingTimeInterval(-max(0, countedSeconds ?? 0))
        }

        public init(
            phase: Phase,
            endedAt: Date? = nil,
            projectName: String? = nil,
            showsProjectName: Bool = false,
            countedSeconds: Double? = nil,
            currentSegmentStartedAt: Date? = nil,
            revision: Int64? = nil,
            requiresReview: Bool? = nil,
            watchConfirmationPending: Bool? = nil
        ) {
            self.phase = phase
            self.endedAt = endedAt
            // Privacy is enforced in the payload, not only in a view label.
            self.projectName = showsProjectName && requiresReview != true ? projectName : nil
            self.showsProjectName = showsProjectName
            self.countedSeconds = countedSeconds
            self.currentSegmentStartedAt = currentSegmentStartedAt
            self.revision = revision
            self.requiresReview = requiresReview
            self.watchConfirmationPending = watchConfirmationPending
        }

        public func elapsed(at date: Date, legacyStartedAt: Date) -> TimeInterval {
            let base = countedSeconds ?? 0
            if phase == .running, requiresReview != true, let currentSegmentStartedAt {
                return max(0, base + date.timeIntervalSince(currentSegmentStartedAt))
            }
            if countedSeconds != nil { return max(0, base) }
            return max(0, (endedAt ?? date).timeIntervalSince(legacyStartedAt))
        }
    }

    /// The authoritative TimerRun UUID for v3 activities. For one compatibility
    /// release, a pre-v3 activity may still contain its timed-session UUID.
    public var activityID: UUID
    public var startedAt: Date

    public var runID: UUID { activityID }

    public init(activityID: UUID, startedAt: Date) {
        self.activityID = activityID
        self.startedAt = startedAt
    }
}
