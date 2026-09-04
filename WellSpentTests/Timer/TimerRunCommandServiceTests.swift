import Foundation
import SwiftData
import XCTest

@testable import WellSpent

@MainActor
final class TimerRunCommandServiceTests: XCTestCase {
    func testDSTFallbackUsesAbsoluteInstantsAndRetainsZoneAuditFields() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "DST")
        context.insert(project)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let formatter = ISO8601DateFormatter()
        let start = try XCTUnwrap(formatter.date(from: "2026-11-01T05:30:00Z"))
        let end = try XCTUnwrap(formatter.date(from: "2026-11-01T07:30:00Z"))
        let runID = UUID()
        _ = try commands(
            repository,
            at: start,
            zone: TimeZone(identifier: "America/New_York")!,
            uuids: [runID, UUID(), UUID()]
        ).start(projectID: project.id)

        let result = try commands(
            repository,
            at: end,
            zone: TimeZone(identifier: "America/New_York")!
        ).end(runID: runID)

        XCTAssertEqual(result.run.countedDuration(at: end), 7_200)
        XCTAssertEqual(result.run.startTimeZoneID, "America/New_York")
        XCTAssertEqual(result.run.endTimeZoneID, "America/New_York")
    }

    func testStartPauseResumeAndEndUseExactBoundariesAndCountOnlySegments() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        context.insert(project)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let runID = id("10101010-1010-4010-8010-101010101010")
        let firstSegmentID = id("11111111-1111-4111-8111-111111111111")
        let originID = id("12121212-1212-4212-8212-121212121212")
        let secondSegmentID = id("13131313-1313-4313-8313-131313131313")
        let startMutation = id("14141414-1414-4414-8414-141414141414")
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let pause = start.addingTimeInterval(4_500)
        let resume = pause.addingTimeInterval(900)
        let end = resume.addingTimeInterval(5_400)

        let started = try commands(
            repository,
            at: start,
            uuids: [runID, firstSegmentID, originID]
        ).start(
            projectID: project.id,
            durationGoalSeconds: 7_200,
            mutationID: startMutation
        )
        XCTAssertEqual(started.disposition, .started)
        XCTAssertEqual(started.run.id, runID)
        XCTAssertEqual(started.run.segments.map(\.id), [firstSegmentID])
        XCTAssertEqual(started.run.originDeviceID, originID)
        XCTAssertEqual(started.run.revision, 1)
        let duplicateStart = try commands(repository, at: pause).start(
            projectID: project.id,
            durationGoalSeconds: 7_200,
            mutationID: startMutation
        )
        XCTAssertEqual(duplicateStart.disposition, .duplicate)
        XCTAssertEqual(duplicateStart.run.id, runID)
        XCTAssertEqual(duplicateStart.run.revision, 1)

        let paused = try commands(repository, at: pause).pause(runID: runID)
        XCTAssertEqual(paused.disposition, .paused)
        XCTAssertEqual(paused.run.state, .paused)
        XCTAssertEqual(paused.run.countedDuration(at: pause), 4_500)
        XCTAssertEqual(paused.run.revision, 2)
        XCTAssertEqual(
            try commands(repository, at: resume).pause(runID: runID).disposition,
            .alreadyPaused
        )

        let resumed = try commands(
            repository,
            at: resume,
            zone: TimeZone(identifier: "America/Los_Angeles")!,
            uuids: [secondSegmentID]
        ).resume(runID: runID)
        XCTAssertEqual(resumed.disposition, .resumed)
        XCTAssertEqual(resumed.run.state, .running)
        XCTAssertEqual(resumed.run.segments.map(\.id), [firstSegmentID, secondSegmentID])
        XCTAssertEqual(resumed.run.countedDuration(at: resume), 4_500)
        XCTAssertEqual(resumed.run.pausedDuration(at: resume), 900)
        XCTAssertEqual(
            try commands(repository, at: end).resume(runID: runID).disposition,
            .alreadyRunning
        )

        let ended = try commands(
            repository,
            at: end,
            zone: TimeZone(identifier: "Asia/Tokyo")!
        ).end(runID: runID)
        XCTAssertEqual(ended.disposition, .ended)
        XCTAssertEqual(ended.run.state, .ended)
        XCTAssertEqual(ended.run.endAt, end)
        XCTAssertEqual(ended.run.countedDuration(at: end), 9_900)
        XCTAssertEqual(ended.run.pausedDuration(at: end), 900)
        XCTAssertEqual(ended.run.goalProgress(at: end), 1.375)
        XCTAssertEqual(ended.run.revision, 4)
        XCTAssertEqual(ended.run.segments[0].endTimeZoneID, "America/New_York")
        XCTAssertEqual(ended.run.segments[1].startTimeZoneID, "America/Los_Angeles")
        XCTAssertEqual(ended.run.segments[1].endTimeZoneID, "Asia/Tokyo")
        XCTAssertEqual(ended.run.endTimeZoneID, "Asia/Tokyo")
        XCTAssertEqual(
            try commands(repository, at: end.addingTimeInterval(10)).end(runID: runID).disposition,
            .alreadyEnded
        )
        XCTAssertEqual(
            try context.fetch(FetchDescriptor<TimeSessionRecord>()).compactMap(\.duration)
                .reduce(0, +),
            9_900
        )
    }

    func testSwitchFromPausedEndsOldRunAndStartsNewRunAtOneBoundary() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let firstProject = ProjectRecord(name: "First")
        let secondProject = ProjectRecord(name: "Second")
        context.insert(firstProject)
        context.insert(secondProject)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let start = Date(timeIntervalSince1970: 2_000)
        let pause = Date(timeIntervalSince1970: 3_000)
        let boundary = Date(timeIntervalSince1970: 3_600.25)
        let firstRunID = id("21212121-2121-4121-8121-212121212121")
        _ = try commands(
            repository,
            at: start,
            uuids: [
                firstRunID,
                id("22222222-2222-4222-8222-222222222222"),
                id("23232323-2323-4323-8323-232323232323"),
            ]
        ).start(projectID: firstProject.id)
        _ = try commands(repository, at: pause).pause(runID: firstRunID)

        let secondRunID = id("24242424-2424-4424-8424-242424242424")
        let result = try commands(
            repository,
            at: boundary,
            uuids: [secondRunID, id("25252525-2525-4525-8525-252525252525")]
        ).switchTimer(to: secondProject.id)

        guard case .switched(let completed, let active) = result else {
            return XCTFail("Expected switch")
        }
        XCTAssertEqual(completed.id, firstRunID)
        XCTAssertEqual(completed.endAt, boundary)
        XCTAssertEqual(completed.countedDuration(at: boundary), 1_000)
        XCTAssertEqual(active.id, secondRunID)
        XCTAssertEqual(active.startAt, boundary)
        XCTAssertEqual(active.currentSegment?.startAt, boundary)
        XCTAssertEqual(active.originDeviceID, completed.originDeviceID)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TimerRunRecord>()).count, 2)
    }

    func testDuplicateSwitchMutationReturnsTheSameTwoRunsWithoutNewRows() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let firstProject = ProjectRecord(name: "First")
        let secondProject = ProjectRecord(name: "Second")
        context.insert(firstProject)
        context.insert(secondProject)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let firstRunID = id("26262626-2626-4626-8626-262626262626")
        let secondRunID = id("27272727-2727-4727-8727-272727272727")
        let switchMutation = id("28282828-2828-4828-8828-282828282828")
        _ = try commands(
            repository,
            at: Date(timeIntervalSince1970: 100),
            uuids: [firstRunID, UUID(), UUID()]
        ).start(projectID: firstProject.id)

        let service = commands(
            repository,
            at: Date(timeIntervalSince1970: 200),
            uuids: [secondRunID, UUID()]
        )
        _ = try service.switchTimer(to: secondProject.id, mutationID: switchMutation)
        let duplicate = try service.switchTimer(
            to: secondProject.id,
            capturedAt: Date(timeIntervalSince1970: 999),
            mutationID: switchMutation
        )

        guard case .duplicate(let completed, let active) = duplicate else {
            return XCTFail("Expected the stored switch result")
        }
        XCTAssertEqual(completed.id, firstRunID)
        XCTAssertEqual(completed.endAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(active.id, secondRunID)
        XCTAssertEqual(active.startAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 2)
    }

    func testSaveFailureRollsBackRunSegmentAndOriginTogether() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        context.insert(project)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        repository.setBeforeSaveForTesting { throw TimerRunInjectedFailure.save }

        XCTAssertThrowsError(
            try commands(
                repository,
                at: Date(timeIntervalSince1970: 100),
                uuids: [UUID(), UUID(), UUID()]
            ).start(projectID: project.id)
        ) { error in
            XCTAssertEqual(error as? TimerRunInjectedFailure, .save)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerOriginRecord>()), 0)
    }

    func testCompoundSwitchSaveFailureRollsBackOldAndNewRunsTogether() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let firstProject = ProjectRecord(name: "First")
        let secondProject = ProjectRecord(name: "Second")
        context.insert(firstProject)
        context.insert(secondProject)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let firstRunID = UUID()
        _ = try commands(
            repository,
            at: Date(timeIntervalSince1970: 100),
            uuids: [firstRunID, UUID(), UUID()]
        ).start(projectID: firstProject.id)
        repository.setBeforeSaveForTesting { throw TimerRunInjectedFailure.save }

        XCTAssertThrowsError(
            try commands(
                repository,
                at: Date(timeIntervalSince1970: 200),
                uuids: [UUID(), UUID()]
            ).switchTimer(to: secondProject.id)
        )

        let runs = try context.fetch(FetchDescriptor<TimerRunRecord>())
        let segments = try context.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(runs.first?.id, firstRunID)
        XCTAssertEqual(runs.first?.state, .running)
        XCTAssertNil(runs.first?.endAt)
        XCTAssertEqual(segments.count, 1)
        XCTAssertNil(segments.first?.endAt)
    }

    func testRestartRestoresPausedRunAndDuplicateMutationIsNoOp() throws {
        let fixture = try TimerRunPersistentFixture()
        defer { fixture.remove() }
        let runID = id("31313131-3131-4131-8131-313131313131")
        let pauseMutation = id("32323232-3232-4232-8232-323232323232")
        let projectID = UUID()
        let start = Date(timeIntervalSince1970: 10_000)
        let pause = start.addingTimeInterval(300)

        do {
            let container = try WellSpentPersistence.makePersistentContainer(
                storeURL: fixture.storeURL
            )
            let context = ModelContext(container)
            context.insert(ProjectRecord(id: projectID, name: "Restart"))
            try context.save()
            let repository = SwiftDataTimerRunRepository(context: context)
            _ = try commands(
                repository,
                at: start,
                uuids: [runID, UUID(), UUID()]
            ).start(projectID: projectID)
            _ = try commands(repository, at: pause).pause(
                runID: runID,
                mutationID: pauseMutation
            )
        }

        let reopened = try WellSpentPersistence.makePersistentContainer(storeURL: fixture.storeURL)
        let repository = SwiftDataTimerRunRepository(context: ModelContext(reopened))
        let service = commands(repository, at: pause.addingTimeInterval(60))
        guard case .paused(let run) = try service.reconcileActiveState() else {
            return XCTFail("Expected paused run")
        }
        XCTAssertEqual(run.id, runID)
        XCTAssertEqual(run.lastAppliedMutationID, pauseMutation)
        XCTAssertEqual(run.revision, 2)
        let duplicate = try service.pause(runID: runID, mutationID: pauseMutation)
        XCTAssertEqual(duplicate.disposition, .duplicate)
        XCTAssertEqual(duplicate.run.revision, 2)
        XCTAssertEqual(duplicate.run.segments.count, 1)
    }

    func testAnnotateProjectsNormalizedNoteAndTagsToEverySegmentAtomically() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        let tag = SessionTagRecord(name: "billable", normalizedName: "billable")
        context.insert(project)
        context.insert(tag)
        try context.save()
        let repository = SwiftDataTimerRunRepository(context: context)
        let runID = id("41414141-4141-4141-8141-414141414141")
        let start = Date(timeIntervalSince1970: 20_000)
        _ = try commands(
            repository,
            at: start,
            uuids: [runID, UUID(), UUID()]
        ).start(projectID: project.id)
        _ = try commands(repository, at: start.addingTimeInterval(60)).pause(runID: runID)
        _ = try commands(
            repository,
            at: start.addingTimeInterval(120),
            uuids: [UUID()]
        ).resume(runID: runID)
        _ = try commands(repository, at: start.addingTimeInterval(180)).end(runID: runID)

        let annotated = try commands(
            repository,
            at: start.addingTimeInterval(200),
            uuids: Array(repeating: UUID(), count: 8)
        ).annotate(runID: runID, note: "  Court filing  ", tagIDs: [tag.id])
        XCTAssertEqual(annotated.note, "Court filing")
        XCTAssertEqual(annotated.tags.map(\.tagID), [tag.id])
        XCTAssertTrue(annotated.segments.allSatisfy { $0.note == "Court filing" })
        XCTAssertTrue(annotated.segments.allSatisfy { $0.tags.map(\.tagID) == [tag.id] })
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<TimerRunTagAssignmentRecord>()),
            1
        )
        XCTAssertEqual(
            try context.fetchCount(FetchDescriptor<SessionTagAssignmentRecord>()),
            2
        )
    }

    func testMultipleNonEndedRunsArePreservedAndEveryMutationIsBlocked() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Conflict")
        context.insert(project)
        for index in 0..<2 {
            let runID = UUID()
            let start = Date(timeIntervalSince1970: 100 + Double(index))
            context.insert(
                TimerRunRecord(
                    id: runID,
                    projectID: project.id,
                    state: .running,
                    startAt: start,
                    startTimeZoneID: "UTC",
                    originDeviceID: UUID(),
                    revision: 1,
                    createdAt: start,
                    updatedAt: start,
                    updatedTimeZoneID: "UTC"
                )
            )
            context.insert(
                TimeSessionRecord(
                    projectID: project.id,
                    source: .timer,
                    timerRunID: runID,
                    startAt: start,
                    startTimeZoneID: "UTC"
                )
            )
        }
        try context.save()
        let service = commands(
            SwiftDataTimerRunRepository(context: context),
            at: Date(timeIntervalSince1970: 500)
        )

        guard
            case .reviewRequired(let runIDs, let segmentIDs, let reasons) =
                try service.reconcileActiveState()
        else { return XCTFail("Expected review") }
        XCTAssertEqual(runIDs.count, 2)
        XCTAssertEqual(segmentIDs.count, 2)
        XCTAssertTrue(reasons.contains(.multipleNonEndedRuns))
        XCTAssertThrowsError(try service.start(projectID: project.id))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimerRunRecord>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 2)
    }
}

