import XCTest
import WebKit
import PaguroCore
@testable import Paguro

/// Adapter rules that keep a live service page on screen after a failed load
/// or full hibernation.
final class WebNavigationRuleTests: XCTestCase {
    // MARK: - Provisional failures

    func testCancelledLoadKeepsTheCurrentPage() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)
        XCTAssertTrue(WebViewCoordinator.keepsCurrentPage(afterProvisionalFailure: error))
    }

    func testCannotShowURLAndDownloadInterruptionKeepTheCurrentPage() {
        for code in [101, 102] {
            let error = NSError(domain: "WebKitErrorDomain", code: code)
            XCTAssertTrue(WebViewCoordinator.keepsCurrentPage(afterProvisionalFailure: error), "\(code)")
        }
    }

    func testConnectionFailuresShowTheErrorPage() {
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        let dns = NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotFindHost)
        let otherWebKit = NSError(domain: "WebKitErrorDomain", code: 103)
        XCTAssertFalse(WebViewCoordinator.keepsCurrentPage(afterProvisionalFailure: offline))
        XCTAssertFalse(WebViewCoordinator.keepsCurrentPage(afterProvisionalFailure: dns))
        XCTAssertFalse(WebViewCoordinator.keepsCurrentPage(afterProvisionalFailure: otherWebKit))
    }

    @MainActor
    func testReloadRetriesHomeWhenThereIsNoCommittedPage() {
        let webView = NavigationSpy()
        let home = URL(string: "https://example.com")!
        WebViewCoordinator.reload(webView, fallbackURL: home)
        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertEqual(webView.requests.map(\.url), [home])
    }

    @MainActor
    func testFreshWebKitViewRetriesTheServiceAddress() async {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        let requested = expectation(description: "Service address requested")
        let home = URL(string: "about:blank")!
        let capture = RequestCapture { url in
            XCTAssertEqual(url, home)
            requested.fulfill()
        }
        webView.navigationDelegate = capture
        WebViewCoordinator.reload(webView, fallbackURL: home)
        await fulfillment(of: [requested], timeout: 10)
        withExtendedLifetime((webView, capture)) {}
    }

    @MainActor
    func testReloadKeepsTheCurrentPageWhenWebKitCanReloadIt() {
        let webView = NavigationSpy()
        webView.reloadResult = webView.loadHTMLString("<p>Existing page</p>", baseURL: nil)
        defer { webView.stopLoading() }
        XCTAssertNotNil(webView.reloadResult)
        WebViewCoordinator.reload(webView, fallbackURL: URL(string: "https://example.com"))
        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertTrue(webView.requests.isEmpty)
    }

    @MainActor
    func testCancelledLoadClearsTheRingWithoutReplacingThePage() async {
        let webView = NavigationSpy()
        let coordinator = WebViewCoordinator()
        coordinator.instanceID = UUID()
        var health = ServiceHealth.loading
        let stopped = expectation(description: "Stopped loading")
        coordinator.onHealthEvent = { _, event in
            health = health.next(event)
            stopped.fulfill()
        }
        coordinator.webView(webView, didFailProvisionalNavigation: nil,
                            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        await fulfillment(of: [stopped], timeout: 1)
        XCTAssertEqual(health, .live)
        XCTAssertTrue(webView.requests.isEmpty)
    }

    @MainActor
    func testCancelledOldLoadDoesNotClearAReplacementLoadsRing() async {
        let webView = NavigationSpy()
        webView.reportedLoading = true
        let coordinator = WebViewCoordinator()
        coordinator.instanceID = UUID()
        let stopped = expectation(description: "No stopped event for a replacement load")
        stopped.isInverted = true
        coordinator.onHealthEvent = { _, _ in stopped.fulfill() }
        coordinator.webView(webView, didFailProvisionalNavigation: nil,
                            withError: NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled))
        await fulfillment(of: [stopped], timeout: 0.1)
    }

    // MARK: - Resume after hibernation

    func testWebPagesAreResumed() {
        let url = URL(string: "https://app.slack.com/client/T1/C2")!
        XCTAssertEqual(WebViewPool.resumeURLString(from: url), url.absoluteString)
        XCTAssertEqual(WebViewPool.resumeURLString(from: URL(string: "http://intranet.example/")), "http://intranet.example/")
    }

    /// The error page loads with `loadHTMLString`, so the web view's URL is
    /// `about:blank` while it shows. Resuming there showed a blank page.
    func testErrorPageAndMissingURLResumeAtHome() {
        XCTAssertNil(WebViewPool.resumeURLString(from: URL(string: "about:blank")))
        XCTAssertNil(WebViewPool.resumeURLString(from: URL(string: "data:text/html,hi")))
        XCTAssertNil(WebViewPool.resumeURLString(from: nil))
    }
}

@MainActor
private final class RequestCapture: NSObject, WKNavigationDelegate {
    let receive: (URL?) -> Void
    init(receive: @escaping (URL?) -> Void) { self.receive = receive }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        receive(action.request.url)
        return .cancel
    }
}

@MainActor
private final class NavigationSpy: WKWebView {
    var reportedLoading = false
    var reloadCount = 0
    var reloadResult: WKNavigation?
    var requests: [URLRequest] = []

    init() { super.init(frame: .zero, configuration: WKWebViewConfiguration()) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isLoading: Bool { reportedLoading }
    override func reload() -> WKNavigation? {
        reloadCount += 1
        return reloadResult
    }
    override func load(_ request: URLRequest) -> WKNavigation? {
        requests.append(request)
        return nil
    }
}
