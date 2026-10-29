#if !APP_STORE
import Foundation
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionCompatibilityTests: XCTestCase {
    func testBitwardenFirefoxProfileReachesLoginWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in Bitwarden profile check.")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "profile-startup-\(UUID().uuidString)")
        let manager = BrowserExtensionManager(directory: directory)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: directory) }
        try await manager.restore()
        let service = ServiceInstance(label: "Disposable profile control", url: "https://example.com/")
        manager.assignableServiceIDs = { [service.id] }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/")
        let package = try await FirefoxAddonClient().fetch(source)
        try await manager.prepare(package)
        XCTAssertTrue(manager.installPreview(serviceIDs: [service.id]))
        XCTAssertTrue(manager.setProfile(.firefox, for: service.id))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        manager.configure(config, for: service)
        let view = WKWebView(frame: .zero, configuration: config)
        defer { view.stopLoading() }
        manager.didCreate(view, for: service.id)
        manager.didActivate(service.id)
        view.loadHTMLString("<!doctype html><title>Profile startup</title>", baseURL: URL(string: service.url))
        let context = try XCTUnwrap(config.webExtensionController?.extensionContexts.first)
        let popup = try XCTUnwrap(context.action(for: nil)?.popupWebView)
        defer { popup.stopLoading() }
        var text = ""
        for _ in 0..<250 {
            text = (try? await popup.evaluateJavaScript("document.body?.innerText ?? ''")) as? String ?? ""
            if text.contains("Create account"), text.contains("Log in") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(text.contains("Create account") && text.contains("Log in"))
        _ = try await popup.evaluateJavaScript("Array.from(document.querySelectorAll('a,button')).find(e => e.textContent.trim() === 'Log in')?.click(); true;")
        for _ in 0..<250 {
            text = (try? await popup.evaluateJavaScript("document.body?.innerText ?? ''")) as? String ?? ""
            if text.contains("Email address") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(text.contains("Email address"))
        let serviceIdentity = try await view.evaluateJavaScript("navigator.userAgent") as? String
        let popupIdentity = try await popup.evaluateJavaScript("navigator.userAgent") as? String
        XCTAssertEqual(serviceIdentity, popupIdentity)
        print("BITWARDEN PROFILE STARTUP: version=\(package.version), sha256=\(package.sha256), emailForm=\(text.contains("Email address")), identitiesMatch=\(serviceIdentity == popupIdentity)")
    }

    func testBitwardenPopupStartupWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "bitwarden-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/")
        let package = try await FirefoxAddonClient().fetch(source)
        let url = directory.appending(path: "bitwarden.zip")
        try package.data.write(to: url)
        let webExtension = try await WKWebExtension(resourceBaseURL: url)
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store)
        defer { session.close() }
        let id = UUID()
        try session.load(webExtension, id: id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        let tab = WKWebView(frame: .zero, configuration: configuration)
        session.open(tab)
        session.setActive(true)
        let context = try XCTUnwrap(session.contexts[id])
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        defer { popup.stopLoading() }
        try await Task.sleep(for: .seconds(8))
        print("BITWARDEN STARTUP: version=\(package.version), contextErrors=\(context.errors.map(\.localizedDescription))")
        let result = try await popup.callAsyncJavaScript("""
            return JSON.stringify({
                state: document.readyState,
                userAgent: navigator.userAgent,
                text: document.body?.innerText?.slice(0, 500),
                backgroundPageAPI: typeof chrome.extension?.getBackgroundPage,
                runtimeBackgroundAPI: typeof chrome.runtime?.getBackgroundPage,
                APIs: Object.fromEntries(['idle','notifications','webRequest','contextMenus','storage','runtime']
                    .map(key => [key, typeof chrome[key]]))
            });
            """, contentWorld: .page)
        print("BITWARDEN STARTUP: popup=\(String(describing: result))")
    }

    func testBitwardenSafariIdentityWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = FileManager.default.temporaryDirectory.appending(path: "bitwarden-identity-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let configuration = WKWebExtensionController.Configuration.nonPersistent()
        let store = WKWebsiteDataStore.nonPersistent()
        configuration.defaultWebsiteDataStore = store
        let views = WKWebViewConfiguration()
        views.websiteDataStore = store
        views.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        configuration.webViewConfiguration = views
        let controller = WKWebExtensionController(configuration: configuration)
        let context = WKWebExtensionContext(for: webExtension)
        context.grantedPermissions = Dictionary(uniqueKeysWithValues: webExtension.requestedPermissions.map { ($0, Date.distantFuture) })
        context.grantedPermissionMatchPatterns = Dictionary(uniqueKeysWithValues: webExtension.allRequestedMatchPatterns.map { ($0, Date.distantFuture) })
        try controller.load(context)
        defer { try? controller.unload(context) }
        print("BITWARDEN SAFARI IDENTITY: loaded \(package.version)")
        let popup = try XCTUnwrap(context.action(for: nil)?.popupWebView)
        defer { popup.stopLoading() }
        try await Task.sleep(for: .seconds(8))
        print("BITWARDEN SAFARI IDENTITY: contextErrors=\(context.errors.map(\.localizedDescription))")
        var snapshot: String?
        popup.evaluateJavaScript("JSON.stringify({userAgent:navigator.userAgent,text:document.body?.innerText?.slice(0,500)})") { result, error in
            snapshot = (result as? String) ?? error?.localizedDescription
        }
        for _ in 0..<100 {
            if snapshot != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        print("BITWARDEN SAFARI IDENTITY: popup=\(snapshot ?? "JavaScript did not respond")")
    }

    func testSimpleTranslateWholePageRequestWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/simple-translate/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = FileManager.default.temporaryDirectory.appending(path: "translate-probe-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store)
        defer { session.close() }
        let id = UUID()
        try session.load(webExtension, id: id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        let tab = WKWebView(frame: .zero, configuration: configuration)
        defer { tab.stopLoading() }
        session.open(tab)
        session.setActive(true)
        tab.loadHTMLString("<!doctype html><title>Public translation fixture</title><p>Bonjour</p>", baseURL: URL(string: "https://example.com/"))
        for _ in 0..<250 {
            if !tab.isLoading, tab.title != nil { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let context = try XCTUnwrap(session.contexts[id])
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        defer { popup.stopLoading() }
        var hasAction = false
        for _ in 0..<250 {
            hasAction = (try? await popup.evaluateJavaScript("Array.from(document.querySelectorAll('a')).some(a => a.textContent.includes('Translate this page'))")) as? Bool ?? false
            if hasAction { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(hasAction)
        context.userGesturePerformed(in: session)
        _ = try await popup.evaluateJavaScript("Array.from(document.querySelectorAll('a')).find(a => a.textContent.includes('Translate this page')).click(); true;")
        for _ in 0..<250 {
            if !session.pages.isEmpty { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let page = try XCTUnwrap(session.pages.first)
        XCTAssertTrue(page.window?.isVisible == true)
        XCTAssertTrue(page.pageView.configuration.websiteDataStore === store)
        for _ in 0..<500 {
            if page.pageView.url != nil, !page.pageView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        print("SIMPLE TRANSLATE PAGE: version=\(package.version), url=\(String(describing: page.pageView.url)), title=\(String(describing: page.pageView.title)), errors=\(context.errors)")
        XCTAssertTrue(page.pageView.url?.host?.contains("translate") == true)
    }

    func testBitwardenSafariTimerContractWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = FileManager.default.temporaryDirectory.appending(path: "bitwarden-timer-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let views = WKWebViewConfiguration()
        views.applicationNameForUserAgent = ExtensionCompatibilityProbe.Identity.safari.applicationName
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
            extensionViewConfiguration: views)
        let host = CompatibilityTimerHost(session: session)
        session.controller.delegate = host
        let context = WKWebExtensionContext(for: webExtension)
        context.grantedPermissions = Dictionary(uniqueKeysWithValues:
            webExtension.requestedPermissions.union([.nativeMessaging]).map { ($0, Date.distantFuture) })
        context.grantedPermissionMatchPatterns = Dictionary(uniqueKeysWithValues:
            webExtension.allRequestedMatchPatterns.map { ($0, Date.distantFuture) })
        try session.controller.load(context)
        defer { try? session.controller.unload(context); host.cancel(); session.close() }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        let tab = WKWebView(frame: .zero, configuration: configuration)
        defer { tab.stopLoading() }
        session.open(tab)
        session.setActive(true)
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        defer { popup.stopLoading() }
        var text = ""
        for _ in 0..<250 {
            text = (try? await popup.evaluateJavaScript("document.body?.innerText ?? ''")) as? String ?? ""
            if text.contains("Log in"), text.contains("Create account") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(text.contains("Log in") && text.contains("Create account"), text)
        XCTAssertGreaterThan(host.sleepRequests, 0)
        print("BITWARDEN SAFARI TIMER CONTROL: version=\(package.version), sha256=\(package.sha256), sleeps=\(host.sleepRequests), text=\(text), errors=\(context.errors)")
    }

    func testBitwardenFirefoxWelcomeWithoutObserversWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/bitwarden-password-manager/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = FileManager.default.temporaryDirectory.appending(path: "bitwarden-control-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let views = WKWebViewConfiguration()
        views.applicationNameForUserAgent = ExtensionCompatibilityProbe.Identity.firefox.applicationName
        let store = WKWebsiteDataStore.nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
            extensionViewConfiguration: views)
        defer { session.close() }
        let id = UUID()
        try session.load(webExtension, id: id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        let tab = WKWebView(frame: .zero, configuration: configuration)
        defer { tab.stopLoading() }
        session.open(tab)
        session.setActive(true)
        let context = try XCTUnwrap(session.contexts[id])
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        defer { popup.stopLoading() }
        var text = ""
        for _ in 0..<250 {
            text = (try? await popup.evaluateJavaScript("document.body?.innerText ?? ''")) as? String ?? ""
            if text.contains("Log in"), text.contains("Create account") { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(text.contains("Log in") && text.contains("Create account"), text)
        print("BITWARDEN FIREFOX CONTROL: version=\(package.version), sha256=\(package.sha256), text=\(text), errors=\(context.errors)")
    }

    func testRuntimeInvestigationWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let slug = ProcessInfo.processInfo.environment["PAGURO_EXTENSION_PROBE_SLUG"] ?? "bitwarden-password-manager"
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(slug)/")
        let package = try await FirefoxAddonClient().fetch(source)
        let file = FileManager.default.temporaryDirectory.appending(path: "runtime-probe-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        for identity in [ExtensionCompatibilityProbe.Identity.webKit, .safari, .firefox] {
            let probe = ExtensionCompatibilityProbe(identity: identity)
            defer { probe.close() }
            let id = UUID()
            try probe.load(webExtension, id: id)
            probe.loadServiceFixture()
            for _ in 0..<100 {
                if probe.isServiceFixtureReady { break }
                try await Task.sleep(for: .milliseconds(20))
            }
            probe.recordServiceState()
            probe.session.didNavigate()
            try await Task.sleep(for: .seconds(2))
            try probe.openPopup(id: id)
            try await Task.sleep(for: .seconds(6))
            probe.snapshotPopup()
            if slug == "bitwarden-password-manager", identity == .firefox {
                probe.evaluatePopup("""
                    const login = Array.from(document.querySelectorAll('a,button')).find(e => e.textContent.trim() === 'Log in');
                    login?.click();
                    return JSON.stringify({loginActionFound:!!login});
                    """, label: "login.opened")
            }
            try await Task.sleep(for: .seconds(2))
            if slug == "bitwarden-password-manager", identity == .firefox {
                probe.snapshotPopup()
                try await Task.sleep(for: .milliseconds(100))
            }
            let data = try JSONEncoder().encode(probe.report(package: package, identity: identity))
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
            attachment.name = "\(slug)-\(identity.rawValue)-runtime"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("EXTENSION RUNTIME REPORT: \(String(decoding: data, as: UTF8.self))")
        }
    }

    func testLiveFirefoxPackagesWhenExplicitlyRequested() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        guard ProcessInfo.processInfo.environment["PAGURO_EXTENSION_LIVE_PROBES"] == "1" else {
            throw XCTSkip("Opt-in live compatibility research. See BROWSER-EXTENSIONS.md.")
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "extension-probes-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for slug in ["bitwarden-password-manager", "grammarly-1", "darkreader", "tampermonkey"] {
            let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(slug)/")
            do {
                let package = try await FirefoxAddonClient().fetch(source)
                let url = directory.appending(path: "\(slug).zip")
                try package.data.write(to: url)
                let webExtension = try await WKWebExtension(resourceBaseURL: url)
                let errors = webExtension.errors.map(\.localizedDescription).joined(separator: "; ")
                print("EXTENSION PROBE: \(slug), version=\(package.version), bytes=\(package.data.count), manifestErrors=[\(errors)]")
                let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: .nonPersistent())
                defer { session.close() }
                do {
                    try session.load(webExtension, id: UUID())
                    print("EXTENSION PROBE: \(slug), controllerLoad=passed")
                } catch { print("EXTENSION PROBE: \(slug), controllerLoad=\(error.localizedDescription)") }
            } catch { print("EXTENSION PROBE: \(slug), downloadOrManifest=\(error.localizedDescription)") }
        }
    }
}

#endif
