import XCTest
import WebKit
@testable import Atoll

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
