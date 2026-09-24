import Foundation
import WebKit
import os
import PaguroCore

/// Tells each live page that it becomes hidden before Paguro quits.
///
/// The visibility override blocks `visibilitychange` for the whole life of a
/// page. Web apps often save their state when the page becomes hidden, so
/// without this step a page can lose state that changed since its last save.
/// The step ends the override in each page and gives the pages a short time
/// to run their save handlers. `QuitVisibilityHandoffPolicy` holds the numbers.
@MainActor
enum QuitVisibilityHandoff {
    struct Outcome: Equatable, Sendable {
        var viewCount: Int
        /// The pages that ran the release function.
        var acceptedCount: Int
        var timedOut: Bool
        var elapsed: Duration
    }

    /// The production release. A page without the function (an error page),
    /// a page that throws, and a page that returns something else do not count
    /// as accepted.
    static func releaseVisibility(in webView: WKWebView) async -> Bool {
        let result = try? await webView.evaluateJavaScript(UserScriptManager.visibilityReleaseCallJS)
        guard let frames = result as? Int else { return false }
        return frames > 0
    }

    /// Calls `release` on every view in parallel. It returns when every view
    /// answers or when the cap ends, and then waits for the minimum grace if a
    /// page accepted. Without a view it returns at once.
    static func run<View: AnyObject>(
        views: [View],
        cap: Duration = QuitVisibilityHandoffPolicy.cap,
        minimumGrace: Duration = QuitVisibilityHandoffPolicy.minimumGrace,
        release: @escaping @MainActor (View) async -> Bool
    ) async -> Outcome {
        let clock = ContinuousClock()
        let start = clock.now
        let race = BoundedParallelRace(items: views, work: release)
        let result = await race.run(
            timeout: QuitVisibilityHandoffPolicy.releaseTimeout(viewCount: views.count, cap: cap)
        )
        let remaining = QuitVisibilityHandoffPolicy.remainingGrace(
            elapsed: clock.now - start,
            acceptedCount: result.acceptedCount,
            minimumGrace: minimumGrace,
            cap: cap
        )
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        return Outcome(
            viewCount: views.count,
            acceptedCount: result.acceptedCount,
            timedOut: result.timedOut,
            elapsed: clock.now - start
        )
    }

    static func log(_ outcome: Outcome) {
        let elapsedMs = QuitStorageFlushPolicy.milliseconds(outcome.elapsed)
        AppLogger.webView.notice(
            "Quit visibility handoff: views=\(outcome.viewCount, privacy: .public) accepted=\(outcome.acceptedCount, privacy: .public) timedOut=\(outcome.timedOut, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }
}
