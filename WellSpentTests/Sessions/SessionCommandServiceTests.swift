import Foundation
import SwiftData
import XCTest

@testable import WellSpent

@MainActor
final class SessionCommandServiceTests: XCTestCase {
    func testCreateManualPersistsACompletedSessionWithExactInjectedMetadata() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let sessionID = UUID(uuidString: "10101010-1010-4010-8010-101010101010")!
        let workspaceID = UUID(uuidString: "20202020-2020-4020-8020-202020202020")!
        let fixture = try SessionServiceFixture(now: now, uuid: sessionID)
        let project = ProjectRecord(workspaceID: workspaceID, name: "Client")
        fixture.context.insert(project)
        try fixture.context.save()
        let startAt = now.addingTimeInterval(-3_600)
        let endAt = now.addingTimeInterval(-1_800)

        let result = try fixture.commands.createManual(
            projectID: project.id,
            startAt: startAt,
            endAt: endAt,
            note: "  Drafted agreement\n"
        )

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.session.id, sessionID)
        XCTAssertEqual(result.session.workspaceID, workspaceID)
        XCTAssertEqual(result.session.projectID, project.id)
        XCTAssertEqual(result.session.source, .manual)
        XCTAssertEqual(result.session.startAt, startAt)
        XCTAssertEqual(result.session.endAt, endAt)
        XCTAssertEqual(result.session.startTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.endTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.note, "Drafted agreement")
        XCTAssertEqual(result.session.createdAt, now)
        XCTAssertEqual(result.session.updatedAt, now)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>()).filter {
                $0.source == .timer && $0.endAt == nil
            }.count,
            0
        )
    }

    func testArchivedProjectsRemainAvailableForCreationAndCompletedReassignment() throws {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let fixture = try SessionServiceFixture(now: now)
        let activeProject = ProjectRecord(name: "Active")
        let archivedProject = ProjectRecord(name: "Archived", status: .archived)
        fixture.context.insert(activeProject)
        fixture.context.insert(archivedProject)
        let existing = makeSession(
            projectID: activeProject.id,
            source: .timer,
            startAt: now.addingTimeInterval(-4_000),
            endAt: now.addingTimeInterval(-3_000)
        )
        fixture.context.insert(existing)
        try fixture.context.save()

        let created = try fixture.commands.createManual(
            projectID: archivedProject.id,
            startAt: now.addingTimeInterval(-2_000),
            endAt: now.addingTimeInterval(-1_000)
        )
        let edited = try fixture.commands.editCompleted(
            sessionID: existing.id,
            projectID: archivedProject.id,
            startAt: existing.startAt,
            endAt: try XCTUnwrap(existing.endAt),
            note: "Historical correction"
        )

        XCTAssertEqual(created.session.projectID, archivedProject.id)
        XCTAssertEqual(edited.session.projectID, archivedProject.id)
        XCTAssertEqual(edited.session.source, .timer)
    }

    func testCompletedValidationRejectsInvalidOrderingAndFutureOrNonfiniteTimes() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let fixture = try SessionServiceFixture(now: now)
        let project = ProjectRecord(name: "Client")
        fixture.context.insert(project)
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.commands.createManual(
                projectID: project.id,
                startAt: now.addingTimeInterval(1),
                endAt: now.addingTimeInterval(2)
            )
        ) { error in
            XCTAssertEqual(error as? SessionCommandError, .startIsInFuture(now.addingTimeInterval(1)))
        }
        XCTAssertThrowsError(
            try fixture.commands.createManual(
                projectID: project.id,
                startAt: now.addingTimeInterval(-1),
                endAt: now.addingTimeInterval(1)
            )
        ) { error in
            XCTAssertEqual(error as? SessionCommandError, .endIsInFuture(now.addingTimeInterval(1)))
        }
        XCTAssertThrowsError(
            try fixture.commands.createManual(projectID: project.id, startAt: now, endAt: now)
        ) { error in
            XCTAssertEqual(
                error as? SessionCommandError,
                .endMustFollowStart(startAt: now, endAt: now)
            )
        }
        let invalidDate = Date(timeIntervalSinceReferenceDate: .nan)
        XCTAssertThrowsError(
            try fixture.commands.createManual(
                projectID: project.id,
                startAt: invalidDate,
                endAt: now
            )
        ) { error in
            XCTAssertEqual(error as? SessionCommandError, .invalidTimestamp)
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
    }

    func testOverlapPreviewAndCreateWarnWithoutBlockingOrCreatingAnotherActiveTimer() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let newSessionID = UUID(uuidString: "30303030-3030-4030-8030-303030303030")!
        let fixture = try SessionServiceFixture(now: now, uuid: newSessionID)
        let project = ProjectRecord(name: "Client")
        let completedID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let activeID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let completed = makeSession(
            id: completedID,
            projectID: project.id,
            source: .manual,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200)
        )
        let active = makeSession(
            id: activeID,
            projectID: project.id,
            source: .timer,
            startAt: Date(timeIntervalSince1970: 400)
        )
        fixture.context.insert(project)
        fixture.context.insert(completed)
        fixture.context.insert(active)
        try fixture.context.save()

        let warnings = try fixture.commands.validateCompletedSession(
            projectID: project.id,
            startAt: Date(timeIntervalSince1970: 150),
            endAt: Date(timeIntervalSince1970: 450)
        )
        XCTAssertEqual(warnings, [.overlaps(existingSessionIDs: [completedID, activeID])])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 2)

        let created = try fixture.commands.createManual(
            projectID: project.id,
            startAt: Date(timeIntervalSince1970: 150),
            endAt: Date(timeIntervalSince1970: 450)
        )
        XCTAssertEqual(created.warnings, warnings)
        XCTAssertEqual(created.session.id, newSessionID)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>()).filter {
                $0.source == .timer && $0.endAt == nil
            }.map(\.id),
            [activeID]
        )

        let adjacentWarnings = try fixture.commands.validateCompletedSession(
            projectID: project.id,
            startAt: Date(timeIntervalSince1970: 200),
            endAt: Date(timeIntervalSince1970: 400),
            excludingSessionID: newSessionID
        )
        XCTAssertEqual(adjacentWarnings, [])
    }

    func testEditCompletedPreservesIdentitySourceAndCreationWhileUpdatingEveryField() throws {
        let mutationTime = Date(timeIntervalSince1970: 1_900_000_000)
        let fixture = try SessionServiceFixture(now: mutationTime)
        let originalProject = ProjectRecord(name: "Original")
        let workspaceID = UUID(uuidString: "40404040-4040-4040-8040-404040404040")!
        let replacementProject = ProjectRecord(
            workspaceID: workspaceID,
            name: "Archived",
            status: .archived
        )
        let createdAt = Date(timeIntervalSince1970: 100)
        let session = makeSession(
            projectID: originalProject.id,
            source: .timer,
            startAt: Date(timeIntervalSince1970: 200),
            endAt: Date(timeIntervalSince1970: 300),
            note: "Old",
            createdAt: createdAt
        )
        fixture.context.insert(originalProject)
        fixture.context.insert(replacementProject)
        fixture.context.insert(session)
        try fixture.context.save()
        let newStart = Date(timeIntervalSince1970: 400)
        let newEnd = Date(timeIntervalSince1970: 500)

        let result = try fixture.commands.editCompleted(
            sessionID: session.id,
            projectID: replacementProject.id,
            startAt: newStart,
            endAt: newEnd,
            note: "  Corrected work  "
        )

        XCTAssertEqual(result.session.id, session.id)
        XCTAssertEqual(result.session.workspaceID, workspaceID)
        XCTAssertEqual(result.session.projectID, replacementProject.id)
        XCTAssertEqual(result.session.source, .timer)
        XCTAssertEqual(result.session.startAt, newStart)
        XCTAssertEqual(result.session.endAt, newEnd)
        XCTAssertEqual(result.session.startTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.endTimeZoneID, DependencyFixtures.fixedTimeZone.identifier)
        XCTAssertEqual(result.session.note, "Corrected work")
        XCTAssertEqual(result.session.createdAt, createdAt)
        XCTAssertEqual(result.session.updatedAt, mutationTime)
    }

    func testEditActiveAllowsOnlyNonfutureStartAndNoteAndReturnsOverlapWarning() throws {
        let mutationTime = Date(timeIntervalSince1970: 1_000)
        let fixture = try SessionServiceFixture(now: mutationTime)
        let project = ProjectRecord(name: "Client")
        let completedID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let activeID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let completed = makeSession(
            id: completedID,
            projectID: project.id,
            source: .manual,
            startAt: Date(timeIntervalSince1970: 50),
            endAt: Date(timeIntervalSince1970: 150)
        )
        let active = makeSession(
            id: activeID,
            projectID: project.id,
            source: .timer,
            startAt: Date(timeIntervalSince1970: 200),
            note: "Old"
        )
        fixture.context.insert(project)
        fixture.context.insert(completed)
        fixture.context.insert(active)
        try fixture.context.save()

        let result = try fixture.commands.editActive(
            sessionID: activeID,
            startAt: Date(timeIntervalSince1970: 100),
            note: "  Current work "
        )

        XCTAssertEqual(result.warnings, [.overlaps(existingSessionIDs: [completedID])])
        XCTAssertEqual(result.session.startAt, Date(timeIntervalSince1970: 100))
        XCTAssertNil(result.session.endAt)
        XCTAssertEqual(result.session.projectID, project.id)
        XCTAssertEqual(result.session.note, "Current work")
        XCTAssertEqual(result.session.updatedAt, mutationTime)

        XCTAssertThrowsError(
            try fixture.commands.editActive(
                sessionID: activeID,
                startAt: mutationTime.addingTimeInterval(1),
                note: nil
            )
        ) { error in
            XCTAssertEqual(
                error as? SessionCommandError,
                .startIsInFuture(mutationTime.addingTimeInterval(1))
            )
        }
        XCTAssertThrowsError(
            try fixture.commands.editCompleted(
                sessionID: activeID,
                projectID: project.id,
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                note: nil
            )
        ) { error in
            XCTAssertEqual(error as? SessionCommandError, .completedSessionRequired(activeID))
        }
        XCTAssertNil(active.endAt)

        let conflictID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!
        fixture.context.insert(
            makeSession(
                id: conflictID,
                projectID: project.id,
                source: .timer,
                startAt: Date(timeIntervalSince1970: 300)
            )
        )
        try fixture.context.save()
        XCTAssertThrowsError(
            try fixture.commands.editActive(
                sessionID: activeID,
                startAt: Date(timeIntervalSince1970: 100),
                note: "Still working"
            )
        ) { error in
            XCTAssertEqual(
                error as? SessionCommandError,
                .activeSessionReviewRequired(activeSessionIDs: [activeID, conflictID])
            )
        }
    }

    func testDeleteRequiresConfirmationRejectsActiveAndReturnsUpdatedDeletionSnapshot() throws {
        let deletionTime = Date(timeIntervalSince1970: 1_000)
        let fixture = try SessionServiceFixture(now: deletionTime)
        let completed = makeSession(
            id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
            source: .manual,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200)
        )
        let active = makeSession(
            id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
            source: .timer,
            startAt: Date(timeIntervalSince1970: 300)
        )
        fixture.context.insert(completed)
        fixture.context.insert(active)
        try fixture.context.save()

        XCTAssertThrowsError(try fixture.commands.delete(sessionID: completed.id, confirmed: false)) {
            error in
            XCTAssertEqual(error as? SessionCommandError, .deletionRequiresConfirmation)
        }
        XCTAssertThrowsError(try fixture.commands.delete(sessionID: active.id, confirmed: true)) {
            error in
            XCTAssertEqual(error as? SessionCommandError, .activeSessionCannotBeDeleted(active.id))
        }

        let result = try fixture.commands.delete(sessionID: completed.id, confirmed: true)
        XCTAssertEqual(result.deletedAt, deletionTime)
        XCTAssertEqual(result.session.updatedAt, deletionTime)
        XCTAssertEqual(
            try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>()).map(\.id),
            [active.id]
        )
    }

    func testLegacySessionCommandsCannotMutateOrDeleteTimerRunSegments() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let fixture = try SessionServiceFixture(now: now)
        let project = ProjectRecord(name: "Client")
        let runID = UUID()
        let segment = TimeSessionRecord(
            projectID: project.id,
            source: .timer,
            timerRunID: runID,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            startTimeZoneID: "UTC",
            endTimeZoneID: "UTC"
        )
        fixture.context.insert(project)
        fixture.context.insert(segment)
        try fixture.context.save()

        XCTAssertThrowsError(
            try fixture.commands.editCompleted(
                sessionID: segment.id,
                projectID: project.id,
                startAt: segment.startAt,
                endAt: try XCTUnwrap(segment.endAt),
                note: "Bypass"
            )
        ) { error in
            XCTAssertEqual(error as? SessionCommandError, .timerRunCommandRequired(runID))
        }
        XCTAssertThrowsError(try fixture.commands.delete(sessionID: segment.id, confirmed: true)) {
            error in
            XCTAssertEqual(error as? SessionCommandError, .timerRunCommandRequired(runID))
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 1)
    }

    func testCreateSaveFailureRollsBackInsertedSession() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let project = ProjectRecord(name: "Client")
        context.insert(project)
        try context.save()
        let commands = SessionCommandService(
            repository: SaveFailingSessionRepository(
                base: SwiftDataSessionRepository(context: context)
            ),
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertThrowsError(
            try commands.createManual(
                projectID: project.id,
                startAt: DependencyFixtures.fixedNow.addingTimeInterval(-200),
                endAt: DependencyFixtures.fixedNow.addingTimeInterval(-100)
            )
        ) { error in
            XCTAssertEqual(error as? SessionInjectedFailure, .save)
        }
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
    }

    func testEditSaveFailureRollsBackAllChangedFields() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let originalProject = ProjectRecord(name: "Original")
        let replacementProject = ProjectRecord(name: "Replacement")
        let session = makeSession(
            projectID: originalProject.id,
            source: .manual,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200),
            note: "Original"
        )
        context.insert(originalProject)
        context.insert(replacementProject)
        context.insert(session)
        try context.save()
        let originalUpdatedAt = session.updatedAt
        let commands = SessionCommandService(
            repository: SaveFailingSessionRepository(
                base: SwiftDataSessionRepository(context: context)
            ),
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertThrowsError(
            try commands.editCompleted(
                sessionID: session.id,
                projectID: replacementProject.id,
                startAt: Date(timeIntervalSince1970: 300),
                endAt: Date(timeIntervalSince1970: 400),
                note: "Changed"
            )
        ) { error in
            XCTAssertEqual(error as? SessionInjectedFailure, .save)
        }

        let reopened = ModelContext(container)
        let stored = try XCTUnwrap(
            reopened.fetch(FetchDescriptor<TimeSessionRecord>()).first { $0.id == session.id }
        )
        XCTAssertEqual(stored.projectID, originalProject.id)
        XCTAssertEqual(stored.startAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(stored.endAt, Date(timeIntervalSince1970: 200))
        XCTAssertEqual(stored.note, "Original")
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)
    }

    func testDeleteSaveFailureRestoresTheSessionAndOriginalUpdatedTimestamp() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let session = makeSession(
            source: .manual,
            startAt: Date(timeIntervalSince1970: 100),
            endAt: Date(timeIntervalSince1970: 200)
        )
        context.insert(session)
        try context.save()
        let originalUpdatedAt = session.updatedAt
        let commands = SessionCommandService(
            repository: SaveFailingSessionRepository(
                base: SwiftDataSessionRepository(context: context)
            ),
            dependencies: DependencyFixtures.fixed()
        )

        XCTAssertThrowsError(try commands.delete(sessionID: session.id, confirmed: true)) { error in
            XCTAssertEqual(error as? SessionInjectedFailure, .save)
        }

        let reopened = ModelContext(container)
        let stored = try XCTUnwrap(reopened.fetch(FetchDescriptor<TimeSessionRecord>()).first)
        XCTAssertEqual(stored.id, session.id)
        XCTAssertEqual(stored.updatedAt, originalUpdatedAt)
    }

    func testCreateEditAndDeletePersistAcrossContainerRecreation() throws {
        let fixture = try SessionStoreFixture()
        defer { fixture.remove() }
        let projectID = UUID(uuidString: "50505050-5050-4050-8050-505050505050")!
        let sessionID = UUID(uuidString: "60606060-6060-4060-8060-606060606060")!
        let createTime = Date(timeIntervalSince1970: 1_000)

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            context.insert(ProjectRecord(id: projectID, name: "Persistent"))
            try context.save()
            let commands = SessionCommandService(
                repository: SwiftDataSessionRepository(context: context),
                dependencies: DependencyFixtures.fixed(now: createTime, uuid: sessionID)
            )
            _ = try commands.createManual(
                projectID: projectID,
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                note: "Created"
            )
        }

        do {
            let container = try fixture.makeContainer()
            let commands = SessionCommandService(
                repository: SwiftDataSessionRepository(modelContainer: container),
                dependencies: DependencyFixtures.fixed(now: Date(timeIntervalSince1970: 1_100))
            )
            let edited = try commands.editCompleted(
                sessionID: sessionID,
                projectID: projectID,
                startAt: Date(timeIntervalSince1970: 300),
                endAt: Date(timeIntervalSince1970: 400),
                note: "Edited"
            )
            XCTAssertEqual(edited.session.note, "Edited")
        }

        do {
            let container = try fixture.makeContainer()
            let context = ModelContext(container)
            let stored = try XCTUnwrap(context.fetch(FetchDescriptor<TimeSessionRecord>()).first)
            XCTAssertEqual(stored.id, sessionID)
            XCTAssertEqual(stored.startAt, Date(timeIntervalSince1970: 300))
            XCTAssertEqual(stored.endAt, Date(timeIntervalSince1970: 400))
            XCTAssertEqual(stored.note, "Edited")
            let commands = SessionCommandService(
                repository: SwiftDataSessionRepository(context: context),
                dependencies: DependencyFixtures.fixed(now: Date(timeIntervalSince1970: 1_200))
            )
            _ = try commands.delete(sessionID: sessionID, confirmed: true)
        }

        let finalContainer = try fixture.makeContainer()
        let finalContext = ModelContext(finalContainer)
        XCTAssertEqual(try finalContext.fetchCount(FetchDescriptor<TimeSessionRecord>()), 0)
    }
}

