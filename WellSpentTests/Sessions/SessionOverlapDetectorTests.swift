import Foundation
import XCTest

@testable import WellSpent

final class SessionOverlapDetectorTests: XCTestCase {
    private let detector = SessionOverlapDetector()
    private let now = Date(timeIntervalSince1970: 1_000)

    func testNestedIntervalsOverlapInEitherArgumentOrder() {
        let outer = interval(1, start: 100, end: 400)
        let inner = interval(2, start: 200, end: 300)

        XCTAssertTrue(detector.overlaps(outer, inner, activeEndAt: now))
        XCTAssertTrue(detector.overlaps(inner, outer, activeEndAt: now))
    }

    func testPartialOverlapsAreDetectedAtBothEnds() {
        let center = interval(1, start: 200, end: 400)
        let earlier = interval(2, start: 100, end: 250)
        let later = interval(3, start: 350, end: 500)

        XCTAssertTrue(detector.overlaps(center, earlier, activeEndAt: now))
        XCTAssertTrue(detector.overlaps(center, later, activeEndAt: now))
    }

    func testIdenticalIntervalsOverlap() {
        XCTAssertTrue(
            detector.overlaps(
                interval(1, start: 100, end: 200),
                interval(2, start: 100, end: 200),
                activeEndAt: now
            )
        )
    }

    func testAdjacentHalfOpenIntervalsDoNotOverlap() {
        let earlier = interval(1, start: 100, end: 200)
        let later = interval(2, start: 200, end: 300)

        XCTAssertFalse(detector.overlaps(earlier, later, activeEndAt: now))
        XCTAssertFalse(detector.overlaps(later, earlier, activeEndAt: now))
    }

    func testActiveIntervalUsesInjectedReferenceTimeAgainstManualSessions() {
        let active = interval(1, start: 200, end: nil)
        let before = interval(2, start: 100, end: 200)
        let overlapping = interval(3, start: 300, end: 400)
        let afterReferenceTime = interval(4, start: 1_000, end: 1_100)

        XCTAssertFalse(detector.overlaps(active, before, activeEndAt: now))
        XCTAssertTrue(detector.overlaps(active, overlapping, activeEndAt: now))
        XCTAssertFalse(detector.overlaps(active, afterReferenceTime, activeEndAt: now))
    }

    func testDetectionReturnsEveryPairAndAffectedSessionInStableOrder() {
        let intervals = [
            interval(4, start: 400, end: 500),
            interval(2, start: 150, end: 350),
            interval(1, start: 100, end: 300),
            interval(3, start: 250, end: 450),
        ]

        let result = detector.detect(in: intervals, activeEndAt: now)

        XCTAssertEqual(
            result.pairs,
            [
                SessionOverlapPair(id(1), id(2)),
                SessionOverlapPair(id(1), id(3)),
                SessionOverlapPair(id(2), id(3)),
                SessionOverlapPair(id(3), id(4)),
            ]
        )
        XCTAssertEqual(result.overlappingSessionIDs, [id(1), id(2), id(3), id(4)])
        XCTAssertTrue(result.contains(sessionID: id(4)))
    }

    func testCandidateLookupExcludesEditedSessionAndDeduplicatesStableIDs() {
        let duplicate = interval(3, start: 300, end: 500)
        let intervals = [
            interval(2, start: 200, end: 400),
            interval(1, start: 100, end: 300),
            duplicate,
            duplicate,
        ]

        let overlappingIDs = detector.overlappingSessionIDs(
            startAt: Date(timeIntervalSince1970: 250),
            endAt: Date(timeIntervalSince1970: 350),
            in: intervals,
            activeEndAt: now,
            excludingSessionID: id(2)
        )

        XCTAssertEqual(overlappingIDs, [id(1), id(3)])
    }

    func testEmptyReversedNonfiniteAndSelfIntervalsAreNotOverlaps() {
        let valid = interval(1, start: 100, end: 200)
        let empty = interval(2, start: 150, end: 150)
        let reversed = interval(3, start: 175, end: 125)
        let nonfinite = SessionInterval(
            sessionID: id(4),
            startAt: Date(timeIntervalSinceReferenceDate: .nan),
            endAt: Date(timeIntervalSince1970: 180)
        )

        XCTAssertFalse(detector.overlaps(valid, valid, activeEndAt: now))
        XCTAssertFalse(detector.overlaps(valid, empty, activeEndAt: now))
        XCTAssertFalse(detector.overlaps(valid, reversed, activeEndAt: now))
        XCTAssertFalse(detector.overlaps(valid, nonfinite, activeEndAt: now))
        XCTAssertEqual(
            detector.detect(in: [valid, empty, reversed, nonfinite], activeEndAt: now),
            SessionOverlapResult(pairs: [], overlappingSessionIDs: [])
        )
    }

    private func interval(_ identifier: Int, start: TimeInterval, end: TimeInterval?)
        -> SessionInterval
    {
        SessionInterval(
            sessionID: id(identifier),
            startAt: Date(timeIntervalSince1970: start),
            endAt: end.map(Date.init(timeIntervalSince1970:))
        )
    }

    private func id(_ value: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!
    }
}
