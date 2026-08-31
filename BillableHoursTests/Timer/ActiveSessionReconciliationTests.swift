import Foundation
import SwiftData
import XCTest

@testable import BillableHours

@MainActor
final class ActiveSessionReconciliationTests: XCTestCase {
    func testZeroActiveFixtureReopensAsNoActiveSessionWithoutDeletingHistory() throws {
        let fixture = try ReconciliationStoreFixture()
        defer { fixture.remove() }
        let completedID = UUID(uuidString: "10101010-1010-4010-8010-101010101010")!

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(
                makeReconciliationSession(
                    id: completedID,
                    startAt: Date(timeIntervalSince1970: 100),
                    endAt: Date(timeIntervalSince1970: 200)
                )
            )
            try context.save()
        }

        let reopenedContainer = try fixture.makeContainer()
        let result = try BillableHoursStartup.reconcileActiveSession(
            in: reopenedContainer,
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertEqual(result, .noActiveSession)
        let reopenedContext = ModelContext(reopenedContainer)
        let records = try reopenedContext.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(records.map(\.id), [completedID])
        XCTAssertEqual(records.first?.endAt, Date(timeIntervalSince1970: 200))
    }

    func testOneActiveFixtureReconstructsExactPersistedStateAcrossContainerRecreation() throws {
        let fixture = try ReconciliationStoreFixture()
        defer { fixture.remove() }
        let sessionID = UUID(uuidString: "20202020-2020-4020-8020-202020202020")!
        let projectID = UUID(uuidString: "30303030-3030-4030-8030-303030303030")!
        let startAt = Date(timeIntervalSince1970: 1_900_000_000.125)
        let calls = ReconciliationDependencyCalls()

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(
                makeReconciliationSession(
                    id: sessionID,
                    projectID: projectID,
                    startAt: startAt
                )
            )
            try context.save()
        }

        let reopenedContainer = try fixture.makeContainer()
        let result = try BillableHoursStartup.reconcileActiveSession(
            in: reopenedContainer,
            dependencies: reconciliationDependencies(calls: calls)
        )