@MainActor
private struct SessionServiceFixture {
    let container: ModelContainer
    let context: ModelContext
    let repository: SwiftDataSessionRepository
    let commands: SessionCommandService

    init(
        now: Date = DependencyFixtures.fixedNow,
        uuid: UUID = DependencyFixtures.fixedUUID
    ) throws {
        container = try WellSpentPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        repository = SwiftDataSessionRepository(context: context)
        commands = SessionCommandService(
            repository: repository,
            dependencies: DependencyFixtures.fixed(now: now, uuid: uuid)
        )
    }
}

@MainActor
private final class SaveFailingSessionRepository: SessionRepository {
    private let base: SwiftDataSessionRepository

    init(base: SwiftDataSessionRepository) {
        self.base = base
    }

    func fetchProject(id: UUID) throws -> ProjectRecord? {
        try base.fetchProject(id: id)
    }

    func fetchSession(id: UUID) throws -> TimeSessionRecord? {
        try base.fetchSession(id: id)
    }

    func fetchSessions() throws -> [TimeSessionRecord] {
        try base.fetchSessions()
    }

    func insert(_ session: TimeSessionRecord) {
        base.insert(session)
    }

    func delete(_ session: TimeSessionRecord) {
        base.delete(session)
    }

    func save() throws {
        throw SessionInjectedFailure.save
    }

