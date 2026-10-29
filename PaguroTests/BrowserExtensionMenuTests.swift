#if !APP_STORE
import AppKit
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionMenuTests: XCTestCase {
    func testNativeMenuListsExtensionsAndRunsTheChosenActionAfterItCloses() {
        let window = makeWindow()
        defer { window.close() }
        let first = UUID(), second = UUID()
        var isTracking = false
        var received: UUID?
        let presenter = BrowserExtensionMenuPresenter { menu, anchor in
            isTracking = true
            XCTAssertEqual(menu.items.map(\.title), ["Dark Reader", "Writing tool"])
            XCTAssertFalse(menu.autoenablesItems)
            XCTAssertEqual(menu.items.first?.toolTip, "Change page appearance")
            XCTAssertTrue(NSApp.sendAction(menu.items[1].action!, to: menu.items[1].target, from: menu.items[1]))
            XCTAssertNil(received)
            isTracking = false
        }
        presenter.anchor = window.contentView
        presenter.show([
            BrowserExtensionMenuEntry(id: first, name: "Dark Reader", help: "Change page appearance"),
            BrowserExtensionMenuEntry(id: second, name: "Writing tool")
        ]) { id, anchor in
            XCTAssertFalse(isTracking)
            XCTAssertTrue(anchor === window.contentView)
            received = id
        }
        XCTAssertEqual(received, second)
    }

    func testExtensionMenuItemsAppearInTheSubmenuAndRunTheirOwnAction() {
        let window = makeWindow()
        defer { window.close() }
        let id = UUID()
        final class Target: NSObject {
            var count = 0
            @objc func run(_ sender: Any?) { count += 1 }
        }
        let target = Target()
        let extensionItem = NSMenuItem(title: "Translate this page", action: #selector(Target.run(_:)), keyEquivalent: "")
        extensionItem.target = target
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            let items = menu.items[0].submenu!.items
            XCTAssertEqual(items.map { $0.isSeparatorItem ? "---" : $0.title },
                           ["Open extension", "---", "Translate this page"])
            _ = NSApp.sendAction(items[2].action!, to: items[2].target, from: items[2])
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: id, name: "Probe")],
                       extensionMenuItems: { requested in requested == id ? [extensionItem] : [] }) { _, _ in
            XCTFail("An extension menu item must not run the toolbar action")
        }
        XCTAssertEqual(target.count, 1)
    }

    func testSettingsSubmenuRunsAfterNativeTrackingEnds() {
        let window = makeWindow()
        defer { window.close() }
        let id = UUID()
        var didOpen = false
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            let items = menu.items[0].submenu!.items
            XCTAssertEqual(items.map(\.title), ["Open extension", "Settings…"])
            _ = NSApp.sendAction(items[1].action!, to: items[1].target, from: items[1])
            XCTAssertFalse(didOpen)
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: id, name: "Probe", hasOptions: true)], openOptions: { selected, _ in
            XCTAssertEqual(selected, id)
            didOpen = true
        }) { _, _ in XCTFail("Settings must not invoke the toolbar action") }
        XCTAssertTrue(didOpen)
    }

    func testDiagnosticsAreOptionalAndRunOnlyAfterMenuTrackingEnds() {
        let window = makeWindow()
        defer { window.close() }
        let id = UUID()
        var didShow = false
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            let items = menu.items[0].submenu!.items
            XCTAssertEqual(items.map(\.title), ["Open extension", "Diagnostics…"])
            XCTAssertTrue(items[0].isEnabled, "Diagnostics must not disable a working action")
            _ = NSApp.sendAction(items[1].action!, to: items[1].target, from: items[1])
            XCTAssertFalse(didShow)
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: id, name: "Probe", hasDiagnostics: true)], showDiagnostics: { selected, _ in
            XCTAssertEqual(selected, id)
            didShow = true
        }) { _, _ in XCTFail("Viewing diagnostics must not run the extension") }
        XCTAssertTrue(didShow)
    }

    func testDiagnosticsStayAvailableWhenAnActionIsUnavailable() {
        let window = makeWindow()
        defer { window.close() }
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            XCTAssertTrue(menu.items[0].isEnabled)
            let items = menu.items[0].submenu!.items
            XCTAssertFalse(items[0].isEnabled)
            XCTAssertTrue(items[1].isEnabled)
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: UUID(), name: "Probe", isEnabled: false, hasDiagnostics: true)]) { _, _ in
            XCTFail("Dismissing diagnostics must not run an extension")
        }
    }

    func testUpdateReviewStaysAvailableAndRunsAfterTracking() {
        let window = makeWindow()
        defer { window.close() }
        let id = UUID()
        var reviewed = false
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            let items = menu.items[0].submenu!.items
            XCTAssertEqual(items.map(\.title), ["Open extension", "Review update to 2.0…"])
            XCTAssertFalse(items[0].isEnabled)
            XCTAssertTrue(items[1].isEnabled)
            _ = NSApp.sendAction(items[1].action!, to: items[1].target, from: items[1])
            XCTAssertFalse(reviewed)
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: id, name: "Probe", isEnabled: false, updateVersion: "2.0")], reviewUpdate: { selected in
            XCTAssertEqual(selected, id)
            reviewed = true
        }) { _, _ in XCTFail("Review must not run the installed extension") }
        XCTAssertTrue(reviewed)
    }

    func testUnavailableExtensionCannotRunAndDismissingTheMenuDoesNothing() {
        let window = makeWindow()
        defer { window.close() }
        let presenter = BrowserExtensionMenuPresenter { menu, _ in
            XCTAssertFalse(menu.items[0].isEnabled)
            _ = NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0])
        }
        presenter.anchor = window.contentView
        presenter.show([BrowserExtensionMenuEntry(id: UUID(), name: "Unavailable", isEnabled: false)]) { _, _ in
            XCTFail("An unavailable extension cannot perform an action")
        }
        let cancelled = BrowserExtensionMenuPresenter { _, _ in }
        cancelled.anchor = window.contentView
        cancelled.show([BrowserExtensionMenuEntry(id: UUID(), name: "Dark Reader")]) { _, _ in
            XCTFail("Dismissing a menu must not run an extension")
        }
    }

    func testDetachingTheAnchorWhileTheMenuIsOpenPreventsAnAction() {
        let window = makeWindow()
        defer { window.close() }
        let anchor = NSView()
        window.contentView?.addSubview(anchor)
        let presenter = BrowserExtensionMenuPresenter { menu, anchor in
            _ = NSApp.sendAction(menu.items[0].action!, to: menu.items[0].target, from: menu.items[0])
            anchor.removeFromSuperview()
        }
        presenter.anchor = anchor
        presenter.show([BrowserExtensionMenuEntry(id: UUID(), name: "Dark Reader")]) { _, _ in
            XCTFail("A removed service button must not present a popup")
        }
    }

    func testOnlyTheSelectedServicesExtensionsAppearInTheMenu() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let manager = BrowserExtensionManager(directory: directory)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: directory) }
        try await manager.restore()
        let first = ServiceInstance(label: "A", url: "about:blank")
        let second = ServiceInstance(label: "B", url: "about:blank")
        manager.assignableServiceIDs = { [first.id, second.id] }
        try await manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(manager.installPreview(serviceIDs: [first.id]))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        manager.configure(configuration, for: first)
        let entries = BrowserExtensionActions.menuEntries(manager: manager, serviceID: first.id)
        XCTAssertEqual(entries.map(\.name), ["Paguro isolation probe"])
        XCTAssertTrue(entries.first?.isEnabled == true)
        XCTAssertTrue(BrowserExtensionActions.menuEntries(manager: manager, serviceID: second.id).isEmpty)
        manager.release(first.id)
        let unavailable = BrowserExtensionActions.menuEntries(manager: manager, serviceID: first.id)
        XCTAssertEqual(unavailable.count, 1, "An assigned extension stays visible if its action is unavailable")
        XCTAssertFalse(unavailable[0].isEnabled)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}
#endif
