#if !APP_STORE
import AppKit
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionPageTests: XCTestCase {
    func testTabsCreateAndOptionsRequestsOpenVisiblePagesInOnlyTheirAccount() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeSession()
        defer { fixture.close() }
        let other = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: .nonPersistent())
        defer { other.close() }
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        let popup = try XCTUnwrap(context.action(for: fixture.session)?.popupWebView)
        try await waitForPage(popup)
        context.userGesturePerformed(in: fixture.session)
        let result = try await popup.callAsyncJavaScript("""
            const tab = await browser.tabs.create({url: browser.runtime.getURL('probe.html')});
            return tab.id;
            """, contentWorld: .page)
        XCTAssertNotNil(result)
        let page = try XCTUnwrap(fixture.session.pages.first)
        XCTAssertTrue(page.window?.isVisible == true)
        XCTAssertTrue(page.pageView.configuration.websiteDataStore === fixture.store)
        XCTAssertTrue(page.pageView.configuration.webExtensionController === fixture.session.controller)
        XCTAssertEqual(context.openTabs.count, 2)
        XCTAssertTrue(other.pages.isEmpty)
        try await waitForPage(page.pageView)
        _ = try await popup.callAsyncJavaScript("await browser.runtime.openOptionsPage(); return true;", contentWorld: .page)
        XCTAssertEqual(fixture.session.pages.count, 2)
        XCTAssertEqual(context.openTabs.count, 3)
        try await waitForPage(fixture.session.pages[1].pageView)
        page.window?.performClose(nil)
        XCTAssertEqual(fixture.session.pages.count, 1)
        XCTAssertEqual(context.openTabs.count, 2)
        fixture.session.setActive(false)
        XCTAssertTrue(fixture.session.pages.isEmpty)
        XCTAssertEqual(context.openTabs.count, 1)
    }

    func testPageSwapsWebViewsWhenMovingBetweenExtensionAndOrdinaryContent() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeSession()
        defer { fixture.close() }
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        context.userGesturePerformed(in: fixture.session)
        let page = try fixture.session.openPage(context.baseURL.appending(path: "probe.html"), for: context)
        try await waitForPage(page.pageView)
        let original = page.pageView
        try await page.loadURL(URL(string: "about:blank")!, for: context)
        for _ in 0..<250 {
            if page.pageView !== original, page.pageView.url?.absoluteString == "about:blank", !page.pageView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertFalse(page.pageView === original)
        XCTAssertEqual(page.pageView.url?.absoluteString, "about:blank")
        XCTAssertTrue(page.pageView.configuration.websiteDataStore === fixture.store)
        let ordinary = page.pageView
        try await page.loadURL(context.baseURL.appending(path: "probe.html"), for: context)
        for _ in 0..<250 {
            if page.pageView !== ordinary { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try await waitForPage(page.pageView)
        XCTAssertFalse(page.pageView === ordinary)
        XCTAssertEqual(context.openTabs.count, 2)
        XCTAssertTrue(context.errors.isEmpty, "\(context.errors)")
    }

    func testInactiveUnsafeForeignAndExcessPageRequestsAreRejected() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeSession()
        defer { fixture.close() }
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        let url = context.baseURL.appending(path: "probe.html")
        XCTAssertThrowsError(try fixture.session.openPage(url, for: context))
        context.userGesturePerformed(in: fixture.session)
        for value in ["javascript:alert(1)", "file:///tmp/test", "webkit-extension://other/probe.html"] {
            XCTAssertThrowsError(try fixture.session.openPage(URL(string: value)!, for: context))
        }
        let foreign = WKWebExtensionContext(for: context.webExtension)
        XCTAssertThrowsError(try fixture.session.openPage(url, for: foreign))
        for _ in 0..<ExtensionPagePolicy.maximumOpenPages { try fixture.session.openPage(url, for: context) }
        XCTAssertThrowsError(try fixture.session.openPage(url, for: context))
        let windows = fixture.session.pages.compactMap(\.window)
        fixture.session.close()
        XCTAssertTrue(windows.allSatisfy { !$0.isVisible })
        XCTAssertTrue(fixture.session.pages.isEmpty)
        XCTAssertTrue(fixture.session.controller.extensionContexts.isEmpty)
        XCTAssertThrowsError(try fixture.session.openPage(url, for: context))
    }

    func testContextErrorsNotifyTheSessionAndStayScopedToTheService() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeSession()
        defer { fixture.close() }
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        let popup = try XCTUnwrap(context.action(for: fixture.session)?.popupWebView)
        try await waitForPage(popup)
        var updates = 0
        fixture.session.onIssuesChanged = { updates += 1 }
        _ = try await popup.evaluateJavaScript("setTimeout(() => { throw new Error('Paguro synthetic startup failure'); }, 0); true;")
        try await requireEngineReport("Paguro synthetic startup failure", in: context)
        for _ in 0..<250 {
            if fixture.session.runtimeIssues[fixture.id]?.contains(where: { $0.contains("Paguro synthetic startup failure") }) == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(fixture.session.runtimeIssues[fixture.id]?.contains(where: { $0.contains("Paguro synthetic startup failure") }) == true)
        XCTAssertGreaterThan(updates, 0)
        fixture.session.close()
        XCTAssertTrue(fixture.session.runtimeIssues.isEmpty)
    }

    func testRuntimeDiagnosticsDoNotBlockOrReplaceTheActionPopup() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        try await PopupFocus.requireActiveApp()
        let fixture = try await makeSession()
        defer { fixture.close() }
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 640, height: 500),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        let anchor = try XCTUnwrap(window.contentView)
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        let action = try XCTUnwrap(context.action(for: fixture.session))
        let popup = try XCTUnwrap(action.popupWebView)
        try await waitForPage(popup)
        try await reportDiagnostic("Before opening", in: popup, fixture: fixture)

        fixture.session.perform(fixture.id, from: anchor)
        for _ in 0..<150 {
            if action.popupPopover?.isShown == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let popover = try XCTUnwrap(action.popupPopover)
        XCTAssertTrue(popover.isShown, "A runtime diagnostic must not require an override to open")
        let content = popover.contentViewController
        try await reportDiagnostic("While open", in: popup, fixture: fixture)
        XCTAssertTrue(popover.isShown, "A new diagnostic must leave the working popup open")
        XCTAssertTrue(popover.contentViewController === content)
        let title = try await popup.evaluateJavaScript("document.title") as? String
        XCTAssertEqual(title, "Extension probe")
        let controls = content?.view.subviews.flatMap(\.subviews).compactMap { $0 as? NSButton }
        let keepOpen = try XCTUnwrap(controls?.first { $0.accessibilityIdentifier() == "extension.popup.keepOpen" })
        keepOpen.performClick(nil)
        XCTAssertEqual(popover.behavior, .applicationDefined)
        fixture.session.setActive(false)
        XCTAssertFalse(popover.isShown, "Account deactivation must close even a kept-open popup")
        fixture.session.perform(fixture.id, from: anchor)
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(popover.isShown, "An inactive account cannot reopen its popup")
    }

    /// Some WebKit versions do not list extension runtime errors in
    /// `WKWebExtensionContext.errors` (seen on macOS 15 and 26, not on 27).
    /// Paguro cannot show what the engine does not report, so skip there.
    /// When the engine does report it, Paguro must pass it on, and the test checks that.
    @available(macOS 15.4, *)
    private func requireEngineReport(_ message: String, in context: WKWebExtensionContext) async throws {
        for _ in 0..<250 {
            if context.errors.contains(where: { $0.localizedDescription.contains(message) }) { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw XCTSkip("This WebKit does not report extension runtime errors, so there is nothing to show.")
    }

    @available(macOS 15.4, *)
    private func reportDiagnostic(_ message: String, in popup: WKWebView, fixture: Fixture) async throws {
        // Messages are fixed synthetic strings, with no account or page content.
        let literal = String(decoding: try JSONEncoder().encode(message), as: UTF8.self)
        _ = try await popup.evaluateJavaScript("setTimeout(() => { throw new Error(\(literal)); }, 0); true;")
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        try await requireEngineReport(message, in: context)
        for _ in 0..<150 {
            if fixture.session.runtimeIssues[fixture.id]?.contains(where: { $0.contains(message) }) == true { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("WebKit did not report the synthetic diagnostic")
    }

    @available(macOS 15.4, *)
    private func waitForPage(_ view: WKWebView) async throws {
        for _ in 0..<250 {
            if view.title == "Extension probe", !view.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Extension resource did not finish loading")
        throw CocoaError(.fileReadUnknown)
    }

    @available(macOS 15.4, *)
    private func makeSession() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let package = try BrowserExtensionFixture.package()
        let file = directory.appending(path: "probe.zip")
        try package.data.write(to: file)
        let extensionObject = try await WKWebExtension(resourceBaseURL: file)
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store)
        let id = UUID()
        try session.load(extensionObject, id: id)
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.webExtensionController = session.controller
        let tab = WKWebView(frame: .zero, configuration: config)
        session.open(tab)
        session.setActive(true)
        return Fixture(session: session, store: store, tab: tab, id: id, directory: directory)
    }

    @available(macOS 15.4, *)
    @MainActor
    private struct Fixture {
        let session: ServiceExtensionSession
        let store: WKWebsiteDataStore
        let tab: WKWebView
        let id: UUID
        let directory: URL
        func close() { session.close(); tab.stopLoading(); try? FileManager.default.removeItem(at: directory) }
    }
}
#endif
