import Foundation
import SwiftData
import XCTest

@testable import BillableHours

@MainActor
final class TimerStopCommandServiceTests: XCTestCase {
    func testStopPersistsTheExactInjectedEndBeforeReturningSuccess() throws {
        let endAt = Date(timeIntervalSince1970: 1_900_000_000.875)
        let fixture = try StopFixture(dependencies: DependencyFixtures.fixed(now: endAt))
        let project = ProjectRecord(name: "Client")
        let session = makeStopSession(
            projectID: project.id,
            startAt: endAt.addingTimeInterval(-3_600)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()

        let result = try fixture.commands.stop(sessionID: session.id)

        XCTAssertEqual(result.disposition, .stopped)
        XCTAssertEqual(result.session.endAt, endAt)
        XCTAssertEqual(result.session.endTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.updatedAt, endAt)

        let reopenedContext = ModelContext(fixture.container)
        let persisted = try XCTUnwrap(
            reopenedContext.fetch(FetchDescriptor<TimeSessionRecord>()).first { $0.id == session.id }
        )
        XCTAssertEqual(persisted.endAt, endAt)
        XCTAssertEqual(persisted.endTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
    }

    func testIntentCapturedBoundaryIsPersistedWithoutSamplingAppClock() throws {
        let capturedEnd = Date(timeIntervalSince1970: 1_900_000_100.875)
        let calls = StopProviderCallCounter()
        let fixture = try StopFixture(
            dependencies: stopCountingDependencies(
                calls: calls,
                now: capturedEnd.addingTimeInterval(999)
            )
        )
        let project = ProjectRecord(name: "Client")
        let session = makeStopSession(
            projectID: project.id,
            startAt: capturedEnd.addingTimeInterval(-60)
        )
        fixture.context.insert(project)
        fixture.context.insert(session)
        try fixture.context.save()

        let result = try fixture.commands.stop(
            sessionID: session.id,
            capturedAt: capturedEnd,
            endTimeZoneID: "America/New_York"
        )

        XCTAssertEqual(result.session.endAt, capturedEnd)
        XCTAssertEqual(result.session.endTimeZoneID, "America/New_York")
        XCTAssertEqual(calls.nowCount, 0)
        XCTAssertEqual(calls.timeZoneCount, 0)
    }

    func testRepeatedAppAndAppIntentStopsReturnTheFirstPersistedEnd() throws {
        let firstEnd = Date(timeIntervalSince1970: 1_900_000_000)
        let laterEnd = firstEnd.addingTimeInterval(60)
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let appContext = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        let session = makeStopSession(
            projectID: project.id,
            startAt: firstEnd.addingTimeInterval(-60)
        )
        appContext.insert(project)
        appContext.insert(session)
        try appContext.save()

        let appCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: appContext),
            dependencies: DependencyFixtures.fixed(now: firstEnd)
        )
        let intentCalls = StopProviderCallCounter()
        let intentContext = ModelContext(container)
        let intentCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: intentContext),
            dependencies: stopCountingDependencies(
                calls: intentCalls,
                now: laterEnd
            )
        )

        let appResult = try appCommands.stop(sessionID: session.id)
        let intentRetryResult = try intentCommands.stop(sessionID: session.id)

        XCTAssertEqual(appResult.disposition, .stopped)
        XCTAssertEqual(intentRetryResult.disposition, .alreadyStopped)
        XCTAssertEqual(appResult.session.endAt, firstEnd)
        XCTAssertEqual(intentRetryResult.session.endAt, firstEnd)
        XCTAssertEqual(intentCalls.nowCount, 0)
        XCTAssertEqual(intentCalls.timeZoneCount, 0)
    }

    func testConcurrentAppAndAppIntentRequestsSerializeAndFirstSuccessfulStopWins() async throws {
        let appEnd = Date(timeIntervalSince1970: 1_900_000_000)
        let intentEnd = appEnd.addingTimeInterval(0.001)
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let setupContext = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        let session = makeStopSession(
            projectID: project.id,
            startAt: appEnd.addingTimeInterval(-60)
        )
        setupContext.insert(project)
        setupContext.insert(session)
        try setupContext.save()

        let appCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: ModelContext(container)),
            dependencies: DependencyFixtures.fixed(now: appEnd)
        )
        let intentCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: ModelContext(container)),
            dependencies: DependencyFixtures.fixed(now: intentEnd)
        )

        let appTask = Task { @MainActor in
            try appCommands.stop(sessionID: session.id)
        }
        let intentTask = Task { @MainActor in
            try intentCommands.stop(sessionID: session.id)
        }
        let appResult = try await appTask.value
        let intentResult = try await intentTask.value

        XCTAssertEqual(appResult.session.endAt, intentResult.session.endAt)
        let winningEnd = try XCTUnwrap(appResult.session.endAt)
        XCTAssertTrue([appEnd, intentEnd].contains(winningEnd))
        XCTAssertEqual(
            Set([appResult.disposition, intentResult.disposition]),
            Set([.stopped, .alreadyStopped])
        )
    }

    func testSaveFailureKeepsTimerActiveAndLaterSuccessfulRetryWins() throws {
        let failedEnd = Date(timeIntervalSince1970: 1_900_000_000)
        let successfulEnd = failedEnd.addingTimeInterval(30)
        let container = try BillableHoursPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        let session = makeStopSession(
            projectID: project.id,
            startAt: failedEnd.addingTimeInterval(-60)
        )
        context.insert(project)
        context.insert(session)
        try context.save()
        let failingCommands = TimerCommandService(
            repository: StopSaveFailingRepository(
                base: SwiftDataTimerRepository(context: context)
            ),
            dependencies: DependencyFixtures.fixed(now: failedEnd)
        )

        XCTAssertThrowsError(try failingCommands.stop(sessionID: session.id)) { error in
            XCTAssertEqual(error as? StopInjectedFailure, .save)
        }

        let retryContext = ModelContext(container)
        let activeAfterFailure = try XCTUnwrap(
            retryContext.fetch(FetchDescriptor<TimeSessionRecord>()).first { $0.id == session.id }
        )
        XCTAssertNil(activeAfterFailure.endAt)
        XCTAssertNil(activeAfterFailure.endTimeZoneID)

        let retryCommands = TimerCommandService(
            repository: SwiftDataTimerRepository(context: retryContext),
            dependencies: DependencyFixtures.fixed(now: successfulEnd)
        )
        let retryResult = try retryCommands.stop(sessionID: session.id)
        XCTAssertEqual(retryResult.disposition, .stopped)
        XCTAssertEqual(retryResult.session.endAt, successfulEnd)
    }

    func testNoActiveSessionAndUnknownIdentityReturnExplicitErrors() throws {
        let fixture = try StopFixture()

        XCTAssertThrowsError(try fixture.commands.stopActive()) { error in
            XCTAssertEqual(error as? TimerCommandError, .noActiveTimedSession)
        }

        let unknownID = UUID(uuidString: "474D71B2-C735-4893-B681-9D5B7E13CF30")!
        XCTAssertThrowsError(try fixture.commands.stop(sessionID: unknownID)) { error in
            XCTAssertEqual(error as? TimerCommandError, .sessionNotFound(unknownID))
        }
    }

    func testCompletedRetryDoesNotRequireAnActiveSessionOrChangeTheFirstEnd() throws {
        let firstEnd = Date(timeIntervalSince1970: 1_900_000_000)
        let retryEnd = firstEnd.addingTimeInterval(300)
        let calls = StopProviderCallCounter()
        let fixture = try StopFixture(
            dependencies: stopCountingDependencies(calls: calls, now: retryEnd)
        )
        let project = ProjectRecord(name: "Client")
        let completed = makeStopSession(
            projectID: project.id,
            startAt: firstEnd.addingTimeInterval(-60),
            endAt: firstEnd
        )
        fixture.context.insert(project)
        fixture.context.insert(completed)
        try fixture.context.save()

        let result = try fixture.commands.stop(sessionID: completed.id)

        XCTAssertEqual(result.disposition, .alreadyStopped)
        XCTAssertEqual(result.session.endAt, firstEnd)
        XCTAssertEqual(calls.nowCount, 0)
        XCTAssertEqual(calls.timeZoneCount, 0)
        XCTAssertThrowsError(try fixture.commands.stopActive()) { error in
            XCTAssertEqual(error as? TimerCommandError, .noActiveTimedSession)
        }
    }

    func testStopRejectsNonIncreasingEndAndManualSessionIdentity() throws {
        let endAt = DependencyFixtures.fixedNow
        let fixture = try StopFixture()
        let project = ProjectRecord(name: "Client")
        let timed = makeStopSession(projectID: project.id, startAt: endAt)
        let manual = TimeSessionRecord(
            projectID: project.id,
            source: .manual,
            startAt: endAt.addingTimeInterval(-60),
            endAt: endAt,
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC"
        )
        fixture.context.insert(project)
        fixture.context.insert(timed)
        fixture.context.insert(manual)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.stop(sessionID: timed.id)) { error in
            XCTAssertEqual(
                error as? TimerCommandError,
                .nonIncreasingBoundary(
                    sessionID: timed.id,
                    startAt: endAt,
                    requestedEndAt: endAt
                )
            )
        }
        XCTAssertThrowsError(try fixture.commands.stop(sessionID: manual.id)) { error in
            XCTAssertEqual(error as? TimerCommandError, .sessionIsNotTimed(manual.id))
        }
        XCTAssertNil(timed.endAt)
    }
}

