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

    #if DEBUG
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
            forcesPreview: true
        ).showsHome)
    }
    #endif
}
