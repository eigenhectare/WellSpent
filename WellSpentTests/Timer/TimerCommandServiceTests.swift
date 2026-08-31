import Foundation
import SwiftData
import XCTest

@testable import WellSpent

@MainActor
final class TimerCommandServiceTests: XCTestCase {
    func testInitialStartPersistsOneAuthoritativeActiveSessionWithExactInjectedValues() throws {
        let workspaceID = UUID(uuidString: "D01A8E7E-7B9F-4469-AC3C-D4EDFB38AD46")!
        let fixture = try TimerServiceFixture()
        let project = ProjectRecord(workspaceID: workspaceID, name: "Client")
        fixture.context.insert(project)
        try fixture.context.save()

        let result = try fixture.commands.start(projectID: project.id)
        let storedSessions = try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>())

        XCTAssertEqual(result.disposition, .started)
        XCTAssertEqual(result.session.id, DependencyFixtures.fixedUUID)
        XCTAssertEqual(result.session.workspaceID, workspaceID)
        XCTAssertEqual(result.session.projectID, project.id)
        XCTAssertEqual(result.session.source, .timer)
        XCTAssertEqual(result.session.startAt, DependencyFixtures.fixedNow)
        XCTAssertNil(result.session.endAt)
        XCTAssertEqual(result.session.startTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.createdAt, DependencyFixtures.fixedNow)
        XCTAssertEqual(result.session.updatedAt, DependencyFixtures.fixedNow)
        XCTAssertEqual(storedSessions.count, 1)
        XCTAssertEqual(storedSessions.first?.id, result.session.id)
    }

    func testRepeatedStartForSameProjectReturnsPersistedSessionWithoutNewInputsOrWrite() throws {
        let calls = ProviderCallCounter()
        let dependencies = countingDependencies(calls: calls)
        let fixture = try TimerServiceFixture(dependencies: dependencies)
        let project = ProjectRecord(name: "Client")
        fixture.context.insert(project)
        try fixture.context.save()

        let first = try fixture.commands.start(projectID: project.id)
        let reopenedContext = ModelContext(fixture.container)
        let reopenedCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: reopenedContext),
            dependencies: dependencies
        )
        let second = try reopenedCommands.start(projectID: project.id)

        XCTAssertEqual(first.disposition, .started)
        XCTAssertEqual(second.disposition, .alreadyActive)
        XCTAssertEqual(second.session, first.session)
        XCTAssertEqual(try reopenedContext.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
        XCTAssertEqual(calls.nowCount, 1)
        XCTAssertEqual(calls.timeZoneCount, 1)
        XCTAssertEqual(calls.uuidCount, 1)
    }

    func testStartForDifferentProjectRequiresFutureSwitchWithoutCreatingSession() throws {
        let fixture = try TimerServiceFixture()
        let activeProject = ProjectRecord(name: "Active")
        let requestedProject = ProjectRecord(name: "Requested")
        let activeSession = makeActiveSession(projectID: activeProject.id)
        fixture.context.insert(activeProject)
        fixture.context.insert(requestedProject)
        fixture.context.insert(activeSession)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.start(projectID: requestedProject.id)) { error in
            XCTAssertEqual(
                error as? TimerCommandError,
                .activeSessionRequiresSwitch(
                    sessionID: activeSession.id,
                    projectID: activeProject.id
                )
            )
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
    }

    func testMalformedMultipleActiveSessionsAreSurfacedWithoutCreatingAnother() throws {
        let fixture = try TimerServiceFixture()
        let requestedProject = ProjectRecord(name: "Requested")
        let first = makeActiveSession(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            projectID: requestedProject.id,
            startAt: Date(timeIntervalSince1970: 100)
        )
        let second = makeActiveSession(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            projectID: requestedProject.id,
            startAt: Date(timeIntervalSince1970: 200)
        )
        fixture.context.insert(requestedProject)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.start(projectID: requestedProject.id)) { error in
            XCTAssertEqual(
                error as? TimerCommandError,
                .activeSessionReviewRequired(
                    activeSessionID: second.id,
                    conflictingSessionIDs: [first.id]
                )
            )
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 2)
    }

    func testArchivedAndMissingProjectsCannotStartTimers() throws {
        let fixture = try TimerServiceFixture()
        let archivedProject = ProjectRecord(name: "Archived", status: .archived)
        fixture.context.insert(archivedProject)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.start(projectID: archivedProject.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, .projectArchived(archivedProject.id))
        }

        let missingID = UUID(uuidString: "1F6BF4E2-9F0F-4B18-9758-E50B64B2780F")!
        XCTAssertThrowsError(try fixture.commands.start(projectID: missingID)) { error in
            XCTAssertEqual(error as? TimerCommandError, .projectNotFound(missingID))
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
    }

    func testPersistenceFailureRollsBackAndNeverReturnsAnActiveSession() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        context.insert(project)
        try context.save()
        let baseRepository = SwiftDataTimerRepository(context: context)
        let repository = SaveFailingTimerRepository(base: baseRepository)
        let commands = TimerCommandService(
            repository: repository,
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertThrowsError(try commands.start(projectID: project.id)) { error in
            XCTAssertEqual(error as? InjectedPersistenceFailure, .save)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
    }
}

@MainActor
private struct TimerServiceFixture {
    let container: ModelContainer
    let context: ModelContext
    let repository: SwiftDataTimerRepository
    let commands: TimerCommandService

    init(dependencies: WellSpentDependencies = DependencyFixtures.fixed()) throws {
        container = try WellSpentPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        repository = SwiftDataTimerRepository(context: context)
        commands = TimerCommandService(repository: repository, dependencies: dependencies)
    }
}

@MainActor
private final class SaveFailingTimerRepository: TimerRepository {
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
        throw InjectedPersistenceFailure.save
    }

    func rollback() {
        base.rollback()
    }
}

private enum InjectedPersistenceFailure: Error, Equatable {
    case save
}

private final class ProviderCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (now: 0, timeZone: 0, uuid: 0)

    var nowCount: Int {
        lock.withLock { counts.now }
    }

    var timeZoneCount: Int {
        lock.withLock { counts.timeZone }
    }

    var uuidCount: Int {
        lock.withLock { counts.uuid }
    }

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

private func countingDependencies(calls: ProviderCallCounter) -> WellSpentDependencies {
    WellSpentDependencies(
        nowProvider: NowProvider { calls.now() },
        localeProvider: LocaleProvider { DependencyFixtures.fixedLocale },
        timeZoneProvider: TimeZoneProvider { calls.timeZone() },
        calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
        uuidProvider: UUIDProvider { calls.uuid() }
    )
}

private func makeActiveSession(
    id: UUID = UUID(uuidString: "8B626379-A9D4-4FCB-B464-C0DB7FA53AD0")!,
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
