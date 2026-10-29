#if !APP_STORE
import AppKit
import WebKit
import XCTest
@testable import Paguro

/// Records the context menu WebKit builds, then empties it so nothing opens.
@available(macOS 15.4, *)
private final class MenuRecordingWebView: WKWebView {
    var items: [NSMenuItem] = []
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        items = menu.items
        menu.removeAllItems()
    }
}

@MainActor
final class BrowserExtensionContextMenuTests: XCTestCase {
    /// Each click is stored under its own key. Clicks can arrive together,
    /// and a shared list would lose one of them.
    private static let background = """
        const api = browser.menus || browser.contextMenus;
        api.create({id:'page-item', title:'Probe page item', contexts:['page','selection','link','editable']});
        api.create({id:'tab-item', title:'Probe tab item', contexts:['tab']});
        api.create({id:'action-item', title:'Probe action item', contexts:['browser_action']});
        api.create({id:'open-item', title:'Probe open page', contexts:['browser_action']});
        api.onClicked.addListener((info, tab) => {
            if (info.menuItemId === 'open-item') browser.tabs.create({url: 'https://example.com/opened'});
            browser.storage.local.set({['click-' + info.menuItemId]: {page: info.pageUrl || null, tab: tab ? tab.url : null}});
        });
        """

    func testPageContextMenuIncludesExtensionItemsAndDeliversClicks() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        for type: NSEvent.EventType in [.rightMouseDown, .rightMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: NSPoint(x: 100, y: 350),
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: fixture.window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            fixture.window.sendEvent(event)
        }
        for _ in 0..<150 where fixture.view.items.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        let all = fixture.view.items.flatMap { [$0] + ($0.submenu?.items ?? []) }
        let item = try XCTUnwrap(all.first { $0.title == "Probe page item" }, "WebKit must add page items to the page menu")
        XCTAssertFalse(all.contains { $0.title == "Probe tab item" || $0.title == "Probe action item" })
        NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        let click = try await fixture.click("page-item")
        XCTAssertEqual(click["page"] as? String, "https://example.com/")
    }

    func testSessionOffersActionAndTabItemsOnlyWhileActive() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let items = fixture.session.menuItems(fixture.id)
        XCTAssertEqual(Set(items.map(\.title)), ["Probe action item", "Probe open page", "Probe tab item"])
        for title in ["Probe action item", "Probe tab item"] {
            let item = try XCTUnwrap(items.first { $0.title == title })
            NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        }
        let action = try await fixture.click("action-item")
        let tab = try await fixture.click("tab-item")
        XCTAssertEqual(action["tab"] as? String, "https://example.com/")
        XCTAssertEqual(tab["tab"] as? String, "https://example.com/")
        fixture.session.setActive(false)
        XCTAssertTrue(fixture.session.menuItems(fixture.id).isEmpty, "An inactive service offers no extension items")
    }

    func testMenuItemClickCanOpenAnExtensionPage() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let item = try XCTUnwrap(fixture.session.menuItems(fixture.id).first { $0.title == "Probe open page" })
        NSApp.sendAction(try XCTUnwrap(item.action), to: item.target, from: item)
        _ = try await fixture.click("open-item")
        for _ in 0..<150 where fixture.session.pages.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(fixture.session.pages.count, 1, "A menu click is a user action, so it may open a page")
    }

    // MARK: - Fixture

    @available(macOS 15.4, *)
    private func makeFixture() async throws -> Fixture {
        let manifest: [String: Any] = [
            "manifest_version": 2, "name": "Menu probe", "version": "1.0", "description": "Context menu probe",
            "permissions": ["menus", "storage", "https://example.com/*"],
            "browser_action": ["default_title": "Menu probe"],
            "background": ["scripts": ["background.js"], "persistent": false]]
        let data = BrowserExtensionFixture.archive([
            ("manifest.json", try JSONSerialization.data(withJSONObject: manifest)),
            ("background.js", Data(Self.background.utf8)),
            ("probe.html", Data("<!doctype html><title>Probe</title>".utf8))])
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: "menu.zip")
        try data.write(to: file)
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        XCTAssertTrue(webExtension.errors.isEmpty)
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store)
        let id = UUID()
        try session.load(webExtension, id: id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        let view = MenuRecordingWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 600, height: 400),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        session.open(view)
        session.setActive(true)
        view.loadHTMLString("<!doctype html><title>Menu page</title><p style='font-size:40px'>Page text</p>",
                            baseURL: URL(string: "https://example.com/"))
        for _ in 0..<150 where view.isLoading || view.title != "Menu page" { try await Task.sleep(for: .milliseconds(20)) }
        let context = try XCTUnwrap(session.contexts[id])
        // Menu registration happens in the background script, after load.
        for _ in 0..<150 where session.menuItems(id).count < 3 { try await Task.sleep(for: .milliseconds(20)) }
        return Fixture(session: session, id: id, context: context, view: view, window: window, directory: directory)
    }

    @available(macOS 15.4, *)
    @MainActor
    private struct Fixture {
        let session: ServiceExtensionSession
        let id: UUID
        let context: WKWebExtensionContext
        let view: MenuRecordingWebView
        let window: NSWindow
        let directory: URL

        /// Reads the click record that the extension stored for a menu item.
        func click(_ itemID: String) async throws -> [String: Any] {
            let reader = WKWebView(frame: .zero, configuration: try XCTUnwrap(context.webViewConfiguration))
            defer { reader.stopLoading() }
            reader.load(URLRequest(url: context.baseURL.appending(path: "probe.html")))
            for _ in 0..<150 where reader.isLoading || reader.title != "Probe" { try await Task.sleep(for: .milliseconds(20)) }
            for _ in 0..<150 {
                let value = try await reader.callAsyncJavaScript(
                    "return (await browser.storage.local.get(key))[key] || null;",
                    arguments: ["key": "click-\(itemID)"], contentWorld: .page)
                if let record = value as? [String: Any] { return record }
                try await Task.sleep(for: .milliseconds(20))
            }
            XCTFail("The extension did not receive the click for \(itemID)")
            return [:]
        }

        func close() {
            session.close()
            view.stopLoading()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
#endif
