import Foundation
import SwiftData
import XCTest

@testable import BillableHours

@MainActor
final class TimerSwitchCommandServiceTests: XCTestCase {
    func testSwitchUsesOneExactBoundaryForPreviousEndAndNewStart() throws {
        let boundary = Date(timeIntervalSince1970: 1_800_000_000.625)
        let newSessionID = UUID(uuidString: "DDB430A8-8A9E-4F68-8C3B-7913B8FE58FC")!
        let fixture = try SwitchFixture(
            dependencies: DependencyFixtures.fixed(now: boundary, uuid: newSessionID)
        )
        let previousProject = ProjectRecord(name: "Previous")
        let nextProject = ProjectRecord(name: "Next")
        let previousSession = makeSwitchSession(
            projectID: previousProject.id,
            startAt: boundary.addingTimeInterval(-60)
        )
        fixture.context.insert(previousProject)
        fixture.context.insert(nextProject)
        fixture.context.insert(previousSession)
        try fixture.context.save()

        let result = try fixture.commands.switchTimer(to: nextProject.id)

        guard case .switched(let completed, let active) = result else {
            return XCTFail("Expected a completed and active session pair")
        }
        XCTAssertEqual(completed.id, previousSession.id)
        XCTAssertEqual(completed.endAt, boundary)
        XCTAssertEqual(completed.endTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(completed.updatedAt, boundary)
        XCTAssertEqual(active.id, newSessionID)
        XCTAssertEqual(active.projectID, nextProject.id)
        XCTAssertEqual(active.startAt, boundary)
        XCTAssertEqual(active.createdAt, boundary)
        XCTAssertEqual(active.updatedAt, boundary)
        XCTAssertEqual(active.startTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(completed.endAt, active.startAt)

        let stored = try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(stored.count, 2)
        XCTAssertEqual(stored.filter { $0.source == .timer && $0.endAt == nil }.map(\.id), [newSessionID])
    }

    func testRapidSwitchesMaintainExactAdjacentBoundariesAndOneActiveSession() throws {
        let firstBoundary = Date(timeIntervalSince1970: 1_800_000_000.001)
        let secondBoundary = Date(timeIntervalSince1970: 1_800_000_000.002)
        let secondSessionID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let thirdSessionID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let fixture = try SwitchFixture(
            dependencies: DependencyFixtures.fixed(now: firstBoundary, uuid: secondSessionID)
        )
        let firstProject = ProjectRecord(name: "First")
        let secondProject = ProjectRecord(name: "Second")
        let thirdProject = ProjectRecord(name: "Third")
        let firstSession = makeSwitchSession(
            projectID: firstProject.id,
            startAt: firstBoundary.addingTimeInterval(-0.001)
        )
        fixture.context.insert(firstProject)
        fixture.context.insert(secondProject)
        fixture.context.insert(thirdProject)
        fixture.context.insert(firstSession)
        try fixture.context.save()

        _ = try fixture.commands.switchTimer(to: secondProject.id)
        let secondCommands = TimerCommandService(
            repository: fixture.repository,
            dependencies: DependencyFixtures.fixed(now: secondBoundary, uuid: thirdSessionID)
        )
        _ = try secondCommands.switchTimer(to: thirdProject.id)

        let stored = try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>())
        let first = try XCTUnwrap(stored.first { $0.id == firstSession.id })
        let second = try XCTUnwrap(stored.first { $0.id == secondSessionID })
        let third = try XCTUnwrap(stored.first { $0.id == thirdSessionID })
        XCTAssertEqual(first.endAt, firstBoundary)
        XCTAssertEqual(second.startAt, firstBoundary)
        XCTAssertEqual(second.endAt, secondBoundary)
        XCTAssertEqual(third.startAt, secondBoundary)
        XCTAssertNil(third.endAt)
        XCTAssertEqual(stored.filter { $0.source == .timer && $0.endAt == nil }.map(\.id), [thirdSessionID])
    }

    func testSameProjectSwitchReturnsExistingSessionWithoutMutationOrDependencyInputs() throws {
        let calls = SwitchProviderCallCounter()
        let fixture = try SwitchFixture(dependencies: switchCountingDependencies(calls: calls))
        let project = ProjectRecord(name: "Already active")
        let session = makeSwitchSession(projectID: project.id)
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()
        let originalUpdatedAt = session.updatedAt

        let result = try fixture.commands.switchTimer(to: project.id)

        XCTAssertEqual(result, .alreadyActive(TimeSessionSnapshot(record: session)))
        XCTAssertNil(session.endAt)
        XCTAssertEqual(session.updatedAt, originalUpdatedAt)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
        XCTAssertEqual(calls.nowCount, 0)
        XCTAssertEqual(calls.timeZoneCount, 0)
        XCTAssertEqual(calls.uuidCount, 0)
    }

    func testSwitchSaveFailureRollsBackOldEndAndNewSessionTogether() throws {
        let boundary = Date(timeIntervalSince1970: 1_800_000_000)
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let previousProject = ProjectRecord(name: "Previous")
        let nextProject = ProjectRecord(name: "Next")
        let previousSession = makeSwitchSession(
            projectID: previousProject.id,
            startAt: boundary.addingTimeInterval(-60)
        )
        context.insert(previousProject)
        context.insert(nextProject)
        context.insert(previousSession)
        try context.save()
        let baseRepository = SwiftDataTimerRepository(context: context)
        let commands = TimerCommandService(
            repository: SwitchSaveFailingRepository(base: baseRepository),
            dependencies: DependencyFixtures.fixed(now: boundary)
        )

        XCTAssertThrowsError(try commands.switchTimer(to: nextProject.id)) { error in
            XCTAssertEqual(error as? SwitchInjectedFailure, .save)
        }

        let reopenedContext = ModelContext(container)
        let stored = try reopenedContext.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.id, previousSession.id)
        XCTAssertNil(stored.first?.endAt)
        XCTAssertNil(stored.first?.endTimeZoneID)
    }

