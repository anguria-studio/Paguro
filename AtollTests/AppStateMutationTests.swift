import XCTest
import SwiftData
import AtollCore
@testable import Atoll

final class AppStateMutationTests: XCTestCase {
    @MainActor
    func testAddServiceUsesTargetTailAndPersistsInput() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Work", emoji: "🏢")
        let resident = ServiceInstance(label: "Resident", url: "https://resident.example")
        context.insert(space)
        context.insert(resident)
        ModelFixtures.link(resident, to: space, sortOrder: 4, in: context)
        try context.save()

        let icon = Data([0x01, 0x02])
        let serviceID = try XCTUnwrap(AppState.addService(
            label: "Chat",
            url: "https://chat.example",
            catalogEntryID: "chat",
            userAgent: "Test Agent",
            customIconData: icon,
            to: space.id,
            in: context
        ))

        let services = try context.fetch(FetchDescriptor<ServiceInstance>())
        let added = try XCTUnwrap(services.first { $0.id == serviceID })
        XCTAssertEqual(added.label, "Chat")
        XCTAssertEqual(added.url, "https://chat.example")
        XCTAssertEqual(added.catalogEntryID, "chat")
        XCTAssertEqual(added.userAgent, "Test Agent")
        XCTAssertEqual(added.customIconData, icon)
        let addedLink = try XCTUnwrap(try AppState.liveLinks(in: context).first {
            $0.service.id == serviceID
        })
        XCTAssertEqual(addedLink.space.id, space.id)
        XCTAssertEqual(addedLink.sortOrder, 5)
    }

    @MainActor
    func testAddServiceDoesNothingForMissingSpace() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext

        XCTAssertNil(try AppState.addService(
            label: "Chat",
            url: "https://chat.example",
            to: UUID(),
            in: context
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
    }

    @MainActor
    func testMoveServiceRelocatesFetchedLinkToTargetTail() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let source = Space(name: "Source", emoji: "1️⃣", sortOrder: 0)
        let target = Space(name: "Target", emoji: "2️⃣", sortOrder: 1)
        let moving = ServiceInstance(label: "Moving", url: "https://moving.example")
        let resident = ServiceInstance(label: "Resident", url: "https://resident.example")
        [source, target].forEach(context.insert)
        [moving, resident].forEach(context.insert)
        let movingLink = ModelFixtures.link(moving, to: source, sortOrder: 0, in: context)
        ModelFixtures.link(resident, to: target, sortOrder: 4, in: context)
        try context.save()

        let outcome = try XCTUnwrap(AppState.moveService(
            linkID: movingLink.id,
            to: target.id,
            in: context
        ))

        XCTAssertEqual(outcome.serviceID, moving.id)
        XCTAssertEqual(outcome.sourceSpaceID, source.id)
        XCTAssertEqual(outcome.targetSpaceID, target.id)
        let links = try AppState.liveLinks(in: context)
        XCTAssertTrue(links.filter { $0.space.id == source.id }.isEmpty)
        let targetLinks = links.filter { $0.space.id == target.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(targetLinks.map { $0.service.label }, ["Resident", "Moving"])
        XCTAssertEqual(targetLinks.map(\.sortOrder), [4, 5])
    }

    @MainActor
    func testMoveServiceRefusesDuplicateTargetMembership() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let source = Space(name: "Source", emoji: "1️⃣", sortOrder: 0)
        let target = Space(name: "Target", emoji: "2️⃣", sortOrder: 1)
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        [source, target].forEach(context.insert)
        context.insert(service)
        let sourceLink = ModelFixtures.link(service, to: source, sortOrder: 0, in: context)
        ModelFixtures.link(service, to: target, sortOrder: 0, in: context)
        try context.save()

        XCTAssertNil(try AppState.moveService(
            linkID: sourceLink.id,
            to: target.id,
            in: context
        ))
        XCTAssertEqual(try AppState.liveLinks(in: context).count, 2)
    }

    @MainActor
    func testReorderServicePersistsContiguousOrder() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Work", emoji: "🏢")
        context.insert(space)
        let services = ["A", "B", "C"].map {
            ServiceInstance(label: $0, url: "https://\($0.lowercased()).example")
        }
        services.forEach(context.insert)
        let links = services.enumerated().map { index, service in
            ModelFixtures.link(service, to: space, sortOrder: index, in: context)
        }
        try context.save()

        XCTAssertTrue(try AppState.reorderService(
            droppedLinkID: links[0].id,
            relativeTo: links[2].id,
            placement: .after,
            in: context
        ))

        let reordered = try AppState.liveLinks(in: context)
            .sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(reordered.map { $0.service.label }, ["B", "C", "A"])
        XCTAssertEqual(reordered.map(\.sortOrder), [0, 1, 2])
    }

    @MainActor
    func testDeleteServiceRemovesEveryMembership() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let first = Space(name: "First", emoji: "1️⃣", sortOrder: 0)
        let second = Space(name: "Second", emoji: "2️⃣", sortOrder: 1)
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        [first, second].forEach(context.insert)
        context.insert(service)
        ModelFixtures.link(service, to: first, sortOrder: 0, in: context)
        try context.save()

        ModelFixtures.link(service, to: second, sortOrder: 0, in: context)
        try context.save()
        let serviceID = service.id
        let dataStoreIdentifier = service.dataStoreIdentifier
        let outcome = try XCTUnwrap(AppState.deleteService(serviceID, in: context))

        XCTAssertEqual(outcome.serviceID, serviceID)
        XCTAssertEqual(outcome.dataStoreIdentifier, dataStoreIdentifier)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
    }

    @MainActor
    func testMuteMutationsReturnAffectedServicesAndPersist() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Work", emoji: "🏢")
        let first = ServiceInstance(label: "Mail", url: "https://mail.example")
        let second = ServiceInstance(label: "Chat", url: "https://chat.example")
        context.insert(space)
        [first, second].forEach(context.insert)
        ModelFixtures.link(first, to: space, sortOrder: 0, in: context)
        ModelFixtures.link(second, to: space, sortOrder: 1, in: context)
        try context.save()

        XCTAssertEqual(
            try AppState.setWorkspaceMuted(true, for: space.id, in: context),
            [first.id, second.id]
        )
        XCTAssertTrue(space.isMutedEffective)
        XCTAssertTrue(try AppState.setServiceMuted(true, for: first.id, in: context))
        XCTAssertTrue(first.isMuted)
    }

    @MainActor
    func testCustomIconMutationCanRestoreDefault() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        context.insert(service)
        try context.save()

        let icon = Data([0x01, 0x02, 0x03])
        XCTAssertTrue(try AppState.setCustomIconData(icon, for: service.id, in: context))
        XCTAssertEqual(service.customIconData, icon)
        XCTAssertTrue(try AppState.setCustomIconData(nil, for: service.id, in: context))
        XCTAssertNil(service.customIconData)
    }
}
