#if !APP_STORE
import AppKit
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionPermissionTests: XCTestCase {
    func testRealRequestsPersistOnlyInTheirAccountAndResetRevokesAccess() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        var prompts = 0
        fixture.session.permissionPrompt.presentSheet = { alert, _, reply in
            prompts += 1
            XCTAssertTrue(alert.informativeText.contains("Permission account"))
            reply(.alertFirstButtonReturn)
        }
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertTrue(result) }
        do { let result = try await fixture.request("{origins:['https://optional.example/*']}"); XCTAssertTrue(result) }
        XCTAssertEqual(prompts, 2)
        XCTAssertTrue(fixture.context.hasPermission(.clipboardWrite))
        XCTAssertTrue(fixture.context.hasAccess(to: URL(string: "https://optional.example/test")!))
        let cookie = try await fixture.page.callAsyncJavaScript("try { await browser.cookies.set({url:'https://optional.example/',name:'consent-fixture',value:'dummy',secure:true}); return (await browser.cookies.get({url:'https://optional.example/',name:'consent-fixture'})).value; } catch(error) { return String(error); }", contentWorld: .page) as? String
        XCTAssertEqual(cookie, "dummy")
        let other = ServiceInstance(label: "Other", url: fixture.service.url)
        fixture.manager.assignableServiceIDs = { [fixture.service.id, other.id] }
        XCTAssertTrue(fixture.manager.assign(fixture.id, to: [fixture.service.id, other.id]))
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        fixture.manager.configure(config, for: other)
        let otherContext = try XCTUnwrap(config.webExtensionController?.extensionContexts.first)
        XCTAssertFalse(otherContext.hasPermission(.clipboardWrite))
        XCTAssertFalse(otherContext.hasAccess(to: URL(string: "https://optional.example/test")!))
        fixture.manager.release(fixture.service.id)
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        restored.assignableServiceIDs = { [fixture.service.id] }
        try await restored.restore()
        let reopened = WKWebViewConfiguration()
        reopened.websiteDataStore = .nonPersistent()
        restored.configure(reopened, for: fixture.service)
        let context = try XCTUnwrap(reopened.webExtensionController?.extensionContexts.first)
        XCTAssertTrue(context.hasPermission(.clipboardWrite))
        XCTAssertTrue(context.hasAccess(to: URL(string: "https://optional.example/test")!))
        restored.resetOptionalAccess(fixture.id)
        XCTAssertFalse(context.hasPermission(.clipboardWrite))
        XCTAssertFalse(context.hasAccess(to: URL(string: "https://optional.example/test")!))
        XCTAssertTrue(context.hasPermission(.storage), "Reset must keep installation consent")
        XCTAssertTrue(restored.optionalAccess.isEmpty)
    }

    func testDenyIsRememberedWhileCancelDoesNotSaveAChoice() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        var prompts = 0
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in prompts += 1; reply(.alertThirdButtonReturn) }
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertFalse(result) }
        XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in prompts += 1; reply(.alertSecondButtonReturn) }
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertFalse(result) }
        XCTAssertEqual(prompts, 2)
        XCTAssertEqual(fixture.manager.optionalAccess[fixture.id.uuidString]?[fixture.service.id.uuidString]?.deniedPermissions, ["clipboardWrite"])
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertFalse(result) }
        XCTAssertEqual(prompts, 2)
        XCTAssertFalse(fixture.context.hasPermission(.clipboardWrite))
        let contains = try await fixture.page.callAsyncJavaScript("return await browser.permissions.contains({permissions:['clipboardWrite']});", contentWorld: .page) as? Bool
        XCTAssertEqual(contains, false)
        fixture.manager.resetOptionalAccess(fixture.id)
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in prompts += 1; reply(.alertFirstButtonReturn) }
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertTrue(result) }
        XCTAssertEqual(prompts, 3)
    }

    func testCombinedRequestAndRealNativeSheetConsent() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        var prompts = 0
        fixture.session.permissionPrompt.presentSheet = { alert, window, reply in
            prompts += 1
            alert.beginSheetModal(for: window, completionHandler: reply)
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertTrue(alert.window.isVisible)
                XCTAssertEqual(alert.buttons.map(\.title), ["Allow", "Deny", "Cancel"])
                if let view = alert.window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let image = NSImage(size: view.bounds.size)
                    image.addRepresentation(bitmap)
                    let attachment = XCTAttachment(image: image)
                    attachment.name = "Optional access native sheet \(prompts)"
                    attachment.lifetime = .keepAlways
                    self.add(attachment)
                }
                alert.buttons[0].performClick(nil)
            }
        }
        let result = try await fixture.request("{permissions:['clipboardWrite'],origins:['https://optional.example/*']}")
        XCTAssertTrue(result)
        XCTAssertEqual(prompts, 2)
        XCTAssertTrue(fixture.context.hasPermission(.clipboardWrite))
        XCTAssertTrue(fixture.context.hasAccess(to: URL(string: "https://optional.example/test")!))
    }

    func testAccountSwitchAndLockCancelPendingConsentAndIgnoreLateAllow() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        for lock in [false, true] {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            fixture.session.permissionPrompt.presentSheet = { _, _, reply in
                if lock { fixture.manager.setLocked(true) } else { fixture.manager.didActivate(nil) }
                reply(.alertFirstButtonReturn)
            }
            do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertFalse(result) }
            XCTAssertFalse(fixture.context.hasPermission(.clipboardWrite))
            XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
        }
    }

    func testRequestingActionPopupSurvivesNativeConsent() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        try await PopupFocus.requireActiveApp()
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let action = try XCTUnwrap(fixture.context.action(for: fixture.session))
        fixture.session.perform(fixture.id, from: try XCTUnwrap(fixture.window.contentView))
        for _ in 0..<150 {
            if action.popupPopover?.isShown == true { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        let popover = try XCTUnwrap(action.popupPopover)
        XCTAssertTrue(popover.isShown)
        let popup = try XCTUnwrap(action.popupWebView)
        for _ in 0..<150 {
            if popup.title == "Extension probe", !popup.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        fixture.session.permissionPrompt.presentSheet = { alert, window, reply in
            alert.beginSheetModal(for: window, completionHandler: reply)
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(50))
                XCTAssertTrue(popover.isShown)
                alert.buttons[0].performClick(nil)
            }
        }
        fixture.context.userGesturePerformed(in: fixture.session)
        let granted = try await popup.callAsyncJavaScript("return await browser.permissions.request({permissions:['clipboardWrite']});", contentWorld: .page) as? Bool
        XCTAssertEqual(granted, true)
        XCTAssertTrue(popover.isShown)
        XCTAssertEqual(popover.behavior, .transient)
    }

    func testCancelledSheetCannotApproveItsReplacement() async throws {
        let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.close() }
        let prompt = BrowserExtensionPermissionPrompt()
        var replies: [(NSApplication.ModalResponse) -> Void] = []
        // Retain the synthetic sheets so stale callbacks can still be delivered.
        var alerts: [NSAlert] = []
        prompt.presentSheet = { alert, _, reply in alerts.append(alert); replies.append(reply) }
        let request = BrowserExtensionPermissionRequest(extensionName: "Synthetic", serviceName: "A", permissions: ["clipboardWrite"], origins: [])
        let first = Task { await prompt.request(request, in: window) }
        for _ in 0..<100 { if replies.count == 1 { break }; await Task.yield() }
        XCTAssertEqual(replies.count, 1)
        prompt.cancel()
        let cancelled = await first.value
        XCTAssertEqual(cancelled, .cancel)
        let second = Task { await prompt.request(request, in: window) }
        for _ in 0..<100 { if replies.count == 2 { break }; await Task.yield() }
        XCTAssertEqual(replies.count, 2)
        guard replies.count == 2 else { prompt.cancel(); _ = await second.value; return }
        replies[0](.alertFirstButtonReturn)
        XCTAssertTrue(prompt.isPresenting, "A stale response must not finish the new sheet")
        replies[1](.alertSecondButtonReturn)
        let denied = await second.value
        XCTAssertEqual(denied, .deny)
        XCTAssertEqual(alerts.count, 2)
    }

    func testNativeExplicitDenialControlRecordsRequestResultWithoutGrantingAccess() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.context.setPermissionStatus(.deniedExplicitly, for: .clipboardWrite)
        fixture.session.permissionPrompt.presentSheet = { _, _, _ in XCTFail("An explicit native denial should not prompt") }
        let reported = try await fixture.request("{permissions:['clipboardWrite']}")
        let contains = try await fixture.page.callAsyncJavaScript("return await browser.permissions.contains({permissions:['clipboardWrite']});", contentWorld: .page) as? Bool
        XCTAssertFalse(fixture.context.hasPermission(.clipboardWrite))
        XCTAssertEqual(contains, false)
        let evidence = XCTAttachment(string: "Native explicit denial: request=\(reported), contains=\(contains == true), granted=\(fixture.context.hasPermission(.clipboardWrite))")
        evidence.name = "Native explicit denial control"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    func testSavingFailureDeniesTheGrant() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in reply(.alertFirstButtonReturn) }
        let index = fixture.directory.appending(path: "library.json")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertFalse(result) }
        XCTAssertFalse(fixture.context.hasPermission(.clipboardWrite))
        XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
        XCTAssertNotNil(fixture.manager.errorMessage)
    }

    func testRevocationStillPersistsWhileLocked() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in reply(.alertFirstButtonReturn) }
        let allowed = try await fixture.request("{permissions:['clipboardWrite']}")
        XCTAssertTrue(allowed)
        fixture.manager.setLocked(true)
        fixture.context.setPermissionStatus(.unknown, for: .clipboardWrite)
        for _ in 0..<100 {
            if fixture.manager.optionalAccess.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
    }

    func testPermissionRemovalAndPackageChangesDoNotRestoreOldGrants() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.session.permissionPrompt.presentSheet = { _, _, reply in reply(.alertFirstButtonReturn) }
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertTrue(result) }
        _ = try await fixture.page.callAsyncJavaScript("return await browser.permissions.remove({permissions:['clipboardWrite']});", contentWorld: .page)
        for _ in 0..<100 {
            if fixture.manager.optionalAccess.isEmpty { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
        do { let result = try await fixture.request("{permissions:['clipboardWrite']}"); XCTAssertTrue(result) }
        try await fixture.manager.prepare(BrowserExtensionFixture.package(version: "2.0"))
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: [fixture.service.id]))
        XCTAssertTrue(fixture.manager.optionalAccess.isEmpty)
    }

    func testURLDelegateShowsOnlyTheOriginAndRejectsForeignTabsAndCredentials() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        var prompts = 0
        fixture.context.userGesturePerformed(in: fixture.session)
        fixture.session.permissionPrompt.presentSheet = { alert, _, reply in
            prompts += 1
            let details = (alert.accessoryView as? NSScrollView)?.documentView as? NSTextView
            XCTAssertEqual(details?.string, "Website: https://optional.example/*")
            reply(.alertFirstButtonReturn)
        }
        let url = URL(string: "https://optional.example/path?query=dummy")!
        let allowed = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissionToAccess: [url], in: fixture.session, for: fixture.context)
        XCTAssertEqual(allowed.0, [url])
        XCTAssertEqual(fixture.manager.optionalAccess[fixture.id.uuidString]?[fixture.service.id.uuidString]?.origins, ["https://optional.example/*"])
        let foreign = ServiceExtensionSession(serviceID: UUID(), storeID: UUID(), dataStore: .nonPersistent())
        defer { foreign.close() }
        let rejected = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissions: [.clipboardWrite], in: foreign, for: fixture.context)
        XCTAssertTrue(rejected.0.isEmpty)
        let unsafe = URL(string: "https://user:dummy@optional.example/")!
        let invalid = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissionToAccess: [unsafe], in: fixture.session, for: fixture.context)
        XCTAssertTrue(invalid.0.isEmpty)
        let huge = URL(string: "https://optional.example/" + String(repeating: "x", count: 8_193))!
        let oversized = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissionToAccess: [huge], in: fixture.session, for: fixture.context)
        XCTAssertTrue(oversized.0.isEmpty)
        XCTAssertEqual(prompts, 1)
    }

    func testUndeclaredForeignAndInactiveRequestsDoNotPrompt() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.session.permissionPrompt.presentSheet = { _, _, _ in XCTFail("Invalid requests must not prompt") }
        let result = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissions: [.nativeMessaging], in: fixture.session, for: fixture.context)
        XCTAssertTrue(result.0.isEmpty)
        let pattern = try WKWebExtension.MatchPattern(string: "https://undeclared.example/*")
        let origins = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissionMatchPatterns: [pattern], in: fixture.session, for: fixture.context)
        XCTAssertTrue(origins.0.isEmpty)
        fixture.manager.didActivate(nil)
        let inactive = await fixture.session.webExtensionController(fixture.session.controller, promptForPermissions: [.clipboardWrite], in: fixture.session, for: fixture.context)
        XCTAssertTrue(inactive.0.isEmpty)
    }

    @available(macOS 15.4, *)
    private func makeFixture() async throws -> Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let manager = BrowserExtensionManager(directory: directory)
        try await manager.restore()
        let service = ServiceInstance(label: "Permission account", url: "https://example.com/")
        manager.assignableServiceIDs = { [service.id] }
        try await manager.prepare(BrowserExtensionFixture.package())
        XCTAssertTrue(manager.installPreview(serviceIDs: [service.id]))
        let id = try XCTUnwrap(manager.records.first?.id)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        manager.configure(configuration, for: service)
        let session = try XCTUnwrap(configuration.webExtensionController?.delegate as? ServiceExtensionSession)
        let context = try XCTUnwrap(session.contexts[id])
        let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 400), configuration: configuration)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        manager.didCreate(view, for: service.id)
        manager.didActivate(service.id)
        let page = WKWebView(frame: view.frame, configuration: try XCTUnwrap(context.webViewConfiguration))
        page.load(URLRequest(url: context.baseURL.appending(path: "probe.html")))
        for _ in 0..<150 {
            if page.title == "Extension probe", !page.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        return Fixture(manager: manager, service: service, session: session, context: context, page: page,
            window: window, directory: directory, id: id)
    }

    @available(macOS 15.4, *)
    @MainActor
    private struct Fixture {
        let manager: BrowserExtensionManager
        let service: ServiceInstance
        let session: ServiceExtensionSession
        let context: WKWebExtensionContext
        let page: WKWebView
        let window: NSWindow
        let directory: URL
        let id: UUID
        func request(_ object: String) async throws -> Bool {
            context.userGesturePerformed(in: session)
            return try await page.callAsyncJavaScript("return await browser.permissions.request(\(object));", contentWorld: .page) as? Bool == true
        }
        func close() {
            manager.shutdown()
            page.stopLoading()
            (window.contentView as? WKWebView)?.stopLoading()
            window.close()
            try? FileManager.default.removeItem(at: directory)
        }
    }
}
#endif
