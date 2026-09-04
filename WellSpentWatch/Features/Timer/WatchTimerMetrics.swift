import Foundation
import WellSpentWatchContracts

struct WatchTimerMetrics: Equatable, Sendable {
    struct Goal: Equatable, Sendable {
        let targetSeconds: TimeInterval
        let progress: Double
        let remainingSeconds: TimeInterval
        let overtimeSeconds: TimeInterval

        var isReached: Bool { remainingSeconds == 0 }
    }

    let billableSeconds: TimeInterval
    let pausedSeconds: TimeInterval
    let wallSeconds: TimeInterval
    let segmentCount: Int
    let goal: Goal?

    static func calculate(
        run: TimerRunSnapshot,
        segments: [TimerSegmentSnapshot],
        at presentationDate: Date
    ) -> WatchTimerMetrics {
        let runEnd = min(run.endedAt ?? presentationDate, presentationDate)
        let wallSeconds = max(0, runEnd.timeIntervalSince(run.startedAt))
        let ownedSegments = segments.filter { $0.runID == run.id }
        let billableSeconds = ownedSegments.reduce(0.0) { partial, segment in
            let segmentEnd: Date
            if let endedAt = segment.endedAt {
                segmentEnd = min(endedAt, runEnd)
            } else if run.state == .running {
                segmentEnd = runEnd
            } else {
                // A healthy paused run has no open segment. Keeping an invalid
                // open segment frozen is the safest presentation fallback.
                segmentEnd = segment.startedAt
            }
            return partial + max(0, segmentEnd.timeIntervalSince(segment.startedAt))
        }
        let pausedSeconds = max(0, wallSeconds - billableSeconds)
        let goal = run.durationGoalSeconds.flatMap { target -> Goal? in
            guard target > 0 else { return nil }
            let targetSeconds = TimeInterval(target)
            return Goal(
                targetSeconds: targetSeconds,
                progress: min(1, billableSeconds / targetSeconds),
                remainingSeconds: max(0, targetSeconds - billableSeconds),
                overtimeSeconds: max(0, billableSeconds - targetSeconds)
            )
        }

        return WatchTimerMetrics(
            billableSeconds: billableSeconds,
            pausedSeconds: pausedSeconds,
            wallSeconds: wallSeconds,
            segmentCount: ownedSegments.count,
            goal: goal
        )
    }
}

enum WatchTotalsFreshness: Equatable, Sendable {
    case current
    case offline
    case stale

    static func classify(
        _ totals: TimerTotalsSnapshot,
        at presentationDate: Date,
        isReachable: Bool,
        staleAfter: TimeInterval = 5 * 60
    ) -> WatchTotalsFreshness {
        guard isReachable else { return .offline }
        guard let timeZone = TimeZone(identifier: totals.calendarTimeZoneID) else {
            return .stale
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let age = presentationDate.timeIntervalSince(totals.calculatedAt)
        guard age >= -staleAfter,
            age <= staleAfter,
            calendar.isDate(presentationDate, inSameDayAs: totals.calculatedAt)
        else {
            return .stale
        }
        return .current
    }
}

enum WatchDurationText {
    static func digital(_ interval: TimeInterval) -> String {
        let totalSeconds = wholeSeconds(interval)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return "\(hours):\(twoDigits(minutes)):\(twoDigits(seconds))"
        }
        return "\(minutes):\(twoDigits(seconds))"
    }

    static func spoken(_ interval: TimeInterval, locale: Locale = .autoupdatingCurrent) -> String {
        let totalSeconds = wholeSeconds(interval)
        // Foundation owns unit order, separators and plural rules. Digital
        // elapsed time deliberately remains the compact, nonlocalized counter.
        return Duration.seconds(totalSeconds).formatted(
            .units(allowed: [.hours, .minutes, .seconds], width: .wide).locale(locale)
        )
    }

    private static func wholeSeconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        // Double(Int.max) rounds above Int.max; never convert that boundary.
        guard interval < Double(Int.max) else { return Int.max }
        return interval > 0 ? Int(interval.rounded(.down)) : 0
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

enum WatchProjectIdentity {
    static var privateName: String { String(localized: "Billable timer") }

    static func displayName(_ projectName: String?, redacted: Bool) -> String {
        guard !redacted, let projectName, !projectName.isEmpty else {
            return privateName
        }
        return projectName
    }
}
