import XCTest
import AppKit
import JavaScriptCore
import WebKit
@testable import Atoll

final class NotificationBridgeTests: XCTestCase {
    // MARK: - The notification interception script

    /// Pulls the injected notification script out of a configured controller.
    @MainActor
    func notificationScriptSource() throws -> String {
        let manager = UserScriptManager()
        let controller = WKUserContentController()
        manager.installUserScripts(
            for: ModelFixtures.service(label: "Slack", catalogID: "slack"),
            customCSS: nil,
            stayActiveInBackground: false,
            on: controller
        )
        return try XCTUnwrap(
            controller.userScripts.map(\.source).first { $0.contains("atollNotification") },
            "no notification interception script was installed"
        )
    }

    /// The shim replaces `window.Notification`, so it has to keep the API it
    /// replaced: instances must still satisfy `instanceof`, and the statics the
    /// original carried must survive. The first version dropped both.
    @MainActor
    func testNotificationShimKeepsPrototypeAndStatics() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }

        context.evaluateScript("var window = this; var posted = [];")
        context.setObject(record, forKeyedSubscript: "atollPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { atollNotification: { postMessage: function(m) { atollPost(m); } } } };
            function Notification(title, options) { this.title = title; }
            Notification.prototype.close = function() { this.closed = true; };
            Notification.maxActions = 2;
            Notification.permission = 'default';
            window.Notification = Notification;
            """)

        context.evaluateScript(try notificationScriptSource())

        XCTAssertEqual(
            context.evaluateScript("(new window.Notification('hi', {body: 'b'})) instanceof window.Notification")?.toBool(),
            true,
            "instanceof must still hold — a site that feature-detects this way breaks otherwise"
        )
        XCTAssertEqual(
            context.evaluateScript("typeof (new window.Notification('hi')).close")?.toString(), "function",
            "the prototype's methods must still be reachable"
        )
        XCTAssertEqual(
            context.evaluateScript("window.Notification.maxActions")?.toInt32(), 2,
            "statics the original carried must be copied across"
        )
        XCTAssertEqual(
            context.evaluateScript("window.Notification.permission")?.toString(), "granted",
            "and Atoll's own overrides must win over the copied ones"
        )
        XCTAssertEqual(posted.count, 2, "each constructed notification is forwarded once")
        XCTAssertTrue(posted[0].contains("\"body\":\"b\""), "the payload must carry the body")
    }

    /// The path that was not covered at all. Web apps raise notifications
    /// through the service worker registration rather than the constructor, so
    /// without this they never reached Atoll.
    @MainActor
    func testNotificationShimForwardsServiceWorkerNotifications() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }

        context.evaluateScript("var window = this;")
        context.setObject(record, forKeyedSubscript: "atollPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { atollNotification: { postMessage: function(m) { atollPost(m); } } } };
            var showCalls = 0;
            function ServiceWorkerRegistration() {}
            ServiceWorkerRegistration.prototype.showNotification = function(t, o) { showCalls++; return 'orig'; };
            window.ServiceWorkerRegistration = ServiceWorkerRegistration;
            """)

        context.evaluateScript(try notificationScriptSource())

        let returned = context.evaluateScript("""
            (new ServiceWorkerRegistration()).showNotification('Nico', {body: 'sent a message'});
            """)?.toString()
        XCTAssertEqual(returned, "orig", "the original call must still run and its result be passed through")
        XCTAssertEqual(context.evaluateScript("showCalls")?.toInt32(), 1, "exactly once — not swallowed, not doubled")
        XCTAssertEqual(posted.count, 1, "and the notification must reach Atoll")
        XCTAssertTrue(posted[0].contains("\"title\":\"Nico\""))
    }

    /// A page that has torn the bridge down must not take the site's own
    /// notification call with it.
    @MainActor
    func testNotificationShimSurvivesAMissingBridge() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        context.evaluateScript("""
            var window = this;
            window.webkit = undefined;
            function Notification(title) { this.title = title; }
            window.Notification = Notification;
            """)
        context.evaluateScript(try notificationScriptSource())

        XCTAssertEqual(
            context.evaluateScript("(new window.Notification('hi')).title")?.toString(), "hi",
            "the original constructor must still run when the bridge is gone"
        )
        XCTAssertNil(context.exception, "and no exception must escape into the page")
    }

    @MainActor
    func testNativeNotificationIncludesServiceIdentity() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 32,
            pixelsHigh: 32,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let iconData = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let service = ModelFixtures.service(label: "Slack", catalogID: nil)
        service.customIconData = iconData
        let iconURL = try XCTUnwrap(NotificationAttachmentStore.prepareServiceIcon(for: service))

        let payload = NotificationPayload(
            title: "New message",
            body: "A short body",
            icon: "https://untrusted.example/icon.png",
            tag: "message-1",
            serviceID: service.id.uuidString
        )
        let content = NativeNotificationContentBuilder.makeContent(
            payload: payload,
            serviceID: service.id,
            serviceLabel: service.label,
            serviceIconURL: iconURL
        )

        XCTAssertEqual(content.title, "New message")
        XCTAssertEqual(content.subtitle, "Slack")
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.attachments.first?.identifier, "service-icon")
        XCTAssertEqual(content.userInfo["serviceID"] as? String, service.id.uuidString)
    }

    /// A fresh install has nothing at either path, and must simply open in the
    /// app's folder without any of the move machinery running.
    func testRelocationOnAFreshInstallOpensInTheAppsFolder() throws {
        let (support, legacy, scoped) = try StoreSandbox.relocationDirectories(label: "relocate-fresh")
        defer { try? FileManager.default.removeItem(at: support) }

        XCTAssertEqual(StoreRelocation.resolveStoreURL(legacy: legacy, scoped: scoped), scoped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoped.path), "nothing is created until the container opens")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scoped.deletingLastPathComponent().path),
            "the folder itself must exist so the container can be created in it"
        )
    }
}