    func testSwitchRejectsMissingActiveSessionAndNonIncreasingBoundary() throws {
        let fixture = try SwitchFixture()
        let project = ProjectRecord(name: "Target")
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.switchTimer(to: project.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, .noActiveTimedSession)
        }

        let startAt = DependencyFixtures.fixedNow
        let otherProject = ProjectRecord(name: "Other")
        let session = makeSwitchSession(projectID: otherProject.id, startAt: startAt)
        fixture.context.insert(otherProject)
        fixture.context.insert(session)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.switchTimer(to: project.id)) { error in
            XCTAssertEqual(
                error as? TimerCommandError,
                .nonIncreasingBoundary(
                    sessionID: session.id,
                    startAt: startAt,
                    requestedEndAt: startAt
                )
            )
        }
        XCTAssertNil(session.endAt)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
    }
}

@MainActor
private struct SwitchFixture {
    let container: ModelContainer
    let context: ModelContext
    let repository: SwiftDataTimerRepository
    let commands: TimerCommandService

    init(dependencies: BillableHoursDependencies = DependencyFixtures.fixed()) throws {
        container = try BillableHoursPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        repository = SwiftDataTimerRepository(context: context)
        commands = TimerCommandService(repository: repository, dependencies: dependencies)
    }
}

@MainActor
private final class SwitchSaveFailingRepository: TimerRepository {
    private let base: SwiftDataTimerRepository

    init(base: SwiftDataTimerRepository) {
        self.base = base
    }

    func fetchProject(id: UUID) throws -> ProjectRecord? {
        try base.fetchProject(id: id)
    }

    func fetchSession(id: UUID) throws -> TimeSessionRecord? {
        try base.fetchSession(id: id)
    }

    func fetchActiveTimedSessions() throws -> [TimeSessionRecord] {
        try base.fetchActiveTimedSessions()
    }

    func insert(_ session: TimeSessionRecord) {
        base.insert(session)
    }

    func save() throws {
        throw SwitchInjectedFailure.save
    }

    func rollback() {
        base.rollback()
    }
}

private enum SwitchInjectedFailure: Error, Equatable {
    case save
}

private final class SwitchProviderCallCounter: @unchecked Sendable {
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

private func switchCountingDependencies(calls: SwitchProviderCallCounter) -> BillableHoursDependencies {
    BillableHoursDependencies(
        nowProvider: NowProvider { calls.now() },
        localeProvider: LocaleProvider { DependencyFixtures.fixedLocale },
        timeZoneProvider: TimeZoneProvider { calls.timeZone() },
        calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
        uuidProvider: UUIDProvider { calls.uuid() }
    )
}

private func makeSwitchSession(
    id: UUID = UUID(uuidString: "A6AE14DF-A93A-4F15-9551-8B57074648BB")!,
    projectID: UUID,
    startAt: Date = Date(timeIntervalSince1970: 100)
) -> TimeSessionRecord {
    TimeSessionRecord(
        id: id,
        projectID: projectID,
        source: .timer,
        startAt: startAt,
        startTimeZoneID: "UTC",
        createdAt: startAt,
        updatedAt: startAt
    )
}
