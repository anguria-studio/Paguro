import PaguroCore
import SwiftData
import XCTest
@testable import Paguro

/// The store side of the first-run rule.
///
/// `FirstRunPolicy` holds the rule itself and `PaguroCoreTests` cover it. These
/// tests cover the number the window feeds it: the services of every workspace
/// together, which is what "no service configured" means.
final class FirstRunHomeTests: XCTestCase {
    @MainActor
    private func makeStore(context: ModelContext) -> WorkspaceStore {
        WorkspaceStore(
            context: context,
            preferencesStore: PreferencesStore(context: context)
        )
    }

    private func showsHome(serviceCount: Int) -> Bool {
        FirstRunPolicy.presentation(
            serviceCount: serviceCount,
            isLocked: false,
            authorization: .authorized,
            islandIsAvailable: false
        ).showsHome
    }

    /// Workspaces alone do not end first run. Two of them with nothing in them
    /// are still an empty window.
    @MainActor
    func testWorkspacesWithoutServicesStillShowTheHomeScreen() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        context.insert(Space(name: "Personal", emoji: "🏠", sortOrder: 0))
        context.insert(Space(name: "Work", emoji: "💼", sortOrder: 1))
        try context.save()
        let store = makeStore(context: context)

        XCTAssertTrue(store.allServices().isEmpty)
        XCTAssertTrue(showsHome(serviceCount: store.allServices().count))
    }

    /// The first service ends the screen, even when it lands in a workspace
    /// that the window does not show.
    @MainActor
    func testTheFirstServiceInAnyWorkspaceEndsTheHomeScreen() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
        let work = Space(name: "Work", emoji: "💼", sortOrder: 1)
        context.insert(personal)
        context.insert(work)
        try context.save()
        let store = makeStore(context: context)

        let serviceID = try XCTUnwrap(store.addService(
            label: "Chat",
            url: "https://chat.example",
            to: work.id
        ))

        XCTAssertEqual(store.allServices().count, 1)
        XCTAssertFalse(showsHome(serviceCount: store.allServices().count))
        // `AppState.addService` selects the new service, so the shell that
        // replaces the screen opens on it rather than on an empty page.
        XCTAssertNotNil(store.service(id: serviceID))
        XCTAssertTrue(store.servicesForSpace(personal.id).isEmpty)
    }

    /// Intended: an empty window is what the screen describes.
    @MainActor
    func testRemovingEveryServiceReturnsToTheHomeScreen() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
        context.insert(space)
        try context.save()
        let store = makeStore(context: context)
        let serviceID = try XCTUnwrap(store.addService(
            label: "Chat", url: "https://chat.example", to: space.id
        ))
        XCTAssertFalse(showsHome(serviceCount: store.allServices().count))

        context.delete(try XCTUnwrap(store.service(id: serviceID)))
        try context.save()

        XCTAssertTrue(showsHome(serviceCount: store.allServices().count))
    }

    @MainActor
    func testFirstAddCreatesHomeAndSecondAddReusesIt() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let store = makeStore(context: context)
        let first = try XCTUnwrap(store.addService(label: "Mail", url: "https://example.com", to: nil))
        let second = try XCTUnwrap(store.addService(label: "Chat", url: "https://chat.example", to: nil))
        let spaces = try context.fetch(FetchDescriptor<Space>())
        XCTAssertEqual(spaces.count, 1)
        let home = try XCTUnwrap(spaces.first)
        XCTAssertEqual(home.name, "Home")
        XCTAssertEqual(home.emoji, "")
        XCTAssertEqual(store.servicesForSpace(home.id).map(\.id), [first, second])
        XCTAssertEqual(store.service(id: first)?.spaceLinks.first?.space?.id, home.id)
        let selection = store.restoredWindowSelection(fallbackSpaceID: home.id, fallbackServiceID: first)
        XCTAssertEqual(selection.spaceID, home.id)
        XCTAssertEqual(selection.serviceID, first)
    }

    @MainActor
    func testFailedFirstAddRollsBackHomeAndService() throws {
        enum Failure: Error { case save }
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let store = makeStore(context: context)
        XCTAssertThrowsError(try store.addService(
            label: "Mail", url: "https://example.com", to: nil,
            save: { _ in throw Failure.save }
        ))
        try context.save()
        let verification = ModelContext(container)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertEqual(try verification.fetchCount(FetchDescriptor<SpaceServiceLink>()), 0)
    }

    #if DEBUG
    @MainActor
    func testPreviewStartsEmptyOnEveryLaunchAndNeverOpensNormalStore() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let normalURL = directory.appending(path: "default.store")
        let sentinel = Data("the normal store must not be opened or repaired".utf8)
        try sentinel.write(to: normalURL)
        let schema = Schema(versionedSchema: PaguroSchemaVCurrent.self)
        let config = ModelConfiguration(schema: schema, url: normalURL)
        let arguments = [FirstRunPreviewConfiguration.launchArgument]
        let first = StoreLoader.prepare(schema: schema, config: config, arguments: arguments)
        let store = makeStore(context: first.container.mainContext)
        XCTAssertNotNil(try store.addService(label: "Preview", url: "https://example.com", to: nil))
        XCTAssertEqual(store.allServices().count, 1)
        first.defaults.set("preview history", forKey: DefaultsKey.lastKnownContent)

        let second = StoreLoader.prepare(schema: schema, config: config, arguments: arguments)
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertEqual(try second.container.mainContext.fetchCount(FetchDescriptor<ServiceInstance>()), 0)
        XCTAssertNil(second.defaults.string(forKey: DefaultsKey.lastKnownContent))
        XCTAssertFalse(second.allowsPersistentReclamation)
        XCTAssertNotEqual(second.url, normalURL)
        XCTAssertEqual(try Data(contentsOf: normalURL), sentinel)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["default.store"])
    }

    @MainActor
    func testPreviewSessionsAreTemporaryAndSeparateForEachAccount() {
        let manager = DataStoreManager(arguments: [FirstRunPreviewConfiguration.launchArgument])
        let firstID = UUID()
        let first = manager.dataStore(forIdentifier: firstID)
        let second = manager.dataStore(forIdentifier: UUID())
        XCTAssertFalse(first.isPersistent)
        XCTAssertFalse(second.isPersistent)
        XCTAssertTrue(first === manager.dataStore(forIdentifier: firstID))
        XCTAssertFalse(first === second)
    }

    /// The argument is read from the launch arguments alone, so it changes no
    /// stored value. The whole `FirstRunPreviewConfiguration` file sits inside
    /// `DEBUG`, so a Release build has neither the argument nor this route.
    func testThePreviewArgumentIsReadFromTheLaunchArguments() {
        XCTAssertTrue(FirstRunPreviewConfiguration.isEnabled(
            arguments: ["Paguro", FirstRunPreviewConfiguration.launchArgument]
        ))
        XCTAssertFalse(FirstRunPreviewConfiguration.isEnabled(arguments: ["Paguro"]))
        XCTAssertFalse(FirstRunPreviewConfiguration.isEnabled(
            arguments: ["Paguro", "--paguro-first-run"]
        ))
    }

    /// The preview shows the screen over a full workspace without touching it.
    func testThePreviewArgumentShowsTheScreenWithServicesPresent() {
        XCTAssertTrue(FirstRunPolicy.presentation(
            serviceCount: 7,
            isLocked: false,
            authorization: .authorized,
            islandIsAvailable: false,
            previewArgument: true
        ).showsHome)
    }
    #endif
}
