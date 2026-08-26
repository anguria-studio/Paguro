import XCTest
import SwiftData
@testable import Atoll

/// Tests the SwiftData layer of "remove service from space" and the
/// membership rule that decides whether the service is deleted with the link.
@MainActor
final class LinkRemovalTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUpWithError() throws {
        let schema = Schema([
            ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
    }

    override func tearDown() {
        container = nil
    }

    private func makeSpace(_ name: String, order: Int) -> Space {
        let space = Space(name: name, emoji: "🏝️", sortOrder: order)
        context.insert(space)
        return space
    }

    private func makeService(_ label: String) -> ServiceInstance {
        let service = ServiceInstance(label: label, url: "https://\(label).example", catalogEntryID: label)
        context.insert(service)
        return service
    }

    @discardableResult
    private func link(_ service: ServiceInstance, to space: Space, order: Int = 0) -> SpaceServiceLink {
        let link = SpaceServiceLink(sortOrder: order, space: space, service: service)
        context.insert(link)
        return link
    }

    private func serviceCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<ServiceInstance>())
    }

    private func linkCount() throws -> Int {
        try context.fetchCount(FetchDescriptor<SpaceServiceLink>())
    }

    // MARK: - removeLink

    func testRemovingOneOfTwoLinksKeepsTheService() throws {
        let personal = makeSpace("Personal", order: 0)
        let work = makeSpace("Work", order: 1)
        let mail = makeService("mail")
        let personalLink = link(mail, to: personal)
        link(mail, to: work)
        try context.save()

        let outcome = try XCTUnwrap(AppState.removeLink(personalLink.id, in: context))

        XCTAssertEqual(outcome.serviceID, mail.id)
        XCTAssertFalse(outcome.deletedService)
        XCTAssertNil(outcome.orphanedDataStoreIdentifier)
        XCTAssertEqual(try serviceCount(), 1, "The service still belongs to Work")
        XCTAssertEqual(try linkCount(), 1)
    }

    func testRemovingTheLastLinkDeletesTheServiceAndReportsItsDataStore() throws {
        let personal = makeSpace("Personal", order: 0)
        let mail = makeService("mail")
        let dataStoreID = mail.dataStoreIdentifier
        let onlyLink = link(mail, to: personal)
        try context.save()

        let outcome = try XCTUnwrap(AppState.removeLink(onlyLink.id, in: context))

        XCTAssertTrue(outcome.deletedService)
        XCTAssertEqual(outcome.orphanedDataStoreIdentifier, dataStoreID)
        XCTAssertEqual(try serviceCount(), 0)
        XCTAssertEqual(try linkCount(), 0)
    }

    /// The regression this file exists for: membership must come from a fetch
    /// that sees unsaved links, not from an inverse relationship that can lag.
    func testAnUnsavedSecondLinkProtectsTheServiceFromDeletion() throws {
        let personal = makeSpace("Personal", order: 0)
        let work = makeSpace("Work", order: 1)
        let mail = makeService("mail")
        let personalLink = link(mail, to: personal)
        try context.save()

        link(mail, to: work)  // not saved yet

        let outcome = try XCTUnwrap(AppState.removeLink(personalLink.id, in: context))

        XCTAssertFalse(outcome.deletedService)
        XCTAssertEqual(try serviceCount(), 1)
        XCTAssertEqual(try linkCount(), 1, "The unsaved Work link is saved with the removal")
    }

    func testRemovingAnUnknownLinkChangesNothing() throws {
        let personal = makeSpace("Personal", order: 0)
        link(makeService("mail"), to: personal)
        try context.save()

        XCTAssertNil(try AppState.removeLink(UUID(), in: context))
        XCTAssertEqual(try serviceCount(), 1)
        XCTAssertEqual(try linkCount(), 1)
    }

    // MARK: - memberships

    func testMembershipsComeFromLinksNotInverses() throws {
        let personal = makeSpace("Personal", order: 0)
        let work = makeSpace("Work", order: 1)
        let mail = makeService("mail")
        let chat = makeService("chat")
        link(mail, to: personal)
        link(mail, to: work)
        link(chat, to: work)
        try context.save()

        let memberships = AppState.memberships(from: try AppState.liveLinks(in: context))

        XCTAssertEqual(memberships[mail.id], [personal.id, work.id])
        XCTAssertEqual(memberships[chat.id], [work.id])
        XCTAssertEqual(
            AppState.servicesOrphaned(byDeletingSpace: work.id, memberships: memberships),
            [chat.id]
        )
    }

    func testLiveLinksSkipDanglingLinks() throws {
        let personal = makeSpace("Personal", order: 0)
        let mail = makeService("mail")
        link(mail, to: personal)
        let ghost = makeService("ghost")
        link(ghost, to: personal)
        try context.save()

        // Delete the service row directly, the way a crashed session can leave
        // a link whose service no longer exists.
        context.delete(ghost)

        let links = try AppState.liveLinks(in: context)
        XCTAssertEqual(links.map(\.service.id), [mail.id])
    }
}