    func rollback() {
        base.rollback()
    }
}

private enum SessionInjectedFailure: Error, Equatable {
    case save
}

private struct SessionStoreFixture {
    let directoryURL: URL
    let storeURL: URL

    init() throws {
        directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "WellSpentSessionCommandTests-\(UUID().uuidString)",
            isDirectory: true
        )
        storeURL = directoryURL.appendingPathComponent("WellSpent.store")
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    func makeContainer() throws -> ModelContainer {
        try WellSpentPersistence.makePersistentContainer(storeURL: storeURL)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directoryURL)
    }
}

private func makeSession(
    id: UUID = UUID(uuidString: "70707070-7070-4070-8070-707070707070")!,
    projectID: UUID = UUID(uuidString: "80808080-8080-4080-8080-808080808080")!,
    source: TimeSessionSource,
    startAt: Date,
    endAt: Date? = nil,
    note: String? = nil,
    createdAt: Date? = nil
) -> TimeSessionRecord {
    TimeSessionRecord(
        id: id,
        projectID: projectID,
        source: source,
        startAt: startAt,
        endAt: endAt,
        startTimeZoneID: "UTC",
        endTimeZoneID: endAt == nil ? nil : "UTC",
        note: note,
        createdAt: createdAt ?? startAt,
        updatedAt: endAt ?? startAt
    )
}
