#if !APP_STORE
import Foundation
import WebKit
import XCTest
@testable import Paguro

/// Use synthetic packages to check browser contracts without vendor accounts.
@MainActor
final class ExtensionAPIContractTests: XCTestCase {
    func testConstantsRespectPermissionsAndBackgroundKind() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        var reports: [[String: Any]] = []
        for version in [2, 3] {
            for permission in [false, true] {
                let fixture = try await APIContractFixture(version: version, scriptingPermission: permission)
                defer { fixture.close() }
                let popup = try await fixture.popup()
                let value = try await popup.callAsyncJavaScript("""
                    const background = await browser.runtime.sendMessage({contract:true});
                    return JSON.stringify({background, popup: {
                        namespace: typeof browser.scripting,
                        execute: typeof browser.scripting?.executeScript,
                        originalMethod: browser.scripting?.executeScript === globalThis.contractOriginalExecute,
                        worlds: browser.scripting?.ExecutionWorld ?? null,
                        chromeWorlds: chrome.scripting?.ExecutionWorld ?? null
                    }});
                    """, contentWorld: .page)
                let text = try XCTUnwrap(value as? String)
                let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
                let background = try XCTUnwrap(result["background"] as? [String: Any])
                let front = try XCTUnwrap(result["popup"] as? [String: Any])
                XCTAssertEqual(front["originalMethod"] as? Bool, true)
                XCTAssertEqual(background["document"] as? Bool, version == 2)
                if permission {
                    XCTAssertEqual(front["worlds"] as? [String: String], Self.worlds)
                    XCTAssertEqual(front["chromeWorlds"] as? [String: String], Self.worlds)
                    XCTAssertEqual(background["execute"] as? String, "function")
                    if version == 2 {
                        XCTAssertEqual(background["worlds"] as? [String: String], Self.worlds)
                        XCTAssertEqual(background["originalMethod"] as? Bool, true)
                    }
                } else {
                    XCTAssertEqual(front["namespace"] as? String, "undefined")
                    XCTAssertEqual(background["namespace"] as? String, "undefined")
                }
                reports.append(["manifestVersion": version, "scriptingPermission": permission, "result": result])
            }
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: reports, options: [.sortedKeys]),
            uniformTypeIdentifier: "public.json")
        attachment.name = "execution-world-contracts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testNativeExecutionKeepsMainAndIsolatedWorldsSeparate() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        for version in [2, 3] {
            let fixture = try await APIContractFixture(version: version, scriptingPermission: true)
            defer { fixture.close() }
            let popup = try await fixture.popup()
            try await fixture.waitForService()
            let value = try await popup.callAsyncJavaScript("""
                const [tab] = await browser.tabs.query({active:true,currentWindow:true});
                const worlds = browser.scripting.ExecutionWorld;
                const main = await browser.scripting.executeScript({target:{tabId:tab.id},world:worlds.MAIN,func:() => {
                    globalThis.contractWorld = 'main';
                    document.documentElement.dataset.contractWorld = 'shared-document';
                    return {extensionID:globalThis.browser?.runtime?.id ?? null, storage:typeof globalThis.browser?.storage, scripting:typeof globalThis.browser?.scripting};
                }});
                const isolated = await browser.scripting.executeScript({target:{tabId:tab.id},world:worlds.ISOLATED,func:() => {
                    const result = {global:globalThis.contractWorld ?? null, shared:document.documentElement.dataset.contractWorld};
                    globalThis.contractWorld = 'isolated';
                    return result;
                }});
                const mainAgain = await browser.scripting.executeScript({target:{tabId:tab.id},world:worlds.MAIN,
                    func:() => globalThis.contractWorld});
                let invalidRejected = false;
                try { await browser.scripting.executeScript({target:{tabId:tab.id},world:'INVALID',func:() => true}); }
                catch { invalidRejected = true; }
                return JSON.stringify({mainAPI:main[0].result,isolated:isolated[0].result,
                    mainAgain:mainAgain[0].result,invalidRejected});
                """, contentWorld: .page)
            let text = try XCTUnwrap(value as? String)
            let result = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            let isolated = try XCTUnwrap(result["isolated"] as? [String: Any])
            let mainAPI = try XCTUnwrap(result["mainAPI"] as? [String: Any])
            XCTAssertTrue(mainAPI["extensionID"] is NSNull, text)
            XCTAssertEqual(mainAPI["storage"] as? String, "undefined", text)
            XCTAssertEqual(mainAPI["scripting"] as? String, "undefined", text)
            XCTAssertTrue(isolated["global"] is NSNull, text)
            XCTAssertEqual(isolated["shared"] as? String, "shared-document", text)
            XCTAssertEqual(result["mainAgain"] as? String, "main", text)
            XCTAssertEqual(result["invalidRejected"] as? Bool, true, text)
            let pageWorld = try await fixture.view.evaluateJavaScript("globalThis.contractWorld") as? String
            XCTAssertEqual(pageWorld, "main")
        }
    }

    func testAccountOwnedExtensionPageReceivesConstantsWithoutAServiceHook() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await APIContractFixture(version: 2, scriptingPermission: true)
        defer { fixture.close() }
        let context = try XCTUnwrap(fixture.session.contexts[fixture.id])
        let url = try XCTUnwrap(context.optionsPageURL)
        context.userGesturePerformed(in: fixture.session)
        let page = try fixture.session.openPage(url, for: context)
        for _ in 0..<100 {
            if page.pageView.title == "Extension probe", !page.pageView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let worlds = try await page.pageView.evaluateJavaScript("JSON.stringify(browser.scripting.ExecutionWorld)") as? String
        let result = try JSONSerialization.jsonObject(with: Data(try XCTUnwrap(worlds).utf8)) as? [String: String]
        XCTAssertEqual(result, Self.worlds)
        let source = BrowserExtensionAPICompatibility.executionWorldConstants
        XCTAssertFalse(fixture.view.configuration.userContentController.userScripts.contains { $0.source == source })
        let ordinary = fixture.session.pageConfiguration(for: URL(string: "https://example.com/")!, context: context)
        XCTAssertFalse(ordinary.userContentController.userScripts.contains { $0.source == source })
    }

    func testScriptingStillRejectsAnUnpermittedHost() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await APIContractFixture(version: 2, scriptingPermission: true, serviceURL: "https://ungranted.invalid/")
        defer { fixture.close() }
        let popup = try await fixture.popup()
        try await fixture.waitForService()
        let rejected = try await popup.callAsyncJavaScript("""
            const [tab] = await browser.tabs.query({active:true,currentWindow:true});
            try {
                await browser.scripting.executeScript({target:{tabId:tab.id},world:browser.scripting.ExecutionWorld.MAIN,
                    func:() => { globalThis.contractUnauthorized = true; }});
                return false;
            } catch { return true; }
            """, contentWorld: .page) as? Bool
        XCTAssertEqual(rejected, true)
        let unauthorized = try await fixture.view.evaluateJavaScript("typeof globalThis.contractUnauthorized") as? String
        XCTAssertEqual(unauthorized, "undefined")
    }

    func testAdapterPreservesAnExistingNativeConstantObject() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await APIContractFixture(version: 2, scriptingPermission: true, seedConstants: true)
        defer { fixture.close() }
        let popup = try await fixture.popup()
        let same = try await popup.evaluateJavaScript("browser.scripting.ExecutionWorld === globalThis.contractOriginalWorld") as? Bool
        XCTAssertEqual(same, true)
    }

    func testConfigurationIsIdempotentAndOrdinaryPagesAreUntouched() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(WKUserScript(source: "globalThis.browser={scripting:{executeScript(){}}};",
            injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        BrowserExtensionAPICompatibility.configure(configuration)
        BrowserExtensionAPICompatibility.configure(configuration)
        XCTAssertEqual(configuration.userContentController.userScripts.count, 2)
        let view = WKWebView(frame: .zero, configuration: configuration)
        defer { view.stopLoading() }
        view.loadHTMLString("<!doctype html><title>Ordinary page</title>", baseURL: URL(string: "https://example.com/"))
        for _ in 0..<100 {
            if view.title == "Ordinary page", !view.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let type = try await view.evaluateJavaScript("typeof browser.scripting.ExecutionWorld") as? String
        XCTAssertEqual(type, "undefined")
    }

    private static let worlds = ["MAIN": "MAIN", "ISOLATED": "ISOLATED"]
}

@available(macOS 15.4, *)
@MainActor
private final class APIContractFixture {
    let session: ServiceExtensionSession
    let view: WKWebView
    let id = UUID()
    let file: URL

    init(version: Int, scriptingPermission: Bool, serviceURL: String = "https://example.com/", seedConstants: Bool = false) async throws {
        let script = """
            const startup = {
                document: typeof document !== 'undefined',
                namespace: typeof browser.scripting,
                execute: typeof browser.scripting?.executeScript,
                originalMethod: browser.scripting?.executeScript === globalThis.contractOriginalExecute,
                worlds: browser.scripting?.ExecutionWorld ?? null
            };
            browser.runtime.onMessage.addListener(() => Promise.resolve(startup));
            """
        let package = try BrowserExtensionFixture.package(manifestVersion: version,
            additionalPermissions: scriptingPermission ? ["scripting"] : [], backgroundScript: script)
        file = FileManager.default.temporaryDirectory.appending(path: "api-contract-\(UUID().uuidString).zip")
        try package.data.write(to: file)
        let webExtension = try await WKWebExtension(resourceBaseURL: file)
        let views = WKWebViewConfiguration()
        views.userContentController.addUserScript(WKUserScript(source: """
            globalThis.contractOriginalExecute = globalThis.browser?.scripting?.executeScript;
            if (\(seedConstants) && browser.scripting && !('ExecutionWorld' in browser.scripting)) {
                Object.defineProperty(browser.scripting, 'ExecutionWorld', {value:{MAIN:'MAIN',ISOLATED:'ISOLATED',EXISTING:'keep'}});
            }
            globalThis.contractOriginalWorld = globalThis.browser?.scripting?.ExecutionWorld;
            """, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        let store = WKWebsiteDataStore.nonPersistent()
        session = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: store,
            extensionViewConfiguration: views)
        try session.load(webExtension, id: id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.webExtensionController = session.controller
        view = WKWebView(frame: .zero, configuration: configuration)
        session.open(view)
        session.setActive(true)
        view.loadHTMLString("<!doctype html><title>API contract</title>", baseURL: URL(string: serviceURL))
    }

    func popup() async throws -> WKWebView {
        let context = try XCTUnwrap(session.contexts[id])
        context.userGesturePerformed(in: session)
        let popup = try XCTUnwrap(context.action(for: session)?.popupWebView)
        for _ in 0..<100 {
            if popup.title == "Extension probe", !popup.isLoading { return popup }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.coderInvalidValue)
    }

    func waitForService() async throws {
        for _ in 0..<100 {
            if view.title == "API contract", !view.isLoading { session.didNavigate(); return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CocoaError(.coderInvalidValue)
    }

    func close() {
        session.contexts[id]?.action(for: session)?.popupWebView?.stopLoading()
        view.stopLoading()
        session.close()
        try? FileManager.default.removeItem(at: file)
    }
}
#endif
