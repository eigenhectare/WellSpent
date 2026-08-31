import Foundation
import SwiftData
import XCTest

@testable import BillableHours

@MainActor
final class ProjectCommandServiceTests: XCTestCase {
    func testCreateTrimsNameAndUsesInjectedIdentityAndTimestamp() throws {
        let fixture = try ProjectServiceFixture()

        let result = try fixture.commands.create(name: "  Client matter\n", colorToken: " blue ")
        let storedProjects = try fixture.context.fetch(FetchDescriptor<ProjectRecord>())

        XCTAssertEqual(result.project.id, DependencyFixtures.fixedUUID)
        XCTAssertEqual(result.project.name, "Client matter")
        XCTAssertEqual(result.project.colorToken, "blue")
        XCTAssertEqual(result.project.status, .active)
        XCTAssertEqual(result.project.createdAt, DependencyFixtures.fixedNow)
        XCTAssertEqual(result.project.updatedAt, DependencyFixtures.fixedNow)
        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(storedProjects.count, 1)
        XCTAssertEqual(storedProjects.first?.id, result.project.id)
    }

    func testCreateAndUpdatePersistOneEmojiWithColorAndName() throws {
        let mutationTime = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try ProjectServiceFixture(now: mutationTime)

        let created = try fixture.commands.create(
            name: "Research",
            colorToken: " purple ",
            emoji: " 🧭 "
        )

        XCTAssertEqual(created.project.emoji, "🧭")
        XCTAssertEqual(created.project.displayName, "🧭 Research")
        XCTAssertEqual(created.project.colorToken, "purple")

        let updated = try fixture.commands.update(
            projectID: created.project.id,
            name: "Client Research",
            colorToken: "teal",
            emoji: "📚"
        )

        XCTAssertEqual(updated.project.name, "Client Research")
        XCTAssertEqual(updated.project.colorToken, "teal")
        XCTAssertEqual(updated.project.emoji, "📚")
        XCTAssertEqual(updated.project.displayName, "📚 Client Research")
        XCTAssertEqual(updated.project.updatedAt, mutationTime)
    }

    func testProjectEmojiMustBeEmptyOrExactlyOneEmojiCharacter() throws {
        let fixture = try ProjectServiceFixture()

        XCTAssertThrowsError(
            try fixture.commands.create(name: "Invalid", emoji: "A")
        ) { error in
            XCTAssertEqual(error as? ProjectCommandError, .invalidEmoji)
        }
        XCTAssertThrowsError(
            try fixture.commands.create(name: "Too many", emoji: "📚🧭")
        ) { error in
            XCTAssertEqual(error as? ProjectCommandError, .invalidEmoji)
        }

        let family = try fixture.commands.create(name: "Combined", emoji: "👨‍💻")
        XCTAssertEqual(family.project.emoji, "👨‍💻")
    }

