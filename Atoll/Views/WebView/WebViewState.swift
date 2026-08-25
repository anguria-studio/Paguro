import Foundation
import WebKit

@MainActor
@Observable
final class WebViewState {
    private(set) var isLoading = false

    private var observations: [NSKeyValueObservation] = []
    private(set) weak var webView: WKWebView?

    /// Bumped on every attach/detach. Each observer captures the generation it
    /// was created under; a KVO callback that hops to the main queue after a
    /// rebind finds the generation has moved on and drops its stale write, so a
    /// queued update from the previous web view can't clobber the new one's state
    /// after a fast service switch.
    private var generation = 0

    init() {}

    func attach(to webView: WKWebView) {
        self.webView = webView
        generation &+= 1
        let gen = generation
        observations.removeAll()
        isLoading = webView.isLoading

        // WKWebView fires KVO on the main thread in practice, but this is not
        // contractually guaranteed. Use DispatchQueue.main.async for safety —
        // it's a no-op if already on main, and handles the off-main edge case
        // without the crash risk of MainActor.assumeIsolated.
        observations.append(
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                let value = change.newValue ?? false
                DispatchQueue.main.async { guard let self, self.generation == gen else { return }; self.isLoading = value }
            }
        )
    }

    func detach() {
        generation &+= 1
        observations.removeAll()
        webView = nil
        isLoading = false
    }
}
