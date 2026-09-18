import XCTest
import AppKit
import PaguroCore
import JavaScriptCore
import WebKit
@testable import Paguro

final class NotificationBridgeTests: XCTestCase {
    // MARK: - The notification interception script

    /// Pulls the injected notification script out of a configured controller.
    @MainActor
    func notificationScriptSource(probeEnabled: Bool = false) throws -> String {
        let manager = UserScriptManager(notificationProbeEnabled: probeEnabled)
        let controller = WKUserContentController()
        manager.installUserScripts(
            for: ModelFixtures.service(label: "Slack", catalogID: "slack"),
            customCSS: nil,
            stayActiveInBackground: false,
            on: controller
        )
        return try XCTUnwrap(
            controller.userScripts.map(\.source).first { $0.contains("paguroNotification") },
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
        context.setObject(record, forKeyedSubscript: "paguroPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { paguroNotification: { postMessage: function(m) { paguroPost(m); } } } };
            function Notification(title, options) { this.title = title; }
            Notification.prototype.close = function() { this.closed = true; };
            Notification.maxActions = 2;
            Notification.permission = 'default';
            window.Notification = Notification;
            """)

        context.evaluateScript(try notificationScriptSource())

        XCTAssertEqual(
            context.evaluateScript("""
                (new window.Notification('hi', {
                    body: 'b',
                    data: {targetURL: 'https://app.slack.com/client/team/channel'}
                })) instanceof window.Notification
                """)?.toBool(),
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
            "and Paguro's own overrides must win over the copied ones"
        )
        XCTAssertEqual(posted.count, 2, "each constructed notification is forwarded once")
        XCTAssertTrue(posted[0].contains("\"body\":\"b\""), "the payload must carry the body")
        XCTAssertTrue(posted[0].contains("\"version\":1"), "the payload must carry its schema version")
        XCTAssertTrue(posted[0].contains("\"type\":\"web-notification\""), "the payload must carry its signal type")
        XCTAssertEqual(
            try NotificationPayload.decode(posted[0]).targetURL,
            "https://app.slack.com/client/team/channel"
        )
        XCTAssertTrue(
            try NotificationPayload.decode(posted[1]).targetURL.isEmpty,
            "the current page URL must not become an implicit destination"
        )
        XCTAssertFalse(posted[0].contains("serviceID"), "the page must not choose the native service identity")
        XCTAssertFalse(posted[0].contains("icon"), "the page must not choose a remote notification icon")
        XCTAssertNil(try NotificationPayload.decode(posted[0]).probe)
    }

    @MainActor
    func testNotificationProbeReportsStructureWithoutValues() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }

        context.evaluateScript("var window = this;")
        context.setObject(record, forKeyedSubscript: "paguroPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { paguroNotification: { postMessage: function(m) { paguroPost(m); } } } };
            function Notification() {}
            window.Notification = Notification;
            """)
        context.evaluateScript(try notificationScriptSource(probeEnabled: true))

        context.evaluateScript("""
            new window.Notification('Private sender', {
                body: 'Private message',
                data: {
                    teamId: 'T-SECRET',
                    channel: {id: 'C-SECRET', displayName: 'Private room'},
                    'unsafe key value': 'MUST-NOT-APPEAR'
                }
            });
            """)

        let raw = try XCTUnwrap(posted.first)
        let probe = try XCTUnwrap(NotificationPayload.decode(raw).probe)
        XCTAssertEqual(probe.source, .constructor)
        XCTAssertEqual(
            probe.dataShape,
            "{channel:{displayName:string,id:string},teamId:string,<redacted-key>:string}"
        )
        XCTAssertFalse(probe.dataShape.contains("SECRET"))
        XCTAssertFalse(probe.dataShape.contains("Private"))
    }

    /// The path that was not covered at all. Web apps raise notifications
    /// through the service worker registration rather than the constructor, so
    /// without this they never reached Paguro.
    @MainActor
    func testNotificationShimForwardsServiceWorkerNotifications() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }

        context.evaluateScript("var window = this;")
        context.setObject(record, forKeyedSubscript: "paguroPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { paguroNotification: { postMessage: function(m) { paguroPost(m); } } } };
            var showCalls = 0;
            function ServiceWorkerRegistration() {}
            ServiceWorkerRegistration.prototype.showNotification = function(t, o) { showCalls++; return 'orig'; };
            window.ServiceWorkerRegistration = ServiceWorkerRegistration;
            """)

        context.evaluateScript(try notificationScriptSource())

        let returned = context.evaluateScript("""
            (new ServiceWorkerRegistration()).showNotification('Nico', {
                body: 'sent a message',
                data: '/messages/42'
            });
            """)?.toString()
        XCTAssertEqual(returned, "orig", "the original call must still run and its result be passed through")
        XCTAssertEqual(context.evaluateScript("showCalls")?.toInt32(), 1, "exactly once — not swallowed, not doubled")
        XCTAssertEqual(posted.count, 1, "and the notification must reach Paguro")
        XCTAssertTrue(posted[0].contains("\"title\":\"Nico\""))
        XCTAssertEqual(try NotificationPayload.decode(posted[0]).targetURL, "/messages/42")
        XCTAssertTrue(try NotificationPayload.decode(posted[0]).pageClickToken.isEmpty)
    }

    @MainActor
    func testNotificationShimCanDispatchTheOriginalPageClickOnce() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }
        let token = "abcdefab-cdef-4abc-8def-abcdefabcdef"

        context.evaluateScript("var window = this;")
        context.setObject(record, forKeyedSubscript: "paguroPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { paguroNotification: { postMessage: function(m) { paguroPost(m); } } } };
            window.crypto = { randomUUID: function() { return '\(token)'; } };
            function Event(type) { this.type = type; }
            function Notification() { this.listeners = {}; }
            Notification.prototype.addEventListener = function(type, listener) {
                this.listeners[type] = listener;
            };
            Notification.prototype.dispatchEvent = function(event) {
                if (this.listeners[event.type]) this.listeners[event.type](event);
                if (event.type === 'click' && this.onclick) this.onclick(event);
                return true;
            };
            window.Notification = Notification;
            """)
        context.evaluateScript(try notificationScriptSource())

        context.evaluateScript("""
            var pageClickCount = 0;
            var notification = new window.Notification('New message');
            notification.addEventListener('click', function() { pageClickCount += 1; });
            """)

        XCTAssertEqual(try NotificationPayload.decode(try XCTUnwrap(posted.first)).pageClickToken, token)
        XCTAssertTrue(
            context.evaluateScript(
                "window.__paguroDispatchNotificationClick('\(token.uppercased())')"
            )?.toBool() == true
        )
        XCTAssertEqual(context.evaluateScript("pageClickCount")?.toInt32(), 1)
        XCTAssertFalse(
            context.evaluateScript("window.__paguroDispatchNotificationClick('\(token)')")?.toBool() == true,
            "a native notification click must not replay a retained page handler"
        )