    func testCreateRejectsEmptyAndWhitespaceNames() throws {
        let fixture = try ProjectServiceFixture()

        XCTAssertThrowsError(try fixture.commands.create(name: "")) { error in
            XCTAssertEqual(error as? ProjectCommandError, .emptyName)
        }
        XCTAssertThrowsError(try fixture.commands.create(name: " \n\t ")) { error in
            XCTAssertEqual(error as? ProjectCommandError, .emptyName)
        }
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectRecord>()), 0)
    }

    func testExactDuplicateWarnsWithoutBlockingCreation() throws {
        let fixture = try ProjectServiceFixture()
        let existingID = UUID(uuidString: "65E1357E-E9C6-4AB9-8C39-0D2E8DEBC27E")!
        fixture.context.insert(ProjectRecord(id: existingID, name: "Matter A"))
        try fixture.context.save()

        let result = try fixture.commands.create(name: "Matter A")

        XCTAssertEqual(result.warnings, [.exactDuplicate(existingProjectIDs: [existingID])])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectRecord>()), 2)
    }

    func testDuplicateComparisonIsExactAndCaseSensitive() throws {
        let fixture = try ProjectServiceFixture()
        fixture.context.insert(ProjectRecord(name: "Matter A"))
        try fixture.context.save()

        let result = try fixture.commands.create(name: "matter a")

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ProjectRecord>()), 2)
    }

    func testRenamePreservesCreationTimestampAndUpdatesMutationTimestamp() throws {
        let mutationTime = Date(timeIntervalSince1970: 1_740_000_000.75)
        let fixture = try ProjectServiceFixture(now: mutationTime)
        let originalCreatedAt = Date(timeIntervalSince1970: 1_700_000_000.25)
        let project = ProjectRecord(name: "Old name", createdAt: originalCreatedAt, updatedAt: originalCreatedAt)
        fixture.context.insert(project)
        try fixture.context.save()

        let result = try fixture.commands.rename(projectID: project.id, to: " New name ")

        XCTAssertEqual(result.project.name, "New name")
        XCTAssertEqual(result.project.createdAt, originalCreatedAt)
        XCTAssertEqual(result.project.updatedAt, mutationTime)
    }

    func testArchiveAndRestoreUpdateQueriesAndMutationTimestamp() throws {
        let archiveTime = Date(timeIntervalSince1970: 1_750_000_000)
        let fixture = try ProjectServiceFixture(now: archiveTime)
        let project = ProjectRecord(name: "Archivable")
        fixture.context.insert(project)
        try fixture.context.save()

        let archived = try fixture.commands.archive(projectID: project.id)

        XCTAssertEqual(archived.project.status, .archived)
        XCTAssertEqual(archived.project.updatedAt, archiveTime)
        XCTAssertEqual(try fixture.queries.activeProjects(), [])
        XCTAssertEqual(try fixture.queries.archivedProjects().map(\.id), [project.id])
        XCTAssertEqual(try fixture.queries.allProjects().map(\.id), [project.id])

        let restoreTime = archiveTime.addingTimeInterval(90)
        let restoreService = ProjectCommandService(
            repository: fixture.repository,
            dependencies: DependencyFixtures.fixed(now: restoreTime)
        )
        let restored = try restoreService.restore(projectID: project.id)

        XCTAssertEqual(restored.project.status, .active)
        XCTAssertEqual(restored.project.updatedAt, restoreTime)
        XCTAssertEqual(try fixture.queries.activeProjects().map(\.id), [project.id])
    }

    func testArchivingProjectWithCompletedSessionRetainsHistoryReference() throws {
        let fixture = try ProjectServiceFixture()
        let project = ProjectRecord(name: "Historical matter")
        fixture.context.insert(project)
        fixture.context.insert(
            TimeSessionRecord(
                projectID: project.id,
                source: .timer,
                startAt: Date(timeIntervalSince1970: 100),
                endAt: Date(timeIntervalSince1970: 200),
                startTimeZoneID: "UTC",
                endTimeZoneID: "UTC"
            )
        )
        try fixture.context.save()

        _ = try fixture.commands.archive(projectID: project.id)

        let sessions = try fixture.context.fetch(FetchDescriptor<TimeSessionRecord>())
        XCTAssertEqual(try fixture.queries.project(id: project.id)?.status, .archived)
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.projectID, project.id)
    }

    func testArchivingProjectWithActiveTimerIsRejectedWithoutMutation() throws {
        let fixture = try ProjectServiceFixture()
        let project = ProjectRecord(name: "Active matter")
        fixture.context.insert(project)
        fixture.context.insert(
            TimeSessionRecord(
                projectID: project.id,
                source: .timer,
                startAt: Date(timeIntervalSince1970: 100),
                startTimeZoneID: "UTC"
            )
        )
        try fixture.context.save()
        let originalUpdatedAt = project.updatedAt

        XCTAssertThrowsError(try fixture.commands.archive(projectID: project.id)) { error in
            XCTAssertEqual(
                error as? ProjectCommandError,
                .activeTimerMustStopOrSwitch(projectID: project.id)
            )
        }
        XCTAssertEqual(project.status, .active)
        XCTAssertEqual(project.updatedAt, originalUpdatedAt)
    }
}

@MainActor
private struct ProjectServiceFixture {
    let container: ModelContainer
    let context: ModelContext
    let repository: SwiftDataProjectRepository
    let commands: ProjectCommandService
    let queries: ProjectQueryService

    init(now: Date = DependencyFixtures.fixedNow) throws {
        container = try BillableHoursPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        repository = SwiftDataProjectRepository(context: context)
        commands = ProjectCommandService(
            repository: repository,
            dependencies: DependencyFixtures.fixed(now: now)
        )
        queries = ProjectQueryService(repository: repository)
    }
}
