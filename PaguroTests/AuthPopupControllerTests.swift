import AppKit
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class AuthPopupControllerTests: XCTestCase {
    func testSelfClosingPopupDoesNotInterruptTheOpenersSignInHandoff() async throws {
        let fixture = PopupFixture()
        defer { fixture.close() }
        try await fixture.load()
        let token = try await fixture.root.evaluateJavaScript("window.documentToken") as? String
        let popup = try await fixture.open(from: fixture.root, name: "signIn")
        _ = try? await popup.evaluateJavaScript("""
            window.opener.postMessage('signed-in', '*');
            window.close();
            """)
        for _ in 0..<100 {
            if fixture.closedPopupCount == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(fixture.closedPopupCount, 1)
        // A provider can finish its session request after its popup closes.
        try await Task.sleep(for: .milliseconds(400))
        let currentToken = try await fixture.root.evaluateJavaScript("window.documentToken") as? String
        let completed = try await fixture.root.evaluateJavaScript("window.authCompleted === true") as? Bool
        XCTAssertEqual(currentToken, token, "Native popup close must not reload the opener")
        XCTAssertEqual(completed, true, "The opener must finish handling the provider's message")
    }

    func testNestedPopupKeepsItsOpenerWindowAlive() async throws {
        let fixture = PopupFixture()
        defer { fixture.close() }
        try await fixture.load()
        let parent = try await fixture.open(from: fixture.root, name: "parent")
        let child = try await fixture.open(from: parent, name: "child")

        XCTAssertTrue(parent.window?.isVisible == true,
                      "Opening a child must not close the sign-in window that created it")
        XCTAssertTrue(fixture.controller.isPopup(parent))
        XCTAssertTrue(fixture.controller.isPopup(child))
        XCTAssertTrue(parent.configuration.websiteDataStore === fixture.root.configuration.websiteDataStore)
        XCTAssertTrue(child.configuration.websiteDataStore === parent.configuration.websiteDataStore)
        let hasOpener = try await child.evaluateJavaScript("window.opener !== null && !window.opener.closed")
        XCTAssertEqual(hasOpener as? Bool, true)

        XCTAssertTrue(fixture.controller.handleWebViewDidClose(child))
        XCTAssertTrue(parent.window?.isVisible == true)
        XCTAssertTrue(fixture.controller.isPopup(parent))
        XCTAssertFalse(fixture.controller.isPopup(child))
    }

    func testClosingParentClosesItsChildWindows() async throws {
        let fixture = PopupFixture()
        defer { fixture.close() }
        try await fixture.load()
        let parent = try await fixture.open(from: fixture.root, name: "parent")
        let child = try await fixture.open(from: parent, name: "child")
        let childWindow = try XCTUnwrap(child.window)

        parent.window?.close()

        XCTAssertFalse(childWindow.isVisible)
        XCTAssertFalse(fixture.controller.isPopup(parent))
        XCTAssertFalse(fixture.controller.isPopup(child))
    }

    func testNestedAuthenticationHostDoesNotLookLikeACompletedSignIn() async throws {
        let fixture = PopupFixture()
        defer { fixture.close() }
        try await fixture.load()
        let parent = try await fixture.open(
            from: fixture.root, name: "parent", url: "popup-fixture://accounts.google.com/parent"
        )
        try await fixture.waitForLoad(parent)
        let child = try await fixture.open(
            from: parent, name: "child", url: "popup-fixture://accounts.google.com/child"
        )
        try await fixture.waitForLoad(child)

        XCTAssertTrue(fixture.controller.handleNavigationFinished(child))
        XCTAssertTrue(child.window?.isVisible == true)
        XCTAssertTrue(parent.window?.isVisible == true)
    }
}

/// Real WebKit popup requests, with windows kept off the active desktop.
@MainActor
private final class PopupFixture: NSObject, WKUIDelegate, WKNavigationDelegate {
    let controller = AuthPopupController(presentWindow: { window in
        window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
        window.orderBack(nil)
    })
    let root: WKWebView
    private var popups: [WKWebView] = []
    private(set) var closedPopupCount = 0

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.setURLSchemeHandler(PopupPageHandler(), forURLScheme: "popup-fixture")
        root = WKWebView(frame: NSRect(x: 0, y: 0, width: 640, height: 480), configuration: configuration)
        super.init()
        root.uiDelegate = self
        root.navigationDelegate = self
    }

    func load() async throws {
        root.load(URLRequest(url: URL(string: "popup-fixture://service/index")!))
        try await waitForLoad(root)
    }

    func waitForLoad(_ view: WKWebView) async throws {
        for _ in 0..<250 {
            if view.title == "Popup fixture", !view.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("The popup fixture did not load")
    }

    func open(from opener: WKWebView, name: String, url: String = "about:blank") async throws -> WKWebView {
        let previousCount = popups.count
        _ = try await opener.evaluateJavaScript("window.open('\(url)', '\(name)'); void 0")
        for _ in 0..<100 {
            if popups.count > previousCount {
                return try XCTUnwrap(popups.last)
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw NSError(domain: "PopupFixture", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "WebKit did not request the popup"])
    }

    func close() {
        for popup in popups.reversed() {
            _ = controller.handleWebViewDidClose(popup)
            popup.stopLoading()
        }
        root.stopLoading()
        root.uiDelegate = nil
        root.navigationDelegate = nil
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        let popup = controller.createWebView(
            with: configuration, for: navigationAction, windowFeatures: windowFeatures,
            opener: webView, fallbackURL: URL(string: "popup-fixture://service/index"),
            navigationDelegate: self, uiDelegate: self
        )
        if let popup { popups.append(popup) }
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        closedPopupCount += 1
        _ = controller.handleWebViewDidClose(webView)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        _ = controller.handleNavigationFinished(webView)
    }
}

@MainActor
private final class PopupPageHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let html = """
            <title>Popup fixture</title>
            <script>
            window.documentToken = Math.random().toString();
            window.addEventListener('message', event => {
                if (event.data === 'signed-in') {
                    setTimeout(() => { window.authCompleted = true; }, 200);
                }
            });
            </script>
            """
        urlSchemeTask.didReceive(URLResponse(
            url: urlSchemeTask.request.url!, mimeType: "text/html",
            expectedContentLength: html.utf8.count, textEncodingName: "utf-8"
        ))
        urlSchemeTask.didReceive(Data(html.utf8))
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}
}
