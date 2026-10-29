#if !APP_STORE
import Foundation
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionProfileTests: XCTestCase {
    func testFirefoxIdentityMatchesBackgroundPopupServiceAndContentScript() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let first = ServiceInstance(label: "Profile A", url: "about:blank")
        let second = ServiceInstance(label: "Profile B", url: "about:blank")
        first.userAgent = UserAgentProvider.mobileSafari
        second.userAgent = UserAgentProvider.mobileSafari
        fixture.manager.assignableServiceIDs = { [first.id, second.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package(backgroundScript: """
            browser.runtime.onMessage.addListener(() => Promise.resolve({userAgent:navigator.userAgent}));
            """))
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [first.id, second.id]))
        XCTAssertTrue(fixture.manager.setProfile(.firefox, for: first.id))
        let pool = WebViewPool(dataStoreManager: DataStoreManager(), userScriptManager: UserScriptManager(), contentBlocker: ContentBlockerManager())
        pool.browserExtensions = fixture.manager
        defer { pool.shutdown() }
        let service = pool.webView(for: first)
        let standard = pool.webView(for: second)
        fixture.manager.didActivate(first.id)
        XCTAssertEqual(service.configuration.applicationNameForUserAgent, "Firefox/143.0")
        XCTAssertEqual(standard.customUserAgent, UserAgentProvider.mobileSafari)
        let context = try XCTUnwrap(service.configuration.webExtensionController?.extensionContexts.first)
        let popup = try XCTUnwrap(context.action(for: nil)?.popupWebView)
        defer { popup.stopLoading() }
        service.loadHTMLString("<!doctype html><title>Profile fixture</title>", baseURL: URL(string: "https://example.com/"))
        for _ in 0..<250 {
            if service.title == "Profile fixture", popup.title == "Extension probe", !service.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let result = try await popup.callAsyncJavaScript("""
            const background = await browser.runtime.sendMessage({identity:true});
            const tabs = await browser.tabs.query({active:true,currentWindow:true});
            const content = await browser.tabs.executeScript(tabs[0].id,{code:'navigator.userAgent'});
            return JSON.stringify({popup:navigator.userAgent,background:background.userAgent,content:content[0]});
            """, contentWorld: .page) as? String
        let values = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(try XCTUnwrap(result).utf8)) as? [String: String])
        let userAgent = try XCTUnwrap(values["popup"])
        XCTAssertTrue(userAgent.hasSuffix("Firefox/143.0"))
        XCTAssertEqual(values["background"], userAgent)
        XCTAssertEqual(values["content"], userAgent)
        let pageIdentity = try await service.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertEqual(pageIdentity, userAgent)
        pool.setUserAgent("Changed mobile preference", for: first.id)
        for _ in 0..<250 {
            if !service.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let updatedIdentity = try await service.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertEqual(updatedIdentity, userAgent)
        XCTAssertTrue(fixture.manager.setProfile(.standard, for: first.id))
        pool.recreateWebView(for: first.id)
        XCTAssertEqual(pool.webView(for: first).customUserAgent, UserAgentProvider.mobileSafari)
    }

    func testProfilePersistsAndLastAssignmentRemovalClearsIt() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let account = UUID()
        fixture.manager.assignableServiceIDs = { [account] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [account]))
        let record = try XCTUnwrap(fixture.manager.records.first)
        XCTAssertTrue(fixture.manager.setProfile(.firefox, for: account))
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertEqual(restored.profile(for: account), .firefox)
        restored.assignableServiceIDs = { [account] }
        XCTAssertTrue(restored.assign(record.id, to: []))
        XCTAssertEqual(restored.profile(for: account), .standard)
        let library = try JSONDecoder().decode(BrowserExtensionLibrary.self, from: Data(contentsOf: fixture.directory.appending(path: "library.json")))
        XCTAssertTrue(library.profiles.isEmpty)
    }

    func testProtectedMediaAndFailedSaveDoNotApplyAProfile() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let account = UUID()
        fixture.manager.assignableServiceIDs = { [account] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [account]))
        var changes = 0
        fixture.manager.onAssignmentsChanged = { _ in changes += 1 }
        fixture.manager.setLocked(true)
        XCTAssertFalse(fixture.manager.setProfile(.firefox, for: account))
        fixture.manager.setLocked(false)
        XCTAssertFalse(fixture.manager.setProfile(.firefox, for: UUID()))
        fixture.manager.canRebuild = { _ in false }
        XCTAssertFalse(fixture.manager.setProfile(.firefox, for: account))
        XCTAssertEqual(fixture.manager.profile(for: account), .standard)
        fixture.manager.canRebuild = { _ in true }
        let index = fixture.directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertFalse(fixture.manager.setProfile(.firefox, for: account))
        XCTAssertEqual(fixture.manager.profile(for: account), .standard)
        XCTAssertEqual(changes, 0)
    }

    func testCreatedPagesKeepProfileAndAccountStore() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        let webExtension = try XCTUnwrap(fixture.manager.preview?.webExtension)
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store, profile: .firefox)
        defer { session.close() }
        let id = UUID()
        try session.load(webExtension, id: id)
        let context = try XCTUnwrap(session.contexts[id])
        for url in [URL(string: "https://example.com/")!, context.baseURL] {
            let config = session.pageConfiguration(for: url, context: context)
            XCTAssertEqual(config.applicationNameForUserAgent, "Firefox/143.0")
            XCTAssertTrue(config.websiteDataStore === store)
        }
    }

    @available(macOS 15.4, *)
    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let manager = BrowserExtensionManager(directory: directory)
        try await manager.restore()
        return Fixture(manager: manager, directory: directory)
    }

    @available(macOS 15.4, *)
    @MainActor
    private struct Fixture {
        let manager: BrowserExtensionManager
        let directory: URL
        func close() { manager.shutdown(); try? FileManager.default.removeItem(at: directory) }
    }
}
#endif