@MainActor
private struct StopFixture {
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
private final class StopSaveFailingRepository: TimerRepository {
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
        throw StopInjectedFailure.save
    }

    func rollback() {
        base.rollback()
    }
}

private enum StopInjectedFailure: Error, Equatable {
    case save
}

private final class StopProviderCallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var counts = (now: 0, timeZone: 0)

    var nowCount: Int { lock.withLock { counts.now } }
    var timeZoneCount: Int { lock.withLock { counts.timeZone } }

    func now(_ value: Date) -> Date {
        lock.withLock {
            counts.now += 1
            return value
        }
    }

    func timeZone() -> TimeZone {
        lock.withLock {
            counts.timeZone += 1
            return DependencyFixtures.fixedTimeZone
        }
    }
}

private func stopCountingDependencies(
    calls: StopProviderCallCounter,
    now: Date
) -> BillableHoursDependencies {
    BillableHoursDependencies(
        nowProvider: NowProvider { calls.now(now) },
        localeProvider: LocaleProvider { DependencyFixtures.fixedLocale },
        timeZoneProvider: TimeZoneProvider { calls.timeZone() },
        calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
        uuidProvider: UUIDProvider { DependencyFixtures.fixedUUID }
    )
}

private func makeStopSession(
    id: UUID = UUID(uuidString: "6D3775BD-A8A8-4698-B651-D1F9B465EC76")!,
    projectID: UUID,
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