private enum TimerRunInjectedFailure: Error, Equatable {
    case save
}

private final class UUIDSequence: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID]

    init(_ values: [UUID]) {
        self.values = values
    }

    func next() -> UUID {
        lock.withLock {
            precondition(!values.isEmpty, "UUID fixture exhausted")
            return values.removeFirst()
        }
    }
}

@MainActor
private func commands(
    _ repository: SwiftDataTimerRunRepository,
    at date: Date,
    zone: TimeZone = TimeZone(identifier: "America/New_York")!,
    uuids: [UUID] = []
) -> TimerRunCommandService {
    let sequence = UUIDSequence(uuids)
    return TimerRunCommandService(
        repository: repository,
        dependencies: WellSpentDependencies(
            nowProvider: NowProvider { date },
            localeProvider: LocaleProvider { Locale(identifier: "en_US") },
            timeZoneProvider: TimeZoneProvider { zone },
            calendarProvider: CalendarProvider { Calendar(identifier: .gregorian) },
            uuidProvider: UUIDProvider { sequence.next() }
        )
    )
}

private func id(_ value: String) -> UUID {
    UUID(uuidString: value)!
}

private struct TimerRunPersistentFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TimerRunCommandTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = directoryURL.appendingPathComponent("WellSpent.store")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}
