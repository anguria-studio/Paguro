#if !APP_STORE
import Foundation
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class ExtensionLifecycleContractTests: XCTestCase {
    func testFreshBeforeAfterConstantsMatrix() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        var reports: [[String: Any]] = []
        for version in [2, 3] {
            for permission in [false, true] {
                let package = try BrowserExtensionFixture.package(manifestVersion: version,
                    additionalPermissions: permission ? ["scripting"] : [], backgroundScript: """
                    function readWorld() {
                        try { return {ok:browser.scripting.ExecutionWorld.MAIN === 'MAIN'}; }
                        catch (error) { return {ok:false,error:String(error)}; }
                    }
                    const startup = readWorld();
                    browser.runtime.onMessage.addListener(() => Promise.resolve(startup));
                    """)
                let resource = try await LifecycleResource(package: package)
                defer { resource.remove() }
                var results: [[String: Any]] = []
                for adapted in [false, true] {
                    let fixture = try LifecycleSession(resource: resource, adapted: adapted)
                    defer { fixture.close() }
                    let popup = try await fixture.popup()
                    let result = try await json(popup, script: """
                        const background = await browser.runtime.sendMessage({snapshot:true});
                        let front;
                        try { front = {ok:browser.scripting.ExecutionWorld.MAIN === 'MAIN'}; }
                        catch (error) { front = {ok:false,error:String(error)}; }
                        return JSON.stringify({background,popup:front});
                        """)
                    let front = try XCTUnwrap(result["popup"] as? [String: Any])
                    let background = try XCTUnwrap(result["background"] as? [String: Any])
                    if adapted { XCTAssertEqual(front["ok"] as? Bool, permission) }
                    if adapted && version == 2 { XCTAssertEqual(background["ok"] as? Bool, permission) }
                    results.append(result)
                }
                let before = try XCTUnwrap(results[0]["background"] as? [String: Any])
                let after = try XCTUnwrap(results[1]["background"] as? [String: Any])
                if version == 3 || !permission { XCTAssertEqual(before["ok"] as? Bool, after["ok"] as? Bool) }
                reports.append(["manifestVersion":version,"scriptingPermission":permission,"sha256":package.sha256,
                    "before":results[0],"after":results[1]])
            }
        }
        try attach(reports, name: "fresh-constants-before-after")
    }

    func testMenuRegistrationAcrossSwitchNavigationAndRecreation() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        var reports: [[String: Any]] = []
        for version in [2, 3] {
            let package = try BrowserExtensionFixture.package(manifestVersion: version,
                additionalPermissions: ["contextMenus"], backgroundScript: Self.menuScript)
            let resource = try await LifecycleResource(package: package)
            defer { resource.remove() }
            for persistent in [false, true] {
                let storeID = UUID()
                let result = try await exerciseMenuLifecycle(resource, version: version, persistent: persistent, storeID: storeID)
                reports.append(result)
            }
        }
        try attach(reports, name: "menu-lifecycle-contracts")
    }

    func testRuntimeReloadMenuBehavior() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        var reports: [[String: Any]] = []
        for version in [2, 3] {
            let package = try BrowserExtensionFixture.package(manifestVersion: version,
                additionalPermissions: ["contextMenus"], backgroundScript: Self.menuScript)
            let resource = try await LifecycleResource(package: package)
            defer { resource.remove() }
            let fixture = try LifecycleSession(resource: resource)
            defer { fixture.close() }
            try await fixture.context.loadBackgroundContent()
            let before = try await menuSnapshot(fixture)
            try assertSingleRegistration(before)
            let popup = try await fixture.popup()
            _ = try await json(popup, script: "setTimeout(() => browser.runtime.reload(), 50); return JSON.stringify({scheduled:true});")
            try await Task.sleep(for: .milliseconds(100))
            var after: [String: Any] = [:]
            for _ in 0..<10 {
                try await Task.sleep(for: .milliseconds(20))
                if let page = try? await fixture.messagingPage() {
                    defer { page.stopLoading() }
                    if let value = try? await json(page, script: "return JSON.stringify(await browser.runtime.sendMessage({snapshot:true}));"),
                       value["boot"] as? String != before["boot"] as? String {
                        after = value
                        break
                    }
                }
            }
            XCTAssertFalse(after.isEmpty, "runtime.reload must start a fresh background")
            if !after.isEmpty { try assertSingleRegistration(after) }
            reports.append(["manifestVersion":version,"before":before,"afterRuntimeReload":after])
        }
        try attach(reports, name: "menu-runtime-reload")
    }

    func testPackageBeforeAfterWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment["PAGURO_CONTRACT_ARCHIVE"] else {
            throw XCTSkip("Opt-in package startup comparison. No account data is loaded.")
        }
        let data = try Data(contentsOf: URL(filePath: path))
        try ExtensionArchivePolicy.validate(data)
        let digest = FirefoxAddonClient.digest(data)
        guard digest == environment["PAGURO_CONTRACT_SHA256"] else { throw CocoaError(.fileReadCorruptFile) }
        let package = FirefoxAddonPackage(slug:"contract-package",version:"comparison",sha256:digest,data:data)
        let resource = try await LifecycleResource(package: package)
        defer { resource.remove() }
        let profile = ExtensionRuntimeProfile(rawValue: environment["PAGURO_CONTRACT_PROFILE"] ?? "standard") ?? .standard
        var reports: [[String: Any]] = []
        for adapted in [false, true] {
            let fixture = try LifecycleSession(resource: resource, adapted: adapted, profile: profile)
            defer { fixture.close() }
            _ = try await fixture.popup()
            try await Task.sleep(for: .seconds(3))
            reports.append(["adapted":adapted,"sha256":digest,"profile":profile.rawValue,
                "name":resource.webExtension.displayName ?? "unknown",
                "version":resource.webExtension.manifest["version"] as? String ?? "unknown",
                "observationMilliseconds":3000,
                "errors":fixture.context.errors.prefix(16).map { String($0.localizedDescription.prefix(2048)) }.sorted()])
        }
        try attach(reports, name: "package-before-after")
    }

    @available(macOS 15.4, *)
    private func exerciseMenuLifecycle(_ resource: LifecycleResource, version: Int, persistent: Bool,
                                       storeID: UUID) async throws -> [String: Any] {
        let store = persistent ? WKWebsiteDataStore(forIdentifier: storeID) : .nonPersistent()
        let first = try LifecycleSession(resource: resource, store: store, storeID: storeID)
        let second = try LifecycleSession(resource: resource, id: first.id)
        defer { first.close(); second.close() }
        let initialA = try await menuSnapshot(first)
        let initialB = try await menuSnapshot(second)
        try assertSingleRegistration(initialA)
        try assertSingleRegistration(initialB)
        XCTAssertNotEqual(initialA["boot"] as? String, initialB["boot"] as? String)
        for _ in 0..<3 {
            first.session.setActive(false); second.session.setActive(true)
            second.session.setActive(false); first.session.setActive(true)
        }
        first.navigate()
        let switched = try await menuSnapshot(first)
        XCTAssertEqual(initialA["boot"] as? String, switched["boot"] as? String)
        try assertSingleRegistration(switched)
        let popup = try await first.popup()
        let duplicate = try await json(popup, script: "return JSON.stringify(await browser.runtime.sendMessage({duplicate:true}));")
        XCTAssertNotNil(duplicate["error"] as? String)
        first.close()
        let recreated = try LifecycleSession(resource: resource, id: first.id, store: first.store, storeID: first.storeID)
        defer { recreated.close() }
        let after = try await menuSnapshot(recreated)
        try assertSingleRegistration(after)
        recreated.close()
        let controller = recreated.session.controller
        let types = WKWebExtensionController.allExtensionDataTypes
        let records = await controller.dataRecords(ofTypes: types)
        await controller.removeData(ofTypes: types, from: records)
        if persistent {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        return ["manifestVersion":version,"persistent":persistent,"initialA":initialA,"initialB":initialB,
            "afterSwitchAndNavigation":switched,"explicitDuplicate":duplicate,"controllerRecreated":after]
    }

    @available(macOS 15.4, *)
    private func menuSnapshot(_ fixture: LifecycleSession) async throws -> [String: Any] {
        let popup = try await fixture.popup()
        return try await json(popup, script: "return JSON.stringify(await browser.runtime.sendMessage({snapshot:true}));")
    }

    private func assertSingleRegistration(_ value: [String: Any]) throws {
        let results = try XCTUnwrap(value["creates"] as? [[String: Any]])
        XCTAssertEqual(results.count, 1, "\(value)")
        XCTAssertTrue(results.first?["error"] is NSNull, "\(value)")
    }

    private func json(_ popup: WKWebView, script: String) async throws -> [String: Any] {
        let bounded = """
            let timer;
            try {
                return await Promise.race([
                    (async () => { \(script) })(),
                    new Promise((_,reject) => { timer = setTimeout(() => reject(new Error('Contract response timed out')), 1500); })
                ]);
            } finally { clearTimeout(timer); }
            """
        let evaluation = LifecycleEvaluation()
        popup.callAsyncJavaScript(bounded, arguments: [:], in: nil, in: .page) { evaluation.result = $0 }
        // A reloaded view can lose its JavaScript timer. Bound the native callback too.
        for _ in 0..<100 {
            if let result = evaluation.result {
                let text = try XCTUnwrap(try result.get() as? String)
                return try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.userCancelled)
    }

    private func attach(_ rows: [[String: Any]], name: String) throws {
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: rows, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private static let menuScript = """
        const boot = crypto.randomUUID();
        const creates = [];
        function create() {
            return new Promise(resolve => {
                chrome.contextMenus.create({id:'shared-entry',title:'Contract menu',contexts:['page']}, () => {
                    resolve({error:chrome.runtime.lastError?.message ?? null});
                });
            });
        }
        const ready = create().then(value => { creates.push(value); });
        browser.runtime.onMessage.addListener(async message => {
            await ready;
            if (message.duplicate) return await create();
            return {boot,creates};
        });
        """
}

@MainActor
private final class LifecycleEvaluation {
    var result: Result<Any, Error>?
}

@available(macOS 15.4, *)
@MainActor
private final class LifecycleResource {
    let file: URL
    let webExtension: WKWebExtension

    init(package: FirefoxAddonPackage) async throws {
        file = FileManager.default.temporaryDirectory.appending(path: "lifecycle-contract-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        webExtension = try await WKWebExtension(resourceBaseURL: file)
    }

    func remove() { try? FileManager.default.removeItem(at: file) }
}

@available(macOS 15.4, *)
@MainActor
private final class LifecycleSession {
    let session: ServiceExtensionSession
    let context: WKWebExtensionContext
    let view: WKWebView
    let id: UUID
    let storeID: UUID
    let store: WKWebsiteDataStore
    private var isClosed = false
    private var messagingViews: [WKWebView] = []

    init(resource: LifecycleResource, adapted: Bool = true, id: UUID = UUID(),
         store: WKWebsiteDataStore = .nonPersistent(), storeID: UUID = UUID(),
         profile: ExtensionRuntimeProfile = .standard) throws {
        self.id = id; self.store = store; self.storeID = storeID
        let views = WKWebViewConfiguration()
        session = ServiceExtensionSession(serviceID: UUID(), storeID: storeID, dataStore: store,
            profile: profile, extensionViewConfiguration: views)
        if !adapted {
            // Remove only the host adapter before loading the unchanged package.
            let content = views.userContentController
            let remaining = content.userScripts.filter { $0.source != BrowserExtensionAPICompatibility.executionWorldConstants }
            content.removeAllUserScripts()
            remaining.forEach(content.addUserScript)
        }
        let configured = session.controller.configuration.webViewConfiguration.userContentController.userScripts
            .contains { $0.source == BrowserExtensionAPICompatibility.executionWorldConstants }
        XCTAssertEqual(configured, adapted, "The control must change only the document adapter")
        try session.load(resource.webExtension, id: id)
        context = try XCTUnwrap(session.contexts[id])
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        configuration.applicationNameForUserAgent = profile.applicationNameForUserAgent
        view = WKWebView(frame: .zero, configuration: configuration)
        session.open(view)
        session.setActive(true)
        navigate()
    }

    func navigate() {
        view.loadHTMLString("<!doctype html><title>Lifecycle contract</title><input name='username'><input type='password'>",
            baseURL: URL(string:"https://example.com/"))
        session.didNavigate()
    }

    func popup() async throws -> WKWebView {
        context.userGesturePerformed(in: session)
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        for _ in 0..<100 {
            if !popup.isLoading, let url = popup.url, url.scheme == context.baseURL.scheme { return popup }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.coderInvalidValue)
    }

    func messagingPage() async throws -> WKWebView {
        let url = context.baseURL.appending(path: "probe.html")
        let page = WKWebView(frame: .zero, configuration: session.pageConfiguration(for: url, context: context))
        messagingViews.append(page)
        page.load(URLRequest(url: url))
        for _ in 0..<100 {
            if page.title == "Extension probe", !page.isLoading { return page }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.fileReadUnknown)
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        messagingViews.forEach { $0.stopLoading() }
        messagingViews.removeAll()
        context.action(for: session)?.popupWebView?.stopLoading()
        view.stopLoading()
        session.close()
    }
}
#endif
