import XCTest
import SwiftData
import BlattaCore
@testable import Blatta

final class WorkspaceStoreMutationTests: XCTestCase {
    @MainActor
    private func makeStore(context: ModelContext) -> WorkspaceStore {
        WorkspaceStore(
            context: context,
            preferencesStore: PreferencesStore(context: context)
        )
    }

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
        let store = makeStore(context: context)

        let icon = Data([0x01, 0x02])
        let serviceID = try XCTUnwrap(store.addService(
            label: "Chat",
            url: "https://chat.example",
            catalogEntryID: "chat",
            userAgent: "Test Agent",
            customIconData: icon,
            to: space.id
        ))

        let services = try context.fetch(FetchDescriptor<ServiceInstance>())
        let added = try XCTUnwrap(services.first { $0.id == serviceID })
        XCTAssertEqual(added.label, "Chat")
        XCTAssertEqual(added.url, "https://chat.example")
        XCTAssertEqual(added.catalogEntryID, "chat")
        XCTAssertEqual(added.userAgent, "Test Agent")
        XCTAssertEqual(added.customIconData, icon)
        let addedLink = try XCTUnwrap(try store.liveLinks().first {
            $0.service.id == serviceID
        })
        XCTAssertEqual(addedLink.space.id, space.id)
        XCTAssertEqual(addedLink.sortOrder, 5)
    }

    @MainActor
    func testAddServiceDoesNothingForMissingSpace() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let store = makeStore(context: context)

        XCTAssertNil(try store.addService(
            label: "Chat",
            url: "https://chat.example",
            to: UUID()
        ))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
    }

    @MainActor
    func testAddServiceUsesExplicitWorkspaceWhenSeveralExist() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let first = Space(name: "First", sortOrder: 0)
        let selected = Space(name: "Selected", sortOrder: 1)
        context.insert(first)
        context.insert(selected)
        try context.save()
        let store = makeStore(context: context)

        let serviceID = try XCTUnwrap(store.addService(
            label: "Chat",
            url: "https://chat.example",
            to: selected.id
        ))

        XCTAssertTrue(store.servicesForSpace(first.id).isEmpty)
        XCTAssertEqual(store.servicesForSpace(selected.id).map(\.id), [serviceID])
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
        let store = makeStore(context: context)

        let outcome = try XCTUnwrap(store.moveService(
            linkID: movingLink.id,
            to: target.id
        ))

        XCTAssertEqual(outcome.serviceID, moving.id)
        XCTAssertEqual(outcome.sourceSpaceID, source.id)
        XCTAssertEqual(outcome.targetSpaceID, target.id)
        let links = try store.liveLinks()
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
        let store = makeStore(context: context)

        XCTAssertNil(try store.moveService(
            linkID: sourceLink.id,
            to: target.id
        ))
        XCTAssertEqual(try store.liveLinks().count, 2)
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
        let store = makeStore(context: context)

        XCTAssertTrue(try store.reorderService(
            droppedLinkID: links[0].id,
            relativeTo: links[2].id,
            placement: .after
        ))

        let reordered = try store.liveLinks()
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
        let store = makeStore(context: context)
        let outcome = try XCTUnwrap(store.deleteService(serviceID))

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
        let store = makeStore(context: context)

        XCTAssertEqual(
            try store.setWorkspaceMuted(true, for: space.id),
            [first.id, second.id]
        )
        XCTAssertTrue(space.isMutedEffective)
        XCTAssertTrue(try store.setServiceMuted(true, for: first.id))
        XCTAssertTrue(first.isMuted)
    }

    @MainActor
    func testCustomIconMutationCanRestoreDefault() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        context.insert(service)
        try context.save()
        let store = makeStore(context: context)

        let icon = Data([0x01, 0x02, 0x03])
        XCTAssertTrue(try store.setCustomIconData(icon, for: service.id))
        XCTAssertEqual(service.customIconData, icon)
        XCTAssertTrue(try store.setCustomIconData(nil, for: service.id))
        XCTAssertNil(service.customIconData)
    }

    @MainActor
    func testFetchedIconAttemptReplacesIconAndRecordsDate() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let service = ServiceInstance(
            label: "Mail",
            url: "https://mail.example",
            fetchedIconData: Data([0x00])
        )
        context.insert(service)
        try context.save()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let icon = Data([0x01, 0x02])
        let store = makeStore(context: context)

        XCTAssertTrue(try store.recordFetchedIconAttempt(
            icon,
            at: date,
            for: service.id
        ))
        XCTAssertEqual(service.fetchedIconData, icon)
        XCTAssertEqual(service.faviconFetchedAt, date)
    }

    @MainActor
    func testFailedFetchedIconAttemptKeepsOldIconAndBacksOff() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let oldIcon = Data([0x01])
        let service = ServiceInstance(
            label: "Mail",
            url: "https://mail.example",
            fetchedIconData: oldIcon
        )
        context.insert(service)
        try context.save()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let store = makeStore(context: context)

        XCTAssertTrue(try store.recordFetchedIconAttempt(
            nil,
            at: date,
            for: service.id
        ))
        XCTAssertEqual(service.fetchedIconData, oldIcon)
        XCTAssertEqual(service.faviconFetchedAt, date)
    }

    @MainActor
    func testFetchedIconAttemptDoesNotOverrideCustomIcon() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let customIcon = Data([0x09])
        let service = ServiceInstance(
            label: "Mail",
            url: "https://mail.example",
            customIconData: customIcon
        )
        context.insert(service)
        try context.save()
        let store = makeStore(context: context)

        XCTAssertFalse(try store.recordFetchedIconAttempt(
            Data([0x01]),
            at: Date(),
            for: service.id
        ))
        XCTAssertEqual(service.customIconData, customIcon)
        XCTAssertNil(service.fetchedIconData)
        XCTAssertNil(service.faviconFetchedAt)
    }

    @MainActor
    func testDeleteSpaceReturnsOnlyOrphanedRuntimeCleanupTargets() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
        let work = Space(name: "Work", emoji: "💼", sortOrder: 1)
        let shared = ServiceInstance(label: "Mail", url: "https://mail.example")
        let orphaned = ServiceInstance(label: "Chat", url: "https://chat.example")
        [personal, work].forEach(context.insert)
        [shared, orphaned].forEach(context.insert)
        ModelFixtures.link(shared, to: personal, sortOrder: 0, in: context)
        ModelFixtures.link(shared, to: work, sortOrder: 0, in: context)
        ModelFixtures.link(orphaned, to: work, sortOrder: 1, in: context)
        try context.save()
        let orphanedDataStoreID = orphaned.dataStoreIdentifier
        let store = makeStore(context: context)

        let outcome = try XCTUnwrap(store.deleteSpace(work.id))

        XCTAssertEqual(outcome.reclaimedServiceIDs, [orphaned.id])
        XCTAssertEqual(outcome.orphanedDataStoreIdentifiers, [orphanedDataStoreID])
        XCTAssertEqual(outcome.remainingSpaceID, personal.id)
        XCTAssertEqual(store.allServices().map(\.id), [shared.id])
        XCTAssertEqual(try store.liveLinks().map(\.space.id), [personal.id])
    }

    @MainActor
    func testDeleteSpaceRefusesToDeleteTheLastWorkspace() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Only", emoji: "🏝️")
        context.insert(space)
        try context.save()
        let store = makeStore(context: context)

        XCTAssertNil(try store.deleteSpace(space.id))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Space>()), 1)
    }

    @MainActor
    func testRestoredWindowSelectionRejectsAServiceOutsideTheSavedWorkspace() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
        let work = Space(name: "Work", emoji: "💼", sortOrder: 1)
        let personalService = ServiceInstance(label: "Mail", url: "https://mail.example")
        let workService = ServiceInstance(label: "Chat", url: "https://chat.example")
        [personal, work].forEach(context.insert)
        [personalService, workService].forEach(context.insert)
        ModelFixtures.link(personalService, to: personal, sortOrder: 0, in: context)
        ModelFixtures.link(workService, to: work, sortOrder: 0, in: context)
        try context.save()
        let preferences = PreferencesStore(context: context)
        let store = WorkspaceStore(context: context, preferencesStore: preferences)
        XCTAssertTrue(preferences.setWindowSelection(
            spaceID: personal.id,
            serviceID: workService.id
        ))

        let selection = store.restoredWindowSelection(
            fallbackSpaceID: work.id,
            fallbackServiceID: workService.id
        )

        XCTAssertEqual(selection.spaceID, personal.id)
        XCTAssertEqual(selection.serviceID, personalService.id)
    }

    @MainActor
    func testSeedCreatesIsolatedDefaultServicesAndRecordsDurableData() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let store = makeStore(context: context)
        let suiteName = "WorkspaceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let outcome = store.seedDefaultDataIfNeeded(defaults: defaults)

        XCTAssertTrue(outcome.didSeed)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Space>()), 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 7)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<SpaceServiceLink>()), 7)
        XCTAssertTrue(defaults.bool(forKey: DefaultsKey.hasEverHadData))
        XCTAssertEqual(
            store.servicesForSpace(try XCTUnwrap(outcome.selectedSpaceID)).count,
            DefaultSeed.personalServices.count
        )
    }

    @MainActor
    func testSeedDoesNotOverwriteAProtectedEmptyStore() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let store = makeStore(context: context)
        let suiteName = "WorkspaceStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: DefaultsKey.hasEverHadData)

        let outcome = store.seedDefaultDataIfNeeded(defaults: defaults)

        XCTAssertFalse(outcome.didSeed)
        XCTAssertNil(outcome.selectedSpaceID)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
    }

    @MainActor
    func testMatchingServicePrefersFreshWorkspaceMembership() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let personal = Space(name: "Personal", emoji: "🏠")
        let work = Space(name: "Work", emoji: "💼")
        let personalMail = ServiceInstance(label: "Mail", url: "https://mail.example/inbox")
        let workMail = ServiceInstance(label: "Mail", url: "https://mail.example/work")
        [personal, work].forEach(context.insert)
        [personalMail, workMail].forEach(context.insert)
        ModelFixtures.link(personalMail, to: personal, sortOrder: 0, in: context)
        try context.save()
        ModelFixtures.link(workMail, to: work, sortOrder: 0, in: context)
        let store = makeStore(context: context)

        let match = store.findServiceMatching(host: "mail.example", preferringSpace: work.id)

        XCTAssertEqual(match?.id, workMail.id)
    }
}
