import Foundation

struct SessionInterval: Equatable, Sendable {
    let sessionID: UUID
    let startAt: Date
    let endAt: Date?
}

struct SessionOverlapPair: Equatable, Hashable, Sendable {
    let firstSessionID: UUID
    let secondSessionID: UUID

    init(_ firstSessionID: UUID, _ secondSessionID: UUID) {
        if firstSessionID.uuidString < secondSessionID.uuidString {
            self.firstSessionID = firstSessionID
            self.secondSessionID = secondSessionID
        } else {
            self.firstSessionID = secondSessionID
            self.secondSessionID = firstSessionID
        }
    }
}

struct SessionOverlapResult: Equatable, Sendable {
    let pairs: [SessionOverlapPair]
    let overlappingSessionIDs: [UUID]

    func contains(sessionID: UUID) -> Bool {
        overlappingSessionIDs.contains(sessionID)
    }
}

/// Detects informational overlaps without changing, merging, or clamping any
/// source interval. All comparisons use half-open intervals.
struct SessionOverlapDetector: Sendable {
    func overlaps(
        _ first: SessionInterval,
        _ second: SessionInterval,
        activeEndAt: Date
    ) -> Bool {
        guard first.sessionID != second.sessionID,
            let firstEnd = resolvedValidEnd(for: first, activeEndAt: activeEndAt),
            let secondEnd = resolvedValidEnd(for: second, activeEndAt: activeEndAt)
        else {
            return false
        }

        return intervalsOverlap(
            firstStart: first.startAt,
            firstEnd: firstEnd,
            secondStart: second.startAt,
            secondEnd: secondEnd
        )
    }

    func detect(
        in intervals: [SessionInterval],
        activeEndAt: Date
    ) -> SessionOverlapResult {
        var pairs = Set<SessionOverlapPair>()

        for firstIndex in intervals.indices {
            for secondIndex in intervals.indices where secondIndex > firstIndex {
                let first = intervals[firstIndex]
                let second = intervals[secondIndex]
                guard overlaps(first, second, activeEndAt: activeEndAt) else {
                    continue
                }
                pairs.insert(SessionOverlapPair(first.sessionID, second.sessionID))
            }
        }

        let sortedPairs = pairs.sorted(by: pairIsOrderedBefore)
        let overlappingSessionIDs = Set(
            sortedPairs.flatMap { [$0.firstSessionID, $0.secondSessionID] }
        ).sorted(by: uuidIsOrderedBefore)

        return SessionOverlapResult(
            pairs: sortedPairs,
            overlappingSessionIDs: overlappingSessionIDs
        )
    }

    func overlappingSessionIDs(
        startAt: Date,
        endAt: Date?,
        in intervals: [SessionInterval],
        activeEndAt: Date,
        excludingSessionID: UUID? = nil
    ) -> [UUID] {
        guard
            let candidateEnd = resolvedValidEnd(
                startAt: startAt,
                endAt: endAt,
                activeEndAt: activeEndAt
            )
        else {
            return []
        }

        return Set(
            intervals.compactMap { interval in
                guard interval.sessionID != excludingSessionID,
                    let intervalEnd = resolvedValidEnd(for: interval, activeEndAt: activeEndAt),
                    intervalsOverlap(
                        firstStart: startAt,
                        firstEnd: candidateEnd,
                        secondStart: interval.startAt,
                        secondEnd: intervalEnd
                    )
                else {
                    return nil
                }
                return interval.sessionID
            }
        ).sorted(by: uuidIsOrderedBefore)
    }

    private func resolvedValidEnd(
        for interval: SessionInterval,
        activeEndAt: Date
    ) -> Date? {
        resolvedValidEnd(
            startAt: interval.startAt,
            endAt: interval.endAt,
            activeEndAt: activeEndAt
        )
    }

    private func resolvedValidEnd(
        startAt: Date,
        endAt: Date?,
        activeEndAt: Date
    ) -> Date? {
        let resolvedEndAt = endAt ?? activeEndAt
        guard startAt.timeIntervalSinceReferenceDate.isFinite,
            resolvedEndAt.timeIntervalSinceReferenceDate.isFinite,
            resolvedEndAt > startAt
        else {
            return nil
        }
        return resolvedEndAt
    }

    private func intervalsOverlap(
        firstStart: Date,
        firstEnd: Date,
        secondStart: Date,
        secondEnd: Date
    ) -> Bool {
        firstStart < secondEnd && secondStart < firstEnd
    }

    private func pairIsOrderedBefore(
        _ first: SessionOverlapPair,
        _ second: SessionOverlapPair
    ) -> Bool {
        if first.firstSessionID == second.firstSessionID {
            return uuidIsOrderedBefore(first.secondSessionID, second.secondSessionID)
        }
        return uuidIsOrderedBefore(first.firstSessionID, second.firstSessionID)
    }

    private func uuidIsOrderedBefore(_ first: UUID, _ second: UUID) -> Bool {
        first.uuidString < second.uuidString
    }
}
