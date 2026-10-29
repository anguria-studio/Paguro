#if !APP_STORE
import AppKit
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionTests: XCTestCase {
    func testFeatureRequiresAnExplicitOptInAndRejectsFirstRunPreview() {
        XCTAssertNil(BrowserExtensionFeature(arguments: []).host)
        XCTAssertNil(BrowserExtensionFeature(arguments: ["--paguro-browser-extensions", "--paguro-first-run-preview"]).host)
        if #available(macOS 15.4, *) {
            let feature = BrowserExtensionFeature(arguments: ["--paguro-browser-extensions"])
            XCTAssertNotNil(feature.manager)
            feature.host?.shutdown()
        }
    }

    func testPreviewDoesNotInstallOrRunUntilTheUserCommits() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertNotNil(fixture.manager.preview)
        XCTAssertTrue(fixture.manager.records.isEmpty)
        let config = WKWebViewConfiguration()
        fixture.manager.configure(config, for: ServiceInstance(label: "A", url: "https://example.com"))
        XCTAssertNil(config.webExtensionController)
        let pending = try XCTUnwrap(fixture.manager.preview?.fileURL)
        fixture.manager.discardPreview()
        XCTAssertFalse(FileManager.default.fileExists(atPath: pending.path))
    }

    func testManifestErrorsBlockInstallationEvenIfWebKitReturnsAnExtension() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        do {
            try await fixture.manager.prepare(BrowserExtensionFixture.package(invalidManifest: true))
            XCTFail("An invalid manifest must not reach the install review")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("WebKit cannot load"))
        }
        XCTAssertNil(fixture.manager.preview)
        XCTAssertTrue(fixture.manager.records.isEmpty)
    }

    func testUpdateWaitsForApprovalAndKeepsTheExtensionIdentityAndResources() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let service = ServiceInstance(label: "A", url: "https://example.com/")
        fixture.manager.assignableServiceIDs = { [service.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))
        let original = try XCTUnwrap(fixture.manager.records.first)
        try await fixture.manager.prepare(BrowserExtensionFixture.package(version: "2.0"))
        XCTAssertEqual(fixture.manager.records.first, original)
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))
        let updated = try XCTUnwrap(fixture.manager.records.first)
        XCTAssertEqual(updated.id, original.id)
        XCTAssertEqual(updated.version, "2.0")
        XCTAssertEqual(updated.serviceIDs, original.serviceIDs)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.directory.appending(path: original.packageName).path))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        fixture.manager.configure(config, for: service)
        let context = try XCTUnwrap(config.webExtensionController?.extensionContexts.first)
        let session = ServiceExtensionSession(serviceID: service.id, storeID: service.dataStoreIdentifier,
                                              dataStore: .nonPersistent())
        defer { session.close() }
        try session.load(context.webExtension, id: updated.id)
        let resource = try await extensionPage(session, id: updated.id)
        resource.stopLoading()
    }

    func testInstallationAndAssignmentsPersistAndPreservePackageResources() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let serviceID = UUID()
        let deletedID = UUID()
        fixture.manager.assignableServiceIDs = { [serviceID] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        let packageURL = try XCTUnwrap(fixture.manager.preview?.fileURL)
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [serviceID, deletedID]))
        XCTAssertTrue(FileManager.default.fileExists(atPath: packageURL.path))
        let record = try XCTUnwrap(fixture.manager.records.first)
        XCTAssertEqual(record.serviceIDs, [serviceID])
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertEqual(restored.records, [record])
        XCTAssertTrue(restored.failures.isEmpty)
    }

    func testPermissionReviewIncludesOptionalAccessWithoutGrantingIt() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let service = ServiceInstance(label: "A", url: "https://example.com")
        fixture.manager.assignableServiceIDs = { [service.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.preview?.permissions.contains("Optional: clipboardWrite") == true)
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        fixture.manager.configure(config, for: service)
        let context = try XCTUnwrap(config.webExtensionController?.extensionContexts.first)
        XCTAssertTrue(context.hasPermission(.storage))
        XCTAssertFalse(context.hasPermission(.clipboardWrite))
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://optional.example/test")!))
    }

    func testFailedSaveAndMediaProtectionKeepThePreviousAssignments() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let first = UUID(), second = UUID()
        fixture.manager.assignableServiceIDs = { [first, second] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [first]))
        let record = try XCTUnwrap(fixture.manager.records.first)
        fixture.manager.canRebuild = { _ in false }
        XCTAssertFalse(fixture.manager.assign(record.id, to: [second]))
        XCTAssertEqual(fixture.manager.records.first?.serviceIDs, [first])
        fixture.manager.canRebuild = { _ in true }
        let index = fixture.directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        XCTAssertFalse(fixture.manager.assign(record.id, to: [second]))
        XCTAssertEqual(fixture.manager.records.first?.serviceIDs, [first])
    }

    func testTamperedPackageIsNotAttachedOnRelaunch() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let service = ServiceInstance(label: "A", url: "https://example.com")
        fixture.manager.assignableServiceIDs = { [service.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))
        let record = try XCTUnwrap(fixture.manager.records.first)
        try Data("tampered".utf8).write(to: fixture.directory.appending(path: record.packageName))
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertNotNil(restored.failures[record.id])
        let config = WKWebViewConfiguration()
        restored.configure(config, for: service)
        XCTAssertNil(config.webExtensionController)
    }

    func testSameOriginAccountsUseSeparateControllersAndCookieStores() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let first = ServiceInstance(label: "A", url: "https://example.com")
        let second = ServiceInstance(label: "B", url: first.url)
        let unselected = ServiceInstance(label: "C", url: first.url)
        fixture.manager.assignableServiceIDs = { [first.id, second.id, unselected.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [first.id, second.id]))
        let configA = WKWebViewConfiguration(), configB = WKWebViewConfiguration()
        configA.websiteDataStore = .nonPersistent()
        configB.websiteDataStore = .nonPersistent()
        fixture.manager.configure(configA, for: first)
        fixture.manager.configure(configB, for: second)
        let controllerA = try XCTUnwrap(configA.webExtensionController)
        let controllerB = try XCTUnwrap(configB.webExtensionController)
        XCTAssertFalse(controllerA === controllerB)
        XCTAssertTrue(controllerA.configuration.defaultWebsiteDataStore === configA.websiteDataStore)
        XCTAssertTrue(controllerB.configuration.defaultWebsiteDataStore === configB.websiteDataStore)
        XCTAssertFalse(controllerA.configuration.defaultWebsiteDataStore === controllerB.configuration.defaultWebsiteDataStore)
        let configC = WKWebViewConfiguration()
        fixture.manager.configure(configC, for: unselected)
        XCTAssertNil(configC.webExtensionController)

        let viewA = WKWebView(frame: .zero, configuration: configA)
        let viewB = WKWebView(frame: .zero, configuration: configB)
        fixture.manager.didCreate(viewA, for: first.id)
        fixture.manager.didCreate(viewB, for: second.id)
        fixture.manager.didActivate(first.id)
        XCTAssertEqual(controllerA.extensionContexts.first?.openTabs.count, 1)
        XCTAssertEqual(controllerB.extensionContexts.first?.openTabs.count, 1)
        fixture.manager.release(first.id)
        XCTAssertTrue(controllerA.extensionContexts.isEmpty)
        XCTAssertEqual(controllerB.extensionContexts.count, 1)
        fixture.manager.shutdown()
        XCTAssertTrue(controllerB.extensionContexts.isEmpty)
    }

    func testExtensionJavaScriptStorageAndCookiesAreIsolatedPerAccount() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let package = try BrowserExtensionFixture.package()
        try await fixture.manager.prepare(package)
        let extensionObject = try XCTUnwrap(fixture.manager.preview?.webExtension)
        let extensionID = UUID()
        let storeA = WKWebsiteDataStore.nonPersistent(), storeB = WKWebsiteDataStore.nonPersistent()
        let sessionA = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: storeA)
        let sessionB = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: storeB)
        defer { sessionA.close(); sessionB.close() }
        try sessionA.load(extensionObject, id: extensionID)
        try sessionB.load(extensionObject, id: extensionID)
        let viewA = try await extensionPage(sessionA, id: extensionID)
        let viewB = try await extensionPage(sessionB, id: extensionID)
        defer { viewA.stopLoading(); viewB.stopLoading() }
        _ = try await viewA.callAsyncJavaScript("await browser.storage.local.set({marker:'account-a'}); return true;",
                                              contentWorld: .page)
        _ = try await viewB.callAsyncJavaScript("await browser.storage.local.set({marker:'account-b'}); return true;",
                                              contentWorld: .page)
        let markerA = try await viewA.callAsyncJavaScript("return (await browser.storage.local.get('marker')).marker;",
                                                         contentWorld: .page) as? String
        let markerB = try await viewB.callAsyncJavaScript("return (await browser.storage.local.get('marker')).marker;",
                                                         contentWorld: .page) as? String
        XCTAssertEqual(markerA, "account-a")
        XCTAssertEqual(markerB, "account-b")
        for (store, value) in [(storeA, "cookie-a"), (storeB, "cookie-b")] {
            let cookie = try XCTUnwrap(HTTPCookie(properties: [
                .domain: "example.com", .path: "/", .name: "paguro-probe", .value: value, .secure: "TRUE"
            ]))
            await withCheckedContinuation { continuation in
                store.httpCookieStore.setCookie(cookie) { continuation.resume() }
            }
        }
        let readCookie = "return (await browser.cookies.get({url:'https://example.com/',name:'paguro-probe'})).value;"
        let cookieA = try await viewA.callAsyncJavaScript(readCookie, contentWorld: .page) as? String
        let cookieB = try await viewB.callAsyncJavaScript(readCookie, contentWorld: .page) as? String
        XCTAssertEqual(cookieA, "cookie-a")
        XCTAssertEqual(cookieB, "cookie-b")
    }

    func testExtensionStorageSurvivesControllerRecreationForTheSameAccount() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        let extensionObject = try XCTUnwrap(fixture.manager.preview?.webExtension)
        let account = UUID(), extensionID = UUID(), serviceID = UUID()
        let store = WKWebsiteDataStore(forIdentifier: account)
        var session = ServiceExtensionSession(serviceID: serviceID, storeID: account, dataStore: store)
        try session.load(extensionObject, id: extensionID)
        var page: WKWebView? = try await extensionPage(session, id: extensionID)
        _ = try await page?.callAsyncJavaScript("await browser.storage.local.set({marker:'saved-account'}); return true;",
                                               contentWorld: .page)
        session.close()
        page?.stopLoading()
        page = nil
        session = ServiceExtensionSession(serviceID: serviceID, storeID: account, dataStore: store)
        try session.load(extensionObject, id: extensionID)
        defer { session.close() }
        let reopened = try await extensionPage(session, id: extensionID)
        defer { reopened.stopLoading() }
        let marker = try await reopened.callAsyncJavaScript("return (await browser.storage.local.get('marker')).marker;",
                                                           contentWorld: .page) as? String
        XCTAssertEqual(marker, "saved-account")
        let records = await session.controller.dataRecords(ofTypes: WKWebExtensionController.allExtensionDataTypes)
        await session.controller.removeData(ofTypes: WKWebExtensionController.allExtensionDataTypes, from: records)
    }

    func testPoolHibernationAndRebuildUnloadOnlyTheAffectedExtensionContexts() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let pool = WebViewPool(dataStoreManager: DataStoreManager(), userScriptManager: UserScriptManager(),
                               contentBlocker: ContentBlockerManager())
        defer { pool.shutdown() }
        pool.browserExtensions = fixture.manager
        let first = ServiceInstance(label: "A", url: "about:blank")
        let second = ServiceInstance(label: "B", url: "about:blank")
        fixture.manager.assignableServiceIDs = { [first.id, second.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [first.id, second.id]))
        let firstView = pool.webView(for: first)
        let secondView = pool.webView(for: second)
        let firstController = try XCTUnwrap(firstView.configuration.webExtensionController)
        let secondController = try XCTUnwrap(secondView.configuration.webExtensionController)
        pool.hibernate(first.id)
        XCTAssertTrue(firstController.extensionContexts.isEmpty)
        XCTAssertEqual(secondController.extensionContexts.count, 1)
        let awakened = pool.webView(for: first)
        XCTAssertFalse(awakened.configuration.webExtensionController === firstController)
        XCTAssertEqual(awakened.configuration.webExtensionController?.extensionContexts.count, 1)
        pool.recreateWebView(for: second.id)
        XCTAssertTrue(secondController.extensionContexts.isEmpty)
        pool.shutdown()
        XCTAssertTrue(awakened.configuration.webExtensionController?.extensionContexts.isEmpty == true)
    }

    func testContentScriptRunsOnlyInTheSelectedService() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let first = ServiceInstance(label: "A", url: "https://example.com/")
        let second = ServiceInstance(label: "B", url: first.url)
        fixture.manager.assignableServiceIDs = { [first.id, second.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [first.id]))
        let configA = WKWebViewConfiguration(), configB = WKWebViewConfiguration()
        configA.websiteDataStore = .nonPersistent()
        configB.websiteDataStore = .nonPersistent()
        fixture.manager.configure(configA, for: first)
        fixture.manager.configure(configB, for: second)
        let viewA = WKWebView(frame: .zero, configuration: configA)
        let viewB = WKWebView(frame: .zero, configuration: configB)
        defer { viewA.stopLoading(); viewB.stopLoading() }
        fixture.manager.didCreate(viewA, for: first.id)
        fixture.manager.didCreate(viewB, for: second.id)
        let page = "<!doctype html><title>Service probe</title><p>Fixture</p>"
        viewA.loadHTMLString(page, baseURL: URL(string: first.url))
        viewB.loadHTMLString(page, baseURL: URL(string: second.url))
        var injection: String?
        for _ in 0..<250 {
            injection = try? await viewA.evaluateJavaScript("document.documentElement.dataset.paguroExtension") as? String
            if injection == "injected", !viewB.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(injection, "injected")
        let unselected = try await viewB.evaluateJavaScript("document.documentElement.dataset.paguroExtension") as? String
        XCTAssertNil(unselected)
    }

    func testSavedPackageAttachesToAnOpenServiceWithoutARebuild() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let service = ServiceInstance(label: "A", url: "https://example.com/")
        fixture.manager.assignableServiceIDs = { [service.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))

        // A new launch reads assignments before the first service view exists.
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        var rebuilds = 0
        restored.onAssignmentsChanged = { _ in rebuilds += 1 }
        try restored.loadLibrary()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        restored.configure(config, for: service)
        let controller = try XCTUnwrap(config.webExtensionController)
        XCTAssertTrue(controller.extensionContexts.isEmpty)
        let view = WKWebView(frame: .zero, configuration: config)
        defer { view.stopLoading() }
        restored.didCreate(view, for: service.id)
        view.loadHTMLString("<!doctype html><title>Service probe</title><p>Fixture</p>", baseURL: URL(string: service.url))
        for _ in 0..<250 where view.isLoading { try await Task.sleep(for: .milliseconds(20)) }

        try await restored.restore()
        XCTAssertEqual(controller.extensionContexts.count, 1)
        var injection: String?
        for _ in 0..<250 {
            injection = try? await view.evaluateJavaScript("document.documentElement.dataset.paguroExtension") as? String
            if injection != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(injection, "injected")
        XCTAssertEqual(rebuilds, 0)
    }

    func testConfiguringAServiceAgainClosesItsPreviousSession() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeManager()
        defer { fixture.close() }
        let service = ServiceInstance(label: "A", url: "https://example.com/")
        fixture.manager.assignableServiceIDs = { [service.id] }
        try await fixture.manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [service.id]))
        let first = WKWebViewConfiguration(), second = WKWebViewConfiguration()
        first.websiteDataStore = .nonPersistent()
        second.websiteDataStore = .nonPersistent()
        fixture.manager.configure(first, for: service)
        let oldController = try XCTUnwrap(first.webExtensionController)
        XCTAssertEqual(oldController.extensionContexts.count, 1)
        fixture.manager.configure(second, for: service)
        XCTAssertTrue(oldController.extensionContexts.isEmpty)
        XCTAssertEqual(second.webExtensionController?.extensionContexts.count, 1)
    }

    func testUnreadableLibraryStaysUntouchedUntilTheUserResetsIt() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let library = directory.appending(path: "library.json")
        try Data("not json".utf8).write(to: library)
        try Data("stale".utf8).write(to: directory.appending(path: "orphan.zip"))
        let manager = BrowserExtensionManager(directory: directory)
        defer { manager.shutdown() }

        do { try await manager.restore(); XCTFail("A corrupt library must not load") } catch {}
        XCTAssertTrue(manager.libraryIsUnreadable)
        XCTAssertEqual(try Data(contentsOf: library), Data("not json".utf8))

        manager.resetUnreadableLibrary()
        for _ in 0..<250 where manager.isBusy { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(manager.libraryIsUnreadable)
        XCTAssertNil(manager.errorMessage)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(files.contains { $0.hasPrefix("library-unreadable-") })
        XCTAssertFalse(files.contains("orphan.zip"))

        let service = ServiceInstance(label: "A", url: "https://example.com/")
        manager.assignableServiceIDs = { [service.id] }
        try await manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(manager.installPreview(serviceIDs: [service.id]))
    }

    @available(macOS 15.4, *)
    private func extensionPage(_ session: ServiceExtensionSession, id: UUID) async throws -> WKWebView {
        let context = try XCTUnwrap(session.contexts[id])
        let configuration = try XCTUnwrap(context.webViewConfiguration)
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 320, height: 240), configuration: configuration)
        view.load(URLRequest(url: context.baseURL.appending(path: "probe.html")))
        for _ in 0..<250 {
            if view.title == "Extension probe", !view.isLoading { return view }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The extension resource did not load")
        throw CocoaError(.fileReadUnknown)
    }

    @available(macOS 15.4, *)
    private func makeManager() async throws -> Fixture {
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
