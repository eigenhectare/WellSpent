import Foundation
import WellSpentWatchContracts

public enum WatchWidgetTimerState: String, Equatable, Sendable {
    case blocked
    case paused
    case ready
    case running
    case setupRequired
    case updateRequired
}

public struct WatchWidgetProject: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String?
}

/// A bounded, read-only presentation of the persisted local projection. No notes,
/// tags, histories, mutation payloads, or confidential glyphs reach WidgetKit.
public struct WatchWidgetState: Equatable, Sendable {
    public static let kind = "WellSpentWatchStatus"
    public let timerState: WatchWidgetTimerState
    public let runID: UUID?
    public let projectName: String?
    public let openSegmentStartedAt: Date?
    public let countedClosedSeconds: TimeInterval
    public let durationGoalSeconds: Int?
    public let pendingSync: Bool
    public let recentProjects: [WatchWidgetProject]
    public let commandContext: String?

    public static func make(
        projection: WatchCachedProjection,
        pendingSync: Bool,
        isBlocked: Bool,
        recentProjectIDs: [UUID],
        commandContext: String? = nil
    ) -> WatchWidgetState {
        let run = projection.activeRun
        let state: WatchWidgetTimerState
        if projection.updateGuidance?.updateRequired == true {
            state = .updateRequired
        } else if isBlocked || projection.conflict != nil {
            state = .blocked
        } else if run?.state == .running {
            state = .running
        } else if run?.state == .paused {
            state = .paused
        } else if projection.projects.isEmpty {
            state = .setupRequired
        } else {
            state = .ready
        }

        let visibleRun = state == .running || state == .paused ? run : nil
        let segments = projection.activeRunSegments.filter { $0.runID == visibleRun?.id }
        let closedSeconds = segments.reduce(0.0) { total, segment in
            guard let end = segment.endedAt else { return total }
            return total + max(0, end.timeIntervalSince(segment.startedAt))
        }
        let namesAllowed = projection.showProjectNamesOnSystemSurfaces == true
        let byID = Dictionary(projection.projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var seen = Set<UUID>()
        let recent = (recentProjectIDs + projection.projects.map(\.id)).compactMap { id -> WatchWidgetProject? in
            guard seen.insert(id).inserted, let project = byID[id] else { return nil }
            return WatchWidgetProject(id: id, name: namesAllowed ? project.name : nil)
        }
        return WatchWidgetState(
            timerState: state,
            runID: visibleRun?.id,
            projectName: namesAllowed ? visibleRun.flatMap { byID[$0.projectID]?.name } : nil,
            openSegmentStartedAt: state == .running ? segments.first(where: { $0.endedAt == nil })?.startedAt : nil,
            countedClosedSeconds: closedSeconds,
            durationGoalSeconds: visibleRun?.durationGoalSeconds,
            pendingSync: pendingSync,
            recentProjects: state == .ready ? Array(recent.prefix(3)) : [],
            commandContext: commandContext
        )
    }

    public func elapsed(at date: Date) -> TimeInterval {
        countedClosedSeconds + (openSegmentStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    /// SwiftUI owns date-based ticking; extension execution is not a counter.
    public var elapsedTimerStart: Date? {
        openSegmentStartedAt?.addingTimeInterval(-countedClosedSeconds)
    }

    public var goalDeadline: Date? {
        guard let start = elapsedTimerStart, let goal = durationGoalSeconds, goal > 0 else { return nil }
        return start.addingTimeInterval(TimeInterval(goal))
    }

    public func timelineDates(from date: Date) -> [Date] {
        let nextRefresh = date.addingTimeInterval(30 * 60)
        guard let deadline = goalDeadline, deadline > date, deadline < nextRefresh else { return [date] }
        return [date, deadline]
    }

    public var route: WatchWidgetRoute {
        runID.map(WatchWidgetRoute.run) ?? .projects
    }
}

/// A control's observed state is an opaque, content-free precondition, not a
/// command. Local commands and changes to the projected run invalidate it;
/// unrelated catalog/privacy snapshots do not make a current Pause control stale.
public enum WatchCommandContext {
    public static func token(for state: WatchStoreState) -> String {
        token(originID: state.originDeviceID, nextSequence: state.nextOriginSequence, projection: state.projection)
    }

    static func token(originID: UUID, nextSequence: UInt64, projection: WatchCachedProjection) -> String {
        let run = projection.activeRun ?? projection.recentlyEndedRun
        return "\(originID.uuidString):\(nextSequence):\(run?.id.uuidString ?? "none"):\(run?.revision ?? 0)"
    }
}

/// Navigation only. A widget URL can never start, end, or switch a timer.
public enum WatchWidgetRoute: Equatable, Sendable {
    case projects
    case project(UUID)
    case run(UUID)

    public var url: URL {
        switch self {
        case .projects: URL(string: "wellspent-watch://projects")!
        case .project(let id): URL(string: "wellspent-watch://project/\(id.uuidString)")!
        case .run(let id): URL(string: "wellspent-watch://run/\(id.uuidString)")!
        }
    }

    public init?(url: URL) {
        guard url.query == nil, url.fragment == nil,
            url.user == nil, url.password == nil, url.port == nil
        else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        // A mirrored iPhone card must open the current Watch state, never
        // re-create its possibly stale run or replace an active Watch timer.
        if url.scheme == "wellspent" {
            if url.host == "track", parts.isEmpty {
                self = .projects
            } else if url.host == "completion", parts.count == 1, let id = UUID(uuidString: parts[0]) {
                self = .run(id)
            } else {
                return nil
            }
            return
        }
        guard url.scheme == "wellspent-watch" else { return nil }
        if url.host == "projects", parts.isEmpty {
            self = .projects
        } else if parts.count == 1, let id = UUID(uuidString: parts[0]) {
            switch url.host {
            case "project": self = .project(id)
            case "run": self = .run(id)
            default: return nil
            }
        } else {
            return nil
        }
    }

    public func resolved(in projection: WatchCachedProjection, isBlocked: Bool) -> WatchWidgetRoute {
        guard !isBlocked, projection.conflict == nil, projection.updateGuidance?.updateRequired != true else {
            return .projects
        }
        // Never let a stale project/run link displace a newer active run.
        if let run = projection.activeRun { return .run(run.id) }
        if case .project(let id) = self, projection.projects.contains(where: { $0.id == id }) {
            return .project(id)
        }
        return .projects
    }
}
