import XCTest
import SwiftData
@testable import Atoll

/// Tests the SwiftData layer of "remove service from space" and the
/// membership rule that decides whether the service is deleted with the link.
final class LinkRemovalTests: XCTestCase {
    @MainActor
    private final class Fixture {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            let schema = Schema([
                ServiceInstance.self,
                Space.self,
                SpaceServiceLink.self,
                AppPreferences.self,
            ])
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            container = try ModelContainer(for: schema, configurations: [config])
            context = container.mainContext
        }

        func makeSpace(_ name: String, order: Int) -> Space {
            let space = Space(name: name, emoji: "🏝️", sortOrder: order)
            context.insert(space)
            return space
        }

        func makeService(_ label: String) -> ServiceInstance {
            let service = ServiceInstance(
                label: label,
                url: "https://\(label).example",
                catalogEntryID: label
            )
            context.insert(service)
            return service
        }

        @discardableResult
        func link(
            _ service: ServiceInstance,
            to space: Space,
            order: Int = 0
        ) -> SpaceServiceLink {
            let link = SpaceServiceLink(sortOrder: order, space: space, service: service)
            context.insert(link)
            return link
        }

        func serviceCount() throws -> Int {
            try context.fetchCount(FetchDescriptor<ServiceInstance>())
        }

        func linkCount() throws -> Int {
            try context.fetchCount(FetchDescriptor<SpaceServiceLink>())
        }
    }

    // MARK: - removeLink

    @MainActor
    func testRemovingOneOfTwoLinksKeepsTheService() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        let work = fixture.makeSpace("Work", order: 1)
        let mail = fixture.makeService("mail")
        let personalLink = fixture.link(mail, to: personal)
        fixture.link(mail, to: work)
        try context.save()

        let outcome = try XCTUnwrap(AppState.removeLink(personalLink.id, in: context))

        XCTAssertEqual(outcome.serviceID, mail.id)
        XCTAssertFalse(outcome.deletedService)
        XCTAssertNil(outcome.orphanedDataStoreIdentifier)
        XCTAssertEqual(try fixture.serviceCount(), 1, "The service still belongs to Work")
        XCTAssertEqual(try fixture.linkCount(), 1)
    }

    @MainActor
    func testRemovingTheLastLinkDeletesTheServiceAndReportsItsDataStore() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        let mail = fixture.makeService("mail")
        let dataStoreID = mail.dataStoreIdentifier
        let onlyLink = fixture.link(mail, to: personal)
        try context.save()

        let outcome = try XCTUnwrap(AppState.removeLink(onlyLink.id, in: context))

        XCTAssertTrue(outcome.deletedService)
        XCTAssertEqual(outcome.orphanedDataStoreIdentifier, dataStoreID)
        XCTAssertEqual(try fixture.serviceCount(), 0)
        XCTAssertEqual(try fixture.linkCount(), 0)
    }

    /// The regression this file exists for: membership must come from a fetch
    /// that sees unsaved links, not from an inverse relationship that can lag.
    @MainActor
    func testAnUnsavedSecondLinkProtectsTheServiceFromDeletion() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        let work = fixture.makeSpace("Work", order: 1)
        let mail = fixture.makeService("mail")
        let personalLink = fixture.link(mail, to: personal)
        try context.save()

        fixture.link(mail, to: work)  // not saved yet

        let outcome = try XCTUnwrap(AppState.removeLink(personalLink.id, in: context))

        XCTAssertFalse(outcome.deletedService)
        XCTAssertEqual(try fixture.serviceCount(), 1)
        XCTAssertEqual(try fixture.linkCount(), 1, "The unsaved Work link is saved with the removal")
    }

    @MainActor
    func testRemovingAnUnknownLinkChangesNothing() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        fixture.link(fixture.makeService("mail"), to: personal)
        try context.save()

        XCTAssertNil(try AppState.removeLink(UUID(), in: context))
        XCTAssertEqual(try fixture.serviceCount(), 1)
        XCTAssertEqual(try fixture.linkCount(), 1)
    }

    // MARK: - memberships

    @MainActor
    func testMembershipsComeFromLinksNotInverses() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        let work = fixture.makeSpace("Work", order: 1)
        let mail = fixture.makeService("mail")
        let chat = fixture.makeService("chat")
        fixture.link(mail, to: personal)
        fixture.link(mail, to: work)
        fixture.link(chat, to: work)
        try context.save()

        let memberships = AppState.memberships(from: try AppState.liveLinks(in: context))

        XCTAssertEqual(memberships[mail.id], [personal.id, work.id])
        XCTAssertEqual(memberships[chat.id], [work.id])
        XCTAssertEqual(
            AppState.servicesOrphaned(byDeletingSpace: work.id, memberships: memberships),
            [chat.id]
        )
    }

    @MainActor
    func testLiveLinksSkipDanglingLinks() throws {
        let fixture = try Fixture()
        let context = fixture.context
        let personal = fixture.makeSpace("Personal", order: 0)
        let mail = fixture.makeService("mail")
        fixture.link(mail, to: personal)
        let ghost = fixture.makeService("ghost")
        fixture.link(ghost, to: personal)
        try context.save()

        // Delete the service row directly, the way a crashed session can leave
        // a link whose service no longer exists.
        context.delete(ghost)

        let links = try AppState.liveLinks(in: context)
        XCTAssertEqual(links.map(\.service.id), [mail.id])
    }
}
