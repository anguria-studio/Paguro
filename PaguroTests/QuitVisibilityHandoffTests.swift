import Foundation
import WebKit
import XCTest
import PaguroCore
@testable import Paguro

@MainActor
final class QuitVisibilityHandoffTests: XCTestCase {
    /// A stand-in for a web view. The handoff only needs object identity.
    private final class FakePage {}

    func testHungPageEndsAtTheCap() async {
        let pages = [FakePage(), FakePage()]
        let hung = pages[1]
        let start = ContinuousClock.now

        let outcome = await QuitVisibilityHandoff.run(
            views: pages,
            cap: .milliseconds(200),
            minimumGrace: .milliseconds(100)
        ) { page in
            if page === hung { try? await Task.sleep(for: .seconds(30)) }
            return true
        }
        let waited = ContinuousClock.now - start

        XCTAssertEqual(outcome.viewCount, 2)
        XCTAssertEqual(outcome.acceptedCount, 1)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(200))
        XCTAssertLessThan(waited, .seconds(2), "the cap must end the handoff")
    }

    /// Models the hardware run that ended 256 ms after its 300 ms cap: pages
    /// that answer late while other work keeps the main thread busy.
    ///
    /// A main-actor task runs 80 ms blocks of work and yields between them, so
    /// each main-actor job waits for up to one block. A timer on the main actor
    /// needed up to three turns there: to start its sleep, to wake up, and to
    /// resume the caller. It ended 190 to 250 ms after the cap in this test.
    /// The timer off the main actor decides at the cap, and only the caller's
    /// own turn waits for the main thread. Other tests can also keep the main
    /// thread busy, so the test checks the decision, not the caller's turn.
    func testCapHoldsWhileTheMainThreadIsBusy() async {
        let cap = Duration.milliseconds(150)
        let busy = MainThreadBusyLoop(blockLength: .milliseconds(80))
        busy.start()
        defer { busy.stop() }
        let start = ContinuousClock.now

        let outcome = await QuitVisibilityHandoff.run(
            views: [FakePage()],
            cap: cap,
            minimumGrace: .milliseconds(100)
        ) { _ in
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        let waited = ContinuousClock.now - start

        XCTAssertTrue(outcome.timedOut)
        XCTAssertGreaterThanOrEqual(waited, cap)
        // The race decides at the deadline off the main thread. Only the
        // caller's return waits for the main thread, and the outcome reports
        // that wait on its own.
        XCTAssertLessThan(waited - outcome.mainThreadDelay, cap + .milliseconds(50), "the deadline must not wait for the main thread")
        XCTAssertLessThan(waited, .seconds(2))
    }

    func testAcceptedPageGetsTheMinimumGrace() async {
        let start = ContinuousClock.now

        let outcome = await QuitVisibilityHandoff.run(
            views: [FakePage()],
            cap: .seconds(5),
            minimumGrace: .milliseconds(120)
        ) { _ in true }
        let waited = ContinuousClock.now - start

        XCTAssertEqual(outcome.acceptedCount, 1)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(120))
        XCTAssertLessThan(waited, .seconds(2))
    }

    func testPagesThatRefuseGetNoGrace() async {
        let start = ContinuousClock.now

        let outcome = await QuitVisibilityHandoff.run(
            views: [FakePage(), FakePage()],
            cap: .seconds(5),
            minimumGrace: .seconds(5)
        ) { _ in false }

        XCTAssertEqual(outcome.acceptedCount, 0)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func testNoLiveViewsReturnsAtOnce() async {
        let start = ContinuousClock.now

        let outcome = await QuitVisibilityHandoff.run(
            views: [FakePage](),
            cap: .seconds(5),
            minimumGrace: .seconds(5)
        ) { _ in
            XCTFail("no page to release")
            return true
        }

        XCTAssertEqual(outcome.viewCount, 0)
        XCTAssertEqual(outcome.acceptedCount, 0)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    /// The real script in a real web view: the page reads visible and gets no
    /// visibilitychange event until the release. After the release it reads
    /// hidden and gets `visibilitychange` and `pagehide`, also in a
    /// same-origin child frame.
    func testReleaseEndsTheOverrideInARealPageAndItsChildFrame() async throws {
        let controller = WKUserContentController()
        controller.addUserScript(WKUserScript(
            source: UserScriptManager.makeVisibilityOverrideScript(),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController = controller
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), configuration: configuration)

        webView.loadHTMLString("""
            <html><head><title>Handoff fixture</title><script>
            window.seen = [];
            document.addEventListener('visibilitychange', function() {
                seen.push('visibilitychange:' + document.visibilityState + ':' + document.hidden);
            });
            window.addEventListener('pagehide', function(e) {
                seen.push('pagehide:' + e.persisted);
            });
            </script></head><body>
            <iframe id="child"></iframe>
            </body></html>
            """, baseURL: URL(string: "https://paguro.invalid/")!)
        try await waitForPage("document.title === 'Handoff fixture'", on: webView)

        let stateBefore = try await webView.evaluateJavaScript("document.visibilityState") as? String
        let hiddenBefore = try await webView.evaluateJavaScript("document.hidden") as? Bool
        XCTAssertEqual(stateBefore, "visible")
        XCTAssertEqual(hiddenBefore, false)

        // A real event from the system stays blocked before the release.
        _ = try await webView.evaluateJavaScript(
            "document.dispatchEvent(new Event('visibilitychange')); seen.length"
        )
        let eventsBefore = try await webView.evaluateJavaScript("seen.length") as? Int
        XCTAssertEqual(eventsBefore, 0)

        // The child frame is an empty same-origin document. WebKit runs the
        // user script in it too, because the script is not main-frame only.
        let name = UserScriptManager.visibilityReleaseFunctionName
        let installChild = """
            var childWindow = document.getElementById('child').contentWindow;
            childWindow.seen = [];
            childWindow.document.addEventListener('visibilitychange', function() {
                childWindow.seen.push(childWindow.document.visibilityState);
            });
            typeof childWindow['\(name)']
            """
        let childFunction = try await webView.evaluateJavaScript(installChild) as? String
        XCTAssertEqual(childFunction, "function")

        let released = await QuitVisibilityHandoff.releaseVisibility(in: webView)
        XCTAssertTrue(released)

        let stateAfter = try await webView.evaluateJavaScript("document.visibilityState") as? String
        let hiddenAfter = try await webView.evaluateJavaScript("document.hidden") as? Bool
        let mainEvents = try await webView.evaluateJavaScript("seen.join(',')") as? String
        let childEvents = try await webView.evaluateJavaScript("frames[0].seen.join(',')") as? String
        let enumerableIndex = try await webView.evaluateJavaScript(
            "Object.keys(window).indexOf('\(name)')"
        ) as? Int
        XCTAssertEqual(stateAfter, "hidden")
        XCTAssertEqual(hiddenAfter, true)
        XCTAssertEqual(mainEvents, "visibilitychange:hidden:true,pagehide:false")
        XCTAssertEqual(childEvents, "hidden", "the main frame must release its same-origin child frame")
        XCTAssertEqual(enumerableIndex, -1, "the release function must not be enumerable")
    }

    func testReleaseOnAPageWithoutTheScriptIsNotAccepted() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString("<title>Plain fixture</title>", baseURL: nil)
        try await waitForPage("document.title === 'Plain fixture'", on: webView)

        let released = await QuitVisibilityHandoff.releaseVisibility(in: webView)

        XCTAssertFalse(released)
    }

    private func waitForPage(_ condition: String, on webView: WKWebView) async throws {
        for _ in 0..<100 {
            if (try? await webView.evaluateJavaScript(condition)) as? Bool == true { return }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTFail("the fixture page did not load")
    }
}
