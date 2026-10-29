#if !APP_STORE
import AppKit
import Foundation
import WebKit
import XCTest
@testable import Paguro

/// Test-only observations. This code is not part of the application target.
@available(macOS 15.4, *)
@MainActor
final class ExtensionCompatibilityProbe: NSObject, WKScriptMessageHandler {
    enum Identity: String, CaseIterable, Codable {
        case webKit, safari, firefox, chrome

        var applicationName: String? {
            switch self {
            case .webKit: nil
            case .safari: "Version/26.0 Safari/605.1.15"
            case .firefox: "Firefox/143.0"
            case .chrome: "Chrome/143.0.0.0 Safari/605.1.15"
            }
        }
    }

    struct Event: Codable {
        let elapsedMilliseconds: Int
        let surface: String
        let event: String
        let detail: String
    }

    struct Report: Codable {
        let slug: String
        let version: String
        let sha256: String
        let os: String
        let webKitVersion: String
        let identity: Identity
        let configuredDocumentAdapters: [String]
        let events: [Event]
        let contextErrors: [String]
        let recognizedRequiredPermissions: [String]
        let declaredPermissions: [String]
        let optionalPermissions: [String]
    }

    private let started = ContinuousClock.now
    private let content = WKUserContentController()
    private var events: [Event] = []
    private var repetitions: [String: Int] = [:]
    private(set) var session: ServiceExtensionSession!
    private var tab: WKWebView?
    private var popup: WKWebView?