        guard case .active(let session) = result else {
            return XCTFail("Expected one reconstructed active session")
        }
        XCTAssertEqual(session.id, sessionID)
        XCTAssertEqual(session.projectID, projectID)
        XCTAssertEqual(session.startAt, startAt)
        XCTAssertNil(session.endAt)
        XCTAssertEqual(calls.nowCount, 0)
        XCTAssertEqual(calls.timeZoneCount, 0)
        XCTAssertEqual(calls.uuidCount, 0)
    }

    func testMultipleActiveFixtureSelectsNewestAndSurfacesEveryOlderRecordUnchanged() throws {
        let fixture = try ReconciliationStoreFixture()
        defer { fixture.remove() }
        let oldestID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let middleID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let newestID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(
                makeReconciliationSession(
                    id: newestID,
                    startAt: Date(timeIntervalSince1970: 300)
                )
            )
            context.insert(
                makeReconciliationSession(
                    id: oldestID,
                    startAt: Date(timeIntervalSince1970: 100)
                )
            )
            context.insert(
                makeReconciliationSession(
                    id: middleID,
                    startAt: Date(timeIntervalSince1970: 200)
                )
            )
            try context.save()
        }

        let reopenedContainer = try fixture.makeContainer()
        let result = try BillableHoursStartup.reconcileActiveSession(
            in: reopenedContainer,
            dependencies: DependencyFixtures.fixed()
        )

        guard case .reviewRequired(let active, let conflicts) = result else {
            return XCTFail("Expected malformed active state to require review")
        }
        XCTAssertEqual(active.id, newestID)
        XCTAssertEqual(conflicts.map(\.id), [oldestID, middleID])

        let verificationContext = ModelContext(reopenedContainer)
        let stored = try verificationContext.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(stored.count, 3)
        XCTAssertTrue(stored.allSatisfy { $0.endAt == nil })
    }

    func testEqualStartTimesUseUUIDTieBreakerAndRemainStableAcrossRepeatedRestarts() throws {
        let fixture = try ReconciliationStoreFixture()
        defer { fixture.remove() }
        let lowerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let higherID = UUID(uuidString: "FFFFFFFF-FFFF-4FFF-BFFF-FFFFFFFFFFFF")!
        let sharedStart = Date(timeIntervalSince1970: 500)

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(makeReconciliationSession(id: higherID, startAt: sharedStart))
            context.insert(makeReconciliationSession(id: lowerID, startAt: sharedStart))
            try context.save()
        }

        let firstResult: ActiveSessionReconciliationResult
        do {
            let container = try fixture.makeContainer()
            firstResult = try BillableHoursStartup.reconcileActiveSession(
                in: container,
                dependencies: DependencyFixtures.fixed()
            )
        }

        let secondContainer = try fixture.makeContainer()
        let secondResult = try BillableHoursStartup.reconcileActiveSession(
            in: secondContainer,
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertEqual(firstResult, secondResult)
        guard case .reviewRequired(let active, let conflicts) = secondResult else {
            return XCTFail("Expected a stable review-required result")
        }
        XCTAssertEqual(active.id, higherID)
        XCTAssertEqual(conflicts.map(\.id), [lowerID])
    }

    func testEveryMutatingTimerCommandBlocksReviewRequiredStateWithoutUsingInputs() throws {
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let firstProject = ProjectRecord(name: "First")
        let secondProject = ProjectRecord(name: "Second")
        let older = makeReconciliationSession(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            projectID: firstProject.id,
            startAt: Date(timeIntervalSince1970: 100)
        )
        let newer = makeReconciliationSession(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            projectID: secondProject.id,
            startAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(firstProject)
        context.insert(secondProject)
        context.insert(older)
        context.insert(newer)
        try context.save()
        let calls = ReconciliationDependencyCalls()
        let commands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: context),
            dependencies: reconciliationDependencies(calls: calls)
        )
        let expected = TimerCommandError.activeSessionReviewRequired(
            activeSessionID: newer.id,
            conflictingSessionIDs: [older.id]
        )

        XCTAssertThrowsError(try commands.start(projectID: firstProject.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, expected)
        }
        XCTAssertThrowsError(try commands.switchTimer(to: firstProject.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, expected)
        }
        XCTAssertThrowsError(try commands.stopActive()) { error in
            XCTAssertEqual(error as? TimerCommandError, expected)
        }
        XCTAssertThrowsError(try commands.stop(sessionID: newer.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, expected)
        }
        XCTAssertEqual(calls.nowCount, 0)
        XCTAssertEqual(calls.timeZoneCount, 0)
        XCTAssertEqual(calls.uuidCount, 0)
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TimeSessionRecord>()).filter { $0.endAt == nil }.count,
            2
        )
    }

    func testPersistedManualRepairAllowsTheNextStartupToRecoverOneActiveSession() throws {
        let fixture = try ReconciliationStoreFixture()
        defer { fixture.remove() }
        let olderID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let newerID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let boundary = Date(timeIntervalSince1970: 200)

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(
                makeReconciliationSession(
                    id: olderID,
                    startAt: Date(timeIntervalSince1970: 100)
                )
            )
            context.insert(makeReconciliationSession(id: newerID, startAt: boundary))
            try context.save()
        }

        do {
            let container = try fixture.makeContainer()
            let result = try BillableHoursStartup.reconcileActiveSession(
                in: container,
                dependencies: DependencyFixtures.fixed()
            )
            guard case .reviewRequired = result else {
                return XCTFail("Expected review before repair")
            }

            let context = ModelContext(container)
            let older = try XCTUnwrap(
                context.fetch(FetchDescriptor<TimeSessionRecord>()).first { $0.id == olderID }
            )
            older.endAt = boundary
            older.endTimeZoneID = "UTC"
            older.updatedAt = boundary
            try context.save()
        }

        let repairedContainer = try fixture.makeContainer()
        let repairedResult = try BillableHoursStartup.reconcileActiveSession(
            in: repairedContainer,
            dependencies: DependencyFixtures.fixed()
        )
        guard case .active(let active) = repairedResult else {
            return XCTFail("Expected one active session after repair")
        }
        XCTAssertEqual(active.id, newerID)

        let verificationContext = ModelContext(repairedContainer)
        let older = try XCTUnwrap(
            verificationContext.fetch(FetchDescriptor<TimeSessionRecord>()).first {
                $0.id == olderID
            }
        )
        XCTAssertEqual(older.endAt, boundary)
    }
}

private struct ReconciliationStoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BillableHoursReconciliationTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = directoryURL.appendingPathComponent("BillableHours.store")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func makeContainer() throws -> ModelContainer {
        try BillableHoursPersistence.makePersistentContainer(storeURL: storeURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private final class ReconciliationDependencyCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (now: 0, timeZone: 0, uuid: 0)

    var nowCount: Int { lock.withLock { counts.now } }
    var timeZoneCount: Int { lock.withLock { counts.timeZone } }
    var uuidCount: Int { lock.withLock { counts.uuid } }

    func now() -> Date {
        lock.withLock {
            counts.now += 1
            return DependencyFixtures.fixedNow
        }
    }

    func timeZone() -> TimeZone {
        lock.withLock {
            counts.timeZone += 1
            return DependencyFixtures.fixedTimeZone
        }
    }

    func uuid() -> UUID {
        lock.withLock {
            counts.uuid += 1
            return DependencyFixtures.fixedUUID
        }
    }
}

private func reconciliationDependencies(
    calls: ReconciliationDependencyCalls
) -> BillableHoursDependencies {
    BillableHoursDependencies(
        nowProvider: NowProvider { calls.now() },
        localeProvider: LocaleProvider { DependencyFixtures.fixedLocale },
        timeZoneProvider: TimeZoneProvider { calls.timeZone() },
        calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
        uuidProvider: UUIDProvider { calls.uuid() }
    )
}

private func makeReconciliationSession(
    id: UUID,
    projectID: UUID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-BAAA-AAAAAAAAAAAA")!,
    startAt: Date,
    endAt: Date? = nil
) -> TimeSessionRecord {
    TimeSessionRecord(
        id: id,
        projectID: projectID,
        source: .timer,
        startAt: startAt,
        endAt: endAt,
        startTimeZoneID: "UTC",
        endTimeZoneID: endAt == nil ? nil : "UTC",
        createdAt: startAt,
        updatedAt: endAt ?? startAt
    )
}
