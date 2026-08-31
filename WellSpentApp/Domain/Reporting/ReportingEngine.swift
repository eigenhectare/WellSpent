import Foundation

struct ReportSegmentID: Hashable, Sendable {
    let sessionID: UUID
    let startAt: Date
    let endAt: Date
}

/// A presentation-ready slice of one source session. Report totals are always
/// derived from these exact slices so every number remains explainable.
struct ReportSegment: Identifiable, Equatable, Hashable, Sendable {
    var id: ReportSegmentID {
        ReportSegmentID(sessionID: sessionID, startAt: startAt, endAt: endAt)
    }

    let sessionID: UUID
    let projectID: UUID
    let startAt: Date
    let endAt: Date
    let sourceStartAt: Date
    let sourceEndAt: Date?
    let note: String?
    let isActive: Bool
    let overlapsAnotherSession: Bool

    var duration: TimeInterval {
        endAt.timeIntervalSince(startAt)
    }
}

struct ReportSelection: Equatable, Hashable, Sendable {
    let interval: DateInterval
    let projectID: UUID?

    init(interval: DateInterval, projectID: UUID? = nil) {
        self.interval = interval
        self.projectID = projectID
    }
}

struct ReportingEngine: Sendable {
    private let overlapDetector = SessionOverlapDetector()

    func dayInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .day, for: date)
    }

    func weekInterval(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }

    func segments(
        for sessions: [TimeSessionSnapshot],
        selection: ReportSelection,
        calendar: Calendar,
        now: Date
    ) -> [ReportSegment] {
        guard isValid(selection.interval), now.timeIntervalSinceReferenceDate.isFinite else {
            return []
        }

        let intervals = sessions.map {
            SessionInterval(sessionID: $0.id, startAt: $0.startAt, endAt: $0.endAt)
        }
        let overlappingIDs = Set(
            overlapDetector.detect(in: intervals, activeEndAt: now).overlappingSessionIDs
        )

        return
            sessions
            .filter { selection.projectID == nil || $0.projectID == selection.projectID }
            .flatMap { session in
                split(
                    session,
                    within: selection.interval,
                    calendar: calendar,
                    now: now,
                    overlapsAnotherSession: overlappingIDs.contains(session.id)
                )
            }
            .sorted(by: segmentIsOrderedBefore)
    }

    func total(of segments: [ReportSegment]) -> TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    func segmentsByProject(_ segments: [ReportSegment]) -> [UUID: [ReportSegment]] {
        Dictionary(grouping: segments, by: \.projectID)
    }

    func segmentsByDay(
        _ segments: [ReportSegment],
        calendar: Calendar
    ) -> [Date: [ReportSegment]] {
        Dictionary(grouping: segments) { calendar.startOfDay(for: $0.startAt) }
    }

    private func split(
        _ session: TimeSessionSnapshot,
        within reportInterval: DateInterval,
        calendar: Calendar,
        now: Date,
        overlapsAnotherSession: Bool
    ) -> [ReportSegment] {
        let resolvedEndAt = session.endAt ?? now
        guard session.startAt.timeIntervalSinceReferenceDate.isFinite,
            resolvedEndAt.timeIntervalSinceReferenceDate.isFinite,
            resolvedEndAt > session.startAt
        else {
            return []
        }

        let intersectionStart = max(session.startAt, reportInterval.start)
        let intersectionEnd = min(resolvedEndAt, reportInterval.end)
        guard intersectionEnd > intersectionStart else {
            return []
        }

        var result: [ReportSegment] = []
        var cursor = intersectionStart

        while cursor < intersectionEnd {
            let nextBoundary = calendar.dateInterval(of: .day, for: cursor)?.end
            let segmentEnd = min(nextBoundary ?? intersectionEnd, intersectionEnd)
            guard segmentEnd > cursor else {
                break
            }

            result.append(
                ReportSegment(
                    sessionID: session.id,
                    projectID: session.projectID,
                    startAt: cursor,
                    endAt: segmentEnd,
                    sourceStartAt: session.startAt,
                    sourceEndAt: session.endAt,
                    note: session.note,
                    isActive: session.endAt == nil,
                    overlapsAnotherSession: overlapsAnotherSession
                )
            )
            cursor = segmentEnd
        }

        return result
    }

    private func isValid(_ interval: DateInterval) -> Bool {
        interval.start.timeIntervalSinceReferenceDate.isFinite
            && interval.end.timeIntervalSinceReferenceDate.isFinite
            && interval.end > interval.start
    }

    private func segmentIsOrderedBefore(_ first: ReportSegment, _ second: ReportSegment) -> Bool {
        if first.startAt != second.startAt {
            return first.startAt < second.startAt
        }
        if first.endAt != second.endAt {
            return first.endAt < second.endAt
        }
        return first.sessionID.uuidString < second.sessionID.uuidString
    }
}