        context.evaluateScript("new window.Notification('No handler')")
        XCTAssertFalse(
            context.evaluateScript("window.__paguroDispatchNotificationClick('\(token)')")?.toBool() == true,
            "a retained object without a provider handler must allow native URL fallback"
        )
    }

    @MainActor
    func testNotificationProbeIdentifiesRegistrationCalls() throws {
        let context = try XCTUnwrap(JSContext(), "Could not create a JSContext")
        var posted: [String] = []
        let record: @convention(block) (String) -> Void = { posted.append($0) }

        context.evaluateScript("var window = this;")
        context.setObject(record, forKeyedSubscript: "paguroPost" as NSString)
        context.evaluateScript("""
            window.webkit = { messageHandlers: { paguroNotification: { postMessage: function(m) { paguroPost(m); } } } };
            function ServiceWorkerRegistration() {}
            ServiceWorkerRegistration.prototype.showNotification = function() {};
            window.ServiceWorkerRegistration = ServiceWorkerRegistration;
            """)
        context.evaluateScript(try notificationScriptSource(probeEnabled: true))

        context.evaluateScript("""
            (new ServiceWorkerRegistration()).showNotification('Title', {
                data: {href: '/messages/42'}
            });
            """)

        let payload = try NotificationPayload.decode(try XCTUnwrap(posted.first))
        XCTAssertEqual(payload.probe?.source, .serviceWorkerRegistration)
        XCTAssertEqual(payload.probe?.dataShape, "{href:string}")
        XCTAssertEqual(payload.targetURL, "/messages/42")
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

        let event = try NotificationEvent.normalize(
            id: UUID(),
            serviceID: service.id,
            payload: NotificationPayload(
                title: "New message",
                body: "A short body",
                tag: "message-1",
                pageClickToken: "33333333-3333-4333-8333-333333333333"
            ),
            targetURL: URL(string: "https://app.slack.com/client/team/channel"),
            receivedAt: Date()
        )
        let content = NativeNotificationContentBuilder.makeContent(
            event: event,
            serviceLabel: service.label,
            serviceIconURL: iconURL
        )

        XCTAssertEqual(content.title, "New message")
        XCTAssertEqual(content.subtitle, "Slack")
        XCTAssertEqual(content.attachments.count, 1)
        XCTAssertEqual(content.attachments.first?.identifier, "service-icon")
        XCTAssertEqual(content.userInfo["serviceID"] as? String, service.id.uuidString)
        XCTAssertEqual(
            content.userInfo["targetURL"] as? String,
            "https://app.slack.com/client/team/channel"
        )
        XCTAssertEqual(
            content.userInfo["pageClickToken"] as? String,
            "33333333-3333-4333-8333-333333333333"
        )
    }

    @MainActor
    func testNotificationPresenterBuildsARequestForItsService() throws {
        let serviceID = UUID()
        let presenter = NotificationPresenter(
            serviceLabel: "Slack",
            serviceIconURLProvider: { nil }
        )
        let event = try NotificationEvent.normalize(
            id: UUID(),
            serviceID: serviceID,
            payload: NotificationPayload(
                title: "New message",
                body: "A short body",
                tag: "message-1"
            ),
            targetURL: URL(string: "https://app.slack.com/client/team/channel"),
            receivedAt: Date()
        )

        let request = presenter.makeRequest(
            event: event,
            identifier: "request-1"
        )

        XCTAssertEqual(request.identifier, "request-1")
        XCTAssertNil(request.trigger)
        XCTAssertEqual(request.content.title, "New message")
        XCTAssertEqual(request.content.subtitle, "Slack")
        XCTAssertEqual(request.content.userInfo["serviceID"] as? String, serviceID.uuidString)
        XCTAssertEqual(
            request.content.userInfo["targetURL"] as? String,
            "https://app.slack.com/client/team/channel"
        )
    }

    @MainActor
    func testNativeNotificationKeepsTheLivePageClickToken() throws {
        let serviceID = UUID()
        let pageClickToken = UUID()
        let event = try NotificationEvent.normalize(
            id: UUID(),
            serviceID: serviceID,
            payload: NotificationPayload(
                title: "New message",
                pageClickToken: pageClickToken.uuidString
            ),
            receivedAt: Date()
        )

        let content = NativeNotificationContentBuilder.makeContent(
            event: event,
            serviceLabel: "Telegram",
            serviceIconURL: nil
        )

        XCTAssertEqual(
            content.userInfo["pageClickToken"] as? String,
            pageClickToken.uuidString
        )
    }

    func testNotificationDelegateReadsTheNativeBoundRoute() throws {
        let serviceID = UUID()
        let destination = "https://app.slack.com/client/team/channel"
        let pageClickToken = UUID()

        XCTAssertEqual(
            NotificationCenterDelegate.navigationRequest(from: [
                "serviceID": serviceID.uuidString,
                "targetURL": destination,
                "pageClickToken": pageClickToken.uuidString,
            ]),
            NotificationNavigationRequest(
                serviceID: serviceID,
                targetURLString: destination,
                pageClickToken: pageClickToken
            )
        )
        XCTAssertNil(NotificationCenterDelegate.navigationRequest(from: [
            "serviceID": "not-a-uuid",
            "targetURL": destination,
        ]))
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
