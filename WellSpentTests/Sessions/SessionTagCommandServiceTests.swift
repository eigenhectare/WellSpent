import Foundation
import SwiftData
import XCTest

@testable import WellSpent

@MainActor
final class SessionTagCommandServiceTests: XCTestCase {
    func testBuiltInsSeedExactlyOnceAndArchivingAllDoesNotReseed() throws {
        let fixture = try TagServiceFixture()

        try fixture.commands.seedBuiltInsIfNeeded()
        var tags = try fixture.repository.fetchTags()

        XCTAssertEqual(tags.map(\.id), SessionTagCommandService.builtInTags.map(\.id))
        XCTAssertEqual(
            tags.map(\.name),
            ["meeting", "internal discussion", "collaboration", "solo work"]
        )
        XCTAssertTrue(tags.allSatisfy(\.isBuiltIn))

        for tag in tags {
            _ = try fixture.commands.archive(id: tag.id)
        }
        try fixture.commands.seedBuiltInsIfNeeded()
        tags = try fixture.repository.fetchTags()

        XCTAssertEqual(tags.count, 4)
        XCTAssertTrue(tags.allSatisfy { $0.status == .archived })
    }

    func testCustomTagNormalizesAndReaddingArchivedNameRestoresSameRecord() throws {
        let fixture = try TagServiceFixture()

        let created = try fixture.commands.create(name: "  Client Call \n")
        XCTAssertEqual(created.name, "Client Call")
        XCTAssertFalse(created.isBuiltIn)

        XCTAssertThrowsError(try fixture.commands.create(name: "client call")) { error in
            XCTAssertEqual(error as? SessionTagCommandError, .duplicateName("Client Call"))
        }

        _ = try fixture.commands.archive(id: created.id)
        let restored = try fixture.commands.create(name: "CLIENT CALL")

        XCTAssertEqual(restored.id, created.id)
        XCTAssertEqual(restored.name, "Client Call")
        XCTAssertEqual(restored.status, .active)
        XCTAssertEqual(try fixture.repository.fetchTags().count, 1)
    }

    func testAssignmentsPersistAfterTagRemovalAndAreDeletedWithSession() throws {
        let container = try WellSpentPersistence.makeInMemoryContainer()
        let context = ModelContext(container)
        let sessionRepository = SwiftDataSessionRepository(context: context)
        let tagRepository = SwiftDataSessionTagRepository(context: context)
        let dependencies = DependencyFixtures.fixed()
        let tagCommands = SessionTagCommandService(
            repository: tagRepository,
            dependencies: dependencies
        )
        try tagCommands.seedBuiltInsIfNeeded()
        let meeting = try XCTUnwrap(
            tagRepository.fetchTags().first { $0.name == "meeting" }
        )
        let soloWork = try XCTUnwrap(
            tagRepository.fetchTags().first { $0.name == "solo work" }
        )
        let project = ProjectRecord(name: "Client")
        context.insert(project)
        try context.save()
        let commands = SessionCommandService(
            repository: sessionRepository,
            tagRepository: tagRepository,
            dependencies: dependencies
        )

        let created = try commands.createManual(
            projectID: project.id,
            startAt: dependencies.now.addingTimeInterval(-3_600),
            endAt: dependencies.now.addingTimeInterval(-1_800),
            note: "Planning",
            tagIDs: [meeting.id, soloWork.id]
        )

        XCTAssertEqual(Set(created.session.tags.map(\.tagID)), [meeting.id, soloWork.id])
        XCTAssertEqual(
            try tagRepository.fetchAssignments(sessionID: created.session.id).count,
            2
        )

        _ = try tagCommands.archive(id: meeting.id)
        let edited = try commands.editCompleted(
            sessionID: created.session.id,
            projectID: project.id,
            startAt: created.session.startAt,
            endAt: try XCTUnwrap(created.session.endAt),
            note: "Planning updated",
            tagIDs: [meeting.id]
        )

        XCTAssertEqual(edited.session.tags.map(\.name), ["meeting"])
        XCTAssertEqual(meeting.status, .archived)
        XCTAssertEqual(
            try tagRepository.fetchAssignments(sessionID: created.session.id).map(\.nameSnapshot),
            ["meeting"]
        )

        _ = try commands.delete(sessionID: created.session.id, confirmed: true)
        XCTAssertTrue(try tagRepository.fetchAssignments(sessionID: created.session.id).isEmpty)
        XCTAssertNotNil(try tagRepository.fetchTag(id: meeting.id))
    }
}

@MainActor
private struct TagServiceFixture {
    let container: ModelContainer
    let context: ModelContext
    let repository: SwiftDataSessionTagRepository
    let commands: SessionTagCommandService

    init() throws {
        container = try WellSpentPersistence.makeInMemoryContainer()
        context = ModelContext(container)
        repository = SwiftDataSessionTagRepository(context: context)
        commands = SessionTagCommandService(
            repository: repository,
            dependencies: DependencyFixtures.fixed()
        )
    }
}