    init(identity: Identity, store: WKWebsiteDataStore = .nonPersistent(), matchServiceIdentity: Bool = false) {
        super.init()
        content.add(self, name: "paguroCompatibility")
        content.addUserScript(WKUserScript(source: Self.observationScript, injectionTime: .atDocumentStart,
            forMainFrameOnly: true, in: .page))
        let views = WKWebViewConfiguration()
        views.userContentController = content
        views.applicationNameForUserAgent = identity.applicationName
        session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
            serviceName: "Compatibility fixture", extensionViewConfiguration: views)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        if matchServiceIdentity { configuration.applicationNameForUserAgent = identity.applicationName }
        tab = WKWebView(frame: .zero, configuration: configuration)
        session.open(tab!)
        session.setActive(true)
    }

    func load(_ webExtension: WKWebExtension, id: UUID) throws {
        try session.load(webExtension, id: id)
        record(surface: "host", event: "controller.loaded", detail: "Required permissions granted. Optional permissions denied.")
    }

    func openPopup(id: UUID) throws {
        let context = try XCTUnwrap(session.contexts[id])
        context.userGesturePerformed(in: session)
        popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        record(surface: "host", event: "popup.requested", detail: "WebKit action popup view")
    }

    func evaluatePopup(_ script: String, label: String) {
        popup?.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { [weak self] result in
            switch result {
            case .success(let value): self?.record(surface: "popup", event: label, detail: value as? String ?? "No string result")
            case .failure(let error): self?.record(surface: "popup", event: label, detail: error.localizedDescription)
            }
        }
    }

    var isServiceFixtureReady: Bool { tab?.title == "Compatibility control" && tab?.isLoading == false }

    func loadServiceFixture() {
        tab?.loadHTMLString("<!doctype html><title>Compatibility control</title><style>body{background:white;color:black}</style><p>Bonjour</p><input name='username'><input type='password'>",
            baseURL: URL(string: "https://example.com/"))
    }

    func recordServiceState() {
        record(surface: "host", event: "service.fixtureReady", detail: String(isServiceFixtureReady))
    }

    func snapshotPopup() {
        popup?.evaluateJavaScript("JSON.stringify({state:document.readyState,text:document.body?.innerText?.slice(0,500),userAgent:navigator.userAgent})") { [weak self] result, error in
            self?.record(surface: "popup", event: "evaluation.completed",
                detail: result as? String ?? error?.localizedDescription ?? "No result")
        }
        record(surface: "host", event: "evaluation.requested", detail: "Popup state and public login text only")
    }

    func snapshotService(label: String) {
        tab?.evaluateJavaScript("""
            JSON.stringify({state:document.readyState,userAgent:navigator.userAgent,
                background:getComputedStyle(document.body).backgroundColor,color:getComputedStyle(document.body).color,
                darkreader:document.documentElement.getAttribute('data-darkreader-mode'),
                darkreaderStyles:document.querySelectorAll('style.darkreader').length})
            """) { [weak self] result, error in
            self?.record(surface: "service", event: label, detail: result as? String ?? error?.localizedDescription ?? "No result")
        }
    }

    func snapshotPages() async {
        var pending = session.pages.count
        for page in session.pages {
            record(surface: "host", event: "page.opened", detail: "visible=\(page.window?.isVisible == true), loading=\(page.pageView.isLoading), url=\(page.pageView.url?.absoluteString ?? "none")")
            page.pageView.evaluateJavaScript("JSON.stringify({title:document.title,text:document.body?.innerText?.slice(0,200)})") { [weak self] result, error in
                self?.record(surface: "page", event: "page.document", detail: result as? String ?? error?.localizedDescription ?? "No result")
                pending -= 1
            }
        }
        for _ in 0..<50 {
            if pending == 0 { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        record(surface: "host", event: "pages.count", detail: String(session.pages.count))
    }

    func report(package: FirefoxAddonPackage, identity: Identity) -> Report {
        Report(slug: package.slug, version: package.version, sha256: package.sha256,
            os: ProcessInfo.processInfo.operatingSystemVersionString,
            webKitVersion: Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown",
            identity: identity,
            configuredDocumentAdapters: [BrowserExtensionAPICompatibility.identifier],
            events: events, contextErrors: session.contexts.values.flatMap { $0.errors.prefix(16).map { String($0.localizedDescription.prefix(2_048)) } },
            recognizedRequiredPermissions: packagePermissions(optional: false),
            declaredPermissions: session.contexts.values.flatMap { $0.webExtension.manifest["permissions"] as? [String] ?? [] }.sorted(),
            optionalPermissions: packagePermissions(optional: true))
    }

    private func packagePermissions(optional: Bool) -> [String] {
        session.contexts.values.flatMap { context in
            (optional ? context.webExtension.optionalPermissions : context.webExtension.requestedPermissions).map(\.rawValue)
        }.sorted()
    }

    func close() {
        popup?.stopLoading()
        popup = nil
        tab?.stopLoading()
        tab = nil
        session.close()
        content.removeScriptMessageHandler(forName: "paguroCompatibility")
        content.removeAllUserScripts()
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: String] else { return }
        record(surface: body["surface"] ?? "unknown", event: body["event"] ?? "unknown", detail: body["detail"] ?? "")
    }

    private func record(surface: String, event: String, detail: String) {
        guard events.count < 160 else { return }
        let key = "\(surface):\(event):\(detail)"
        let count = repetitions[key, default: 0]
        repetitions[key] = count + 1
        guard count < 3 else { return }
        let duration = started.duration(to: .now).components
        let elapsed = Int(duration.seconds * 1_000 + duration.attoseconds / 1_000_000_000_000_000)
        events.append(Event(elapsedMilliseconds: elapsed, surface: String(surface.prefix(160)),
            event: String(event.prefix(80)), detail: String(detail.prefix(2_048))))
    }

    private static let observationScript = #"""
        (() => {
            const surface = location.pathname;
            const send = (event, detail) => {
                try { window.webkit.messageHandlers.paguroCompatibility.postMessage({surface,event,detail:String(detail).slice(0,2048)}); } catch {}
            };
            const repeated = new Map();
            const primitives = values => values.map(v => {
                if (typeof v === 'string' || typeof v === 'number') return String(v);
                if (v instanceof Error) return v.name + ': ' + v.message;
                return '';
            }).join(' ').slice(0,1024);
            for (const level of ['log','info','warn','error']) {
                const original = console[level];
                console[level] = function(...values) {
                    const detail = primitives(values);
                    const key = level + ':' + detail;
                    const count = repeated.get(key) ?? 0;
                    if (repeated.has(key) || repeated.size < 100) {
                        repeated.set(key, count + 1);
                        if (count < 3) send('console.' + level, detail);
                    }
                    return Reflect.apply(original, console, values);
                };
            }
            addEventListener('error', e => send('error', e.message + ' @ ' + e.filename.split('/').pop() + ':' + e.lineno));
            addEventListener('unhandledrejection', e => send('unhandledrejection', e.reason?.message ?? typeof e.reason));
            const paths = ['runtime.sendMessage','runtime.connect','runtime.getBackgroundPage','extension.getBackgroundPage',
                'storage.local','storage.session','storage.sync','storage.managed','alarms','tabs.query','tabs.create','tabs.executeScript','windows.getCurrent',
                'notifications','idle','runtime.sendNativeMessage','runtime.connectNative','scripting.executeScript',
                'scripting.ExecutionWorld','offscreen','sidePanel','userScripts','declarativeNetRequest','webRequest','contextMenus','management.getSelf'];
            const api = globalThis.browser ?? globalThis.chrome;
            const resolve = p => p.split('.').reduce((v,k) => v?.[k], api);
            send('document.start', JSON.stringify({userAgent:navigator.userAgent,APIs:Object.fromEntries(paths.map(p => [p,typeof resolve(p)]))}));
            document.addEventListener('DOMContentLoaded', () => send('document.ready', document.readyState));
            let count = 0;
            const heartbeat = setInterval(() => {
                send('heartbeat', JSON.stringify({state:document.readyState,textLength:document.body?.innerText?.length ?? 0,
                    scripts:document.scripts.length,container:typeof globalThis.bitwardenContainerService,
                    main:typeof globalThis.bitwardenMain,initSdk:typeof globalThis.initSdk,
                    resources:performance.getEntriesByType('resource').map(r => r.name.split('/').pop()).slice(-8)}));
                if (++count === 12) clearInterval(heartbeat);
            }, 1000);
        })();
        """#
}
#endif
