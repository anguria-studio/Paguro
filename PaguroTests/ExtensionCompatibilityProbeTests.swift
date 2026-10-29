#if !APP_STORE
import Foundation
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class ExtensionCompatibilityProbeTests: XCTestCase {
    func testEmptyContentScriptArrayAndOmittedFieldParserControl() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        var results: [String: [String]] = [:]
        for empty in [false, true] {
            var manifest: [String: Any] = ["manifest_version": 2, "name": "Manifest parser control", "version": "1.0",
                "description": "Tests empty and omitted content script declarations."]
            if empty { manifest["content_scripts"] = [String]() }
            let data = BrowserExtensionFixture.archive([("manifest.json", try JSONSerialization.data(withJSONObject: manifest))])
            let file = FileManager.default.temporaryDirectory.appending(path: "manifest-control-\(UUID().uuidString).zip")
            try data.write(to: file)
            defer { try? FileManager.default.removeItem(at: file) }
            let webExtension = try await WKWebExtension(resourceBaseURL: file)
            results[empty ? "empty" : "omitted"] = webExtension.errors.map(\.localizedDescription)
            if !empty { XCTAssertTrue(webExtension.errors.isEmpty) }
        }
        let data = try JSONEncoder().encode(results)
        print("EXTENSION MANIFEST CONTROL: \(String(decoding: data, as: UTF8.self))")
    }

    func testManifestV3WorkerMessagingStorageAndScriptInjection() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let package = try BrowserExtensionFixture.package(manifestVersion: 3, additionalPermissions: ["scripting", "alarms"], backgroundScript: """
            browser.runtime.onMessage.addListener(() => {
                let lateListener;
                try { browser.tabs.onUpdated.addListener(() => {}); lateListener = 'registered'; }
                catch (error) { lateListener = error.message; }
                return Promise.resolve({working:true,lateListener});
            });
            """)
        let file = FileManager.default.temporaryDirectory.appending(path: "worker-control-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        XCTAssertTrue(webExtension.errors.isEmpty, "\(webExtension.errors)")
        let probe = ExtensionCompatibilityProbe(identity: .webKit)
        defer { probe.close() }
        let id = UUID()
        try probe.load(webExtension, id: id)
        probe.loadServiceFixture()
        for _ in 0..<100 {
            if probe.isServiceFixtureReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(probe.isServiceFixtureReady)
        probe.session.didNavigate()
        try probe.openPopup(id: id)
        try await Task.sleep(for: .milliseconds(250))
        probe.evaluatePopup("""
            const response = await browser.runtime.sendMessage({control:true});
            await browser.storage.local.set({workerControl:'stored'});
            const storage = await browser.storage.local.get('workerControl');
            const tabs = await browser.tabs.query({active:true,currentWindow:true});
            const injection = await browser.scripting.executeScript({target:{tabId:tabs[0].id},world:'ISOLATED',func:() => 'worker-injection'});
            return JSON.stringify({message:response.working,storage:storage.workerControl,injection:injection[0].result,
                executionWorldType:typeof browser.scripting.ExecutionWorld,managedStorageType:typeof browser.storage.managed,
                lateListener:response.lateListener});
            """, label: "worker.result")
        for _ in 0..<100 {
            if probe.report(package: package, identity: .webKit).events.contains(where: { $0.event == "worker.result" }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let report = probe.report(package: package, identity: .webKit)
        let result = try XCTUnwrap(report.events.first { $0.event == "worker.result" })
        let values = try JSONSerialization.jsonObject(with: Data(result.detail.utf8)) as? [String: Any]
        XCTAssertEqual(values?["message"] as? Bool, true, result.detail)
        XCTAssertEqual(values?["storage"] as? String, "stored")
        XCTAssertEqual(values?["injection"] as? String, "worker-injection")
        print("EXTENSION WORKER CONTROL: \(result.detail)")
    }

    func testInjectedViewConfigurationCannotReplaceTheAccountStore() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let store = WKWebsiteDataStore.nonPersistent()
        let supplied = WKWebViewConfiguration()
        supplied.websiteDataStore = .nonPersistent()
        let session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
            extensionViewConfiguration: supplied)
        defer { session.close() }
        XCTAssertTrue(session.controller.configuration.defaultWebsiteDataStore === store)
        XCTAssertTrue(session.controller.configuration.webViewConfiguration.websiteDataStore === store)
    }

    func testProbeObservesBackgroundAndPopupWithoutReplacingBrowserAPIs() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let package = try BrowserExtensionFixture.package(additionalPermissions: ["alarms", "idle", "notifications"], backgroundScript: """
            globalThis.paguroMarker = 'background-ready';
            console.info('Background control ready');
            browser.runtime.onMessage.addListener(() => Promise.resolve({working:true}));
            browser.runtime.onConnect.addListener(port => port.onMessage.addListener(() => port.postMessage({working:true})));
            """)
        let file = FileManager.default.temporaryDirectory.appending(path: "probe-control-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let probe = ExtensionCompatibilityProbe(identity: .webKit)
        defer { probe.close() }
        let id = UUID()
        try probe.load(webExtension, id: id)
        probe.loadServiceFixture()
        for _ in 0..<100 {
            if probe.isServiceFixtureReady { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(probe.isServiceFixtureReady)
        probe.session.didNavigate()
        try probe.openPopup(id: id)
        for _ in 0..<100 {
            if probe.report(package: package, identity: .webKit).events.contains(where: { $0.surface == "/probe.html" && $0.event == "document.ready" }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        probe.evaluatePopup("""
            return await (async () => {
                const response = await browser.runtime.sendMessage({control:true});
                await browser.storage.local.set({probeControl:'isolated'});
                const storage = await browser.storage.local.get('probeControl');
                const background = await browser.runtime.getBackgroundPage();
                await browser.storage.session.set({control:'session-value'});
                const sessionValue = (await browser.storage.session.get('control')).control;
                browser.alarms.create('control', {delayInMinutes:60});
                const alarm = await browser.alarms.get('control');
                const tabs = await browser.tabs.query({active:true,currentWindow:true});
                const injection = await browser.tabs.executeScript(tabs[0].id, {code:"'dynamic-ready'"});
                const port = browser.runtime.connect({name:'control'});
                const portReply = await new Promise((resolve,reject) => {
                    const timer = setTimeout(() => reject(new Error('Port control timed out')),1000);
                    port.onMessage.addListener(reply => { clearTimeout(timer); resolve(reply.working); });
                    port.postMessage({control:true});
                });
                port.disconnect();
                console.info('Control log', {sensitive:'do not record arbitrary objects'});
                console.error(new Error('Synthetic diagnostic detail'));
                return JSON.stringify({message:response.working,storage:storage.probeControl,background:background?.paguroMarker,
                    session:sessionValue,alarm:alarm.name,dynamic:injection[0],port:portReply,
                    idle:typeof browser.idle,notifications:typeof browser.notifications});
            })();
            """, label: "control.result")
        for _ in 0..<100 {
            if probe.report(package: package, identity: .webKit).events.contains(where: { $0.event == "control.result" }) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let report = probe.report(package: package, identity: .webKit)
        XCTAssertTrue(report.events.contains { $0.event == "console.info" && $0.detail == "Background control ready" })
        let result = try XCTUnwrap(report.events.first { $0.event == "control.result" })
        let values = try JSONSerialization.jsonObject(with: Data(result.detail.utf8)) as? [String: Any]
        XCTAssertEqual(values?["message"] as? Bool, true)
        XCTAssertEqual(values?["storage"] as? String, "isolated")
        XCTAssertEqual(values?["background"] as? String, "background-ready")
        XCTAssertEqual(values?["session"] as? String, "session-value")
        XCTAssertEqual(values?["alarm"] as? String, "control")
        XCTAssertEqual(values?["dynamic"] as? String, "dynamic-ready")
        XCTAssertEqual(values?["port"] as? Bool, true)
        XCTAssertNotNil(values?["idle"] as? String)
        XCTAssertNotNil(values?["notifications"] as? String)
        XCTAssertTrue(report.declaredPermissions.contains("idle"))
        XCTAssertTrue(report.declaredPermissions.contains("notifications"))
        XCTAssertTrue(report.events.contains { $0.detail.contains("Synthetic diagnostic detail") })
        XCTAssertFalse(report.events.contains { $0.detail.contains("do not record arbitrary objects") })
    }
}
#endif
