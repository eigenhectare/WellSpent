import ActivityKit
import Foundation

public struct BillableHoursActivityAttributes: ActivityAttributes, Sendable {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Phase: String, Codable, Hashable, Sendable {
            case running
            case stopped
        }

        public var phase: Phase
        public var endedAt: Date?
        public var projectName: String?
        public var showsProjectName: Bool

        public var statusText: String {
            switch phase {
            case .running:
                "Running"
            case .stopped:
                "Stopped"
            }
        }

        public var displayLabel: String {
            guard showsProjectName,
                let projectName,
                !projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return "Billable timer"
            }
            return projectName
        }

        public var stopAccessibilityLabel: String {
            showsProjectName ? "Stop \(displayLabel) timer" : "Stop billable timer"
        }

        public init(
            phase: Phase,
            endedAt: Date? = nil,
            projectName: String? = nil,
            showsProjectName: Bool = false
        ) {
            self.phase = phase
            self.endedAt = endedAt
            self.projectName = projectName
            self.showsProjectName = showsProjectName
        }
    }

    /// The authoritative timed-session UUID. ActivityKit's own string ID is
    /// intentionally not used as a persistence identity.
    public var activityID: UUID
    public var startedAt: Date

    public init(activityID: UUID, startedAt: Date) {
        self.activityID = activityID
        self.startedAt = startedAt
    }
}
