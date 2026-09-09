import XCTest
@testable import Paguro

/// The presence preference decides which of the Dock icon and the menu-bar
/// item Paguro shows. Each mode must map to a distinct pair.
final class AppPresenceModeTests: XCTestCase {
    func testDockOnlyShowsTheDockIconAndRemovesTheMenuBarItem() {
        XCTAssertTrue(AppPresenceMode.dock.showsDockIcon)
        XCTAssertFalse(AppPresenceMode.dock.showsMenuBarItem)
    }

    func testMenuBarOnlyHidesTheDockIconAndKeepsTheMenuBarItem() {
        XCTAssertFalse(AppPresenceMode.menuBar.showsDockIcon)
        XCTAssertTrue(AppPresenceMode.menuBar.showsMenuBarItem)
    }

    func testBothShowsBoth() {
        XCTAssertTrue(AppPresenceMode.both.showsDockIcon)
        XCTAssertTrue(AppPresenceMode.both.showsMenuBarItem)
    }

    func testEveryModeIsDistinguishable() {
        let pairs = [AppPresenceMode.dock, .menuBar, .both].map {
            [$0.showsDockIcon, $0.showsMenuBarItem]
        }
        XCTAssertEqual(Set(pairs).count, 3, "Two modes must not behave the same")
    }

    @MainActor
    func testControllerAppliesTheModeAndPublishesIt() {
        let controller = AppPresenceController()
        controller.setMode(.dock)
        XCTAssertEqual(controller.mode, .dock)
        controller.setMode(.menuBar)
        XCTAssertEqual(controller.mode, .menuBar)
    }
}
