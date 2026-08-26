import Foundation
import WebKit
import AppKit
import os
import AtollCore

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?
    private var popupTitleObservation: NSKeyValueObservation?

    /// The service's main web view that opened the current popup. Kept so we can
    /// reload it once the sign-in popup closes (see reloadOpenerAfterPopup).
    private weak var openerWebView: WKWebView?

    /// Whether the current popup was *opened at* a known sign-in gateway. Set
    /// once, from the URL that opened it. `WebRoutingPolicy.shouldReloadOpener`
    /// explains why the rest of the navigation chain is not consulted.
    private var popupOpenedAtAuthHost = false

    /// Fallback URL to load if the WebContent process crashes before any
    /// navigation has committed (so `webView.reload()` has nothing to retry).
    var fallbackURL: URL?

    /// Timestamps of recent WebContent terminations, used to break a crash →
    /// reload → crash loop. Accessed only from main-thread delegate callbacks.
    private var crashTimestamps: [Date] = []
    /// Same, for the OAuth/sign-in popup web view — tracked separately so a
    /// looping popup gets the same backoff the main view has instead of
    /// reloading forever.
    private var popupCrashTimestamps: [Date] = []
    // nonisolated so the nonisolated `shouldAutoReload` can use them as default
    // argument values — they're immutable Sendable constants.
    private nonisolated static let maxCrashesInWindow = 3
    private nonisolated static let crashWindow: TimeInterval = 30

    /// Routes external/cross-domain navigations through AppState so it can
    /// match the URL against an existing Atoll service before falling back
    /// to the system browser. The second argument is the source service's id
    /// (`instanceID`), so AppState can honour that service's "open links in
    /// Atoll" choice. When nil the coordinator falls back to `NSWorkspace.open`
    /// directly.
    var externalLinkHandler: ((URL, UUID?) -> Void)?

    /// The service this coordinator drives, set by `WebViewPool` so navigation
    /// callbacks can be attributed to a specific service.
    var instanceID: UUID?

    /// Called when a top-level navigation finishes (fresh load or login
    /// redirect) so the app can fire an immediate badge poll instead of waiting
    /// for the next poll tick. Never called for OAuth popup web views.
    var onNavigationFinished: ((UUID) -> Void)?

    /// Reports a navigation event for this service so the pool can keep a health
    /// state the rail can draw. Set by `WebViewPool`. Never called for OAuth
    /// popup web views: a popup's failure is the popup's business, and the
    /// service behind it is still fine.
    var onHealthEvent: ((UUID, ServiceHealth.Event) -> Void)?

    /// Set just before Atoll loads one of its own error pages into the web
    /// view, and cleared by the `didFinish` that page produces.
    ///
    /// Without it the failed dot would light and go out immediately: a failure
    /// paints an error page, painting it is a navigation, and that navigation
    /// finishes — which would report the service healthy while it is sitting on
    /// "Unable to connect".
    private var errorPageLoadInFlight = false

    /// Resolves a camera/microphone capture request to a WebKit decision. Set by
    /// `WebViewPool` (supplied by `AppState`), which owns the per-service policy
    /// and the "ask" prompt. Nil ⇒ deny (fail closed).
    var mediaCapturePolicyProvider: ((UUID, WKMediaCaptureType, WKFrameInfo) async -> WKPermissionDecision)?

    /// The legacy WebKit error domain that `WKWebView` still reports for
    /// load failures that are not network errors.
    nonisolated private static let webKitLegacyErrorDomain = "WebKitErrorDomain"
    /// `WebKitErrorCannotShowURL`: WebKit has no way to show this URL.
    nonisolated private static let webKitCannotShowURLCode = 101
    /// `WebKitErrorFrameLoadInterruptedByPolicyChange`: the load stopped
    /// because the response became a download.
    nonisolated private static let webKitFrameLoadInterruptedCode = 102

    /// Whether a provisional navigation failure keeps the current page instead
    /// of showing the error page.
    ///
    /// The committed page is still on screen after a provisional failure.
    /// These failures are not connection problems, so the page must stay: a
    /// cancelled load (the user navigated away), a URL WebKit cannot show, and
    /// a load that WebKit interrupted to start a download.
    nonisolated static func keepsCurrentPage(afterProvisionalFailure error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled { return true }
        if error.domain == webKitLegacyErrorDomain {
            return error.code == webKitCannotShowURLCode || error.code == webKitFrameLoadInterruptedCode
        }
        return false
    }

    /// Whether a link that leaves a service (and that no other Atoll service
    /// owns) should open in an in-app Atoll window rather than the system
    /// browser. True only when the source service opted in AND the target is
    /// http/https. Other schemes stay on the `openExternally` path so the Core
    /// scheme gate still decides them (a `mailto:` reaches Mail, an
    /// `smb://` is dropped) — an in-app web view can't load them anyway.
    nonisolated static func shouldOpenInAppBrowser(sourceOptedIn: Bool, url: URL) -> Bool {
        guard sourceOptedIn, let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    /// Hands `url` to the system handler, but only on a vetted scheme. Anything
    /// else is dropped with a log line rather than silently ignored.
    nonisolated static func openExternally(_ url: URL) {
        guard WebRoutingPolicy.isSafeForExternalOpen(url) else {
            AppLogger.webView.info("Blocked external open on disallowed scheme: \(url.scheme ?? "none")")
            return
        }
        NSWorkspace.shared.open(url)
    }

    deinit {
        // A backstop for the popup lifecycle, which is normally torn down by
        // popupWindowWillClose / webViewDidClose. deinit is nonisolated, so it
        // can't call the main-actor-isolated cleanupPopup(); invalidate the
        // (thread-safe) KVO observation here and close any still-open popup
        // window on the main actor. The window is captured as a local so the
        // hop never touches `self`, which is being deallocated.
        //
        popupTitleObservation?.invalidate()
        if let window = popupWindow {
            Task { @MainActor in window.close() }
        }
        // Mirror cleanupPopup's removeObserver so the willClose observer is gone
        // even if the coordinator is deallocated with a popup still open. Must
        // come LAST: passing `self` copies it, after which isolated stored
        // properties can't be touched in a deinit. removeObserver(self) is
        // thread-safe; the modern runtime would auto-clear it anyway, but drop it
        // explicitly for symmetry.
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Navigation Delegate

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .cancel
        }

        #if DEBUG
        // The fixture cannot terminate a WebContent process through a public
        // API. This route calls the same recovery handler after the navigation
        // decision completes. Release builds do not contain this route.
        if CompatibilityFixture.isProcessFailureURL(url) {
            scheduleFixtureProcessFailure(for: webView)
            return .cancel
        }
        #endif

        let request = NavigationRequestContext(
            url: url,
            isLinkActivated: navigationAction.navigationType == .linkActivated,
            shouldDownload: navigationAction.shouldPerformDownload,
            hasCommandModifier: navigationAction.modifierFlags.contains(.command),
            targetsMainFrame: navigationAction.targetFrame?.isMainFrame ?? true,
            currentHost: webView.url?.host
        )

        switch NavigationDecision.decide(request) {
        case .cancel:
            return .cancel
        case .download:
            return .download
        case .openExternally(.system):
            Self.openExternally(url)
            return .cancel
        case .openExternally(.matchingServiceOrSystem):
            if let handler = externalLinkHandler {
                handler(url, instanceID)
            } else {
                Self.openExternally(url)
            }
            return .cancel
        case .allow:
            break
        }

        #if DEBUG
        // A live service test needs the navigation boundary, but it must not
        // record a path, query, account name, or page title. The host and broad
        // context show whether sign-in stayed in the service or its popup.
        if navigationAction.targetFrame?.isMainFrame ?? true {
            let context = webView === popupWebView ? "popup" : "service"
            let host = url.host ?? "no-host"
            AppLogger.webView.info(
                "Allowed main-frame navigation: context=\(context, privacy: .public) host=\(host, privacy: .public) type=\(navigationAction.navigationType.rawValue)"
            )
        }
        #endif
        return .allow
    }

    func webView(
        _ webView: WKWebView,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let space = challenge.protectionSpace
        #if DEBUG
        if let trust = space.serverTrust,
           CompatibilityFixture.allowsUntrustedServerCertificate(
               host: space.host,
               port: space.port,
               authenticationMethod: space.authenticationMethod
           ) {
            completionHandler(.useCredential, URLCredential(trust: trust))
            return
        }
        #endif
        completionHandler(.performDefaultHandling, nil)
    }

    #if DEBUG
    private func scheduleFixtureProcessFailure(for webView: WKWebView) {
        Task { @MainActor [weak self, weak webView] in
            await Task.yield()
            guard let self, let webView else { return }
            self.webViewWebContentProcessDidTerminate(webView)
        }
    }
    #endif

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse
    ) async -> WKNavigationResponsePolicy {
        // An explicit `Content-Disposition: attachment` means "download this",
        // even for a type WebKit could render inline (e.g. a PDF served as a
        // download — the reported Teams case). Otherwise download anything we
        // can't display.
        if Self.isAttachment(navigationResponse.response) {
            return .download
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // Some providers finish sign-in by navigating the popup to the service
        // instead of calling window.close(). Gmail does this after password
        // sign-in. Close a known authentication popup after it returns to the
        // opener's service, then reload the opener with the shared session.
        if webView === popupWebView {
            if WebRoutingPolicy.shouldCloseAuthenticationPopup(
                openedAtAuthenticationHost: popupOpenedAtAuthHost,
                landedHost: webView.url?.host,
                openerHost: openerWebView?.url?.host ?? fallbackURL?.host
            ) {
                AppLogger.webView.info("Authentication popup returned to the service; closing it")
                reloadOpenerAfterPopup(selfClosed: false)
                cleanupPopup()
            }
            return
        }

        // Only the service's main web view carries a badge.
        guard let instanceID else { return }
        if errorPageLoadInFlight {
            errorPageLoadInFlight = false
        } else {
            onHealthEvent?(instanceID, .finishedLoading)
        }
        onNavigationFinished?(instanceID)
    }

    // WebKit kills WebContent on memory pressure, JIT bugs, or page crashes.
    // The webview is left blank with no recovery affordance — auto-reload so
    // the user just sees a brief flicker. But a page that crashes
    // deterministically would reload-crash forever, so back off after a few
    // crashes in a short window and show a recovery page instead.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // The OAuth/sign-in popup shares this coordinator as its delegate.
        // Don't apply the service's crash recovery (fallbackURL + home page) to
        // it — that would reload the popup on the service's home URL, not the
        // popup's own page. Reload its own page, but with the same crash-window
        // backoff the main view has: a popup that crashes deterministically
        // would otherwise reload-crash forever. Give up by closing the popup.
        if webView === popupWebView {
            let now = Date()
            popupCrashTimestamps.append(now)
            popupCrashTimestamps = popupCrashTimestamps.filter { now.timeIntervalSince($0) <= Self.crashWindow }
            guard Self.shouldAutoReload(
                crashTimestamps: popupCrashTimestamps,
                now: now,
                maxCrashes: Self.maxCrashesInWindow,
                window: Self.crashWindow
            ) else {
                AppLogger.webView.error("OAuth popup WebContent terminated repeatedly — closing popup")
                cleanupPopup()
                return
            }
            if webView.url != nil { webView.reload() }
            return
        }

        // The service's own content process died — reconcile downloads it started
        // so a stuck transfer can't leak this coordinator (see cancelActiveDownloads).
        cancelActiveDownloads()

        let now = Date()
        crashTimestamps.append(now)
        crashTimestamps = crashTimestamps.filter { now.timeIntervalSince($0) <= Self.crashWindow }

        let retryURL = webView.url ?? fallbackURL

        guard Self.shouldAutoReload(
            crashTimestamps: crashTimestamps,
            now: now,
            maxCrashes: Self.maxCrashesInWindow,
            window: Self.crashWindow
        ) else {
            AppLogger.webView.error("WebContent terminated repeatedly — showing recovery page")
            let html = Self.errorPageHTML(
                title: "This page keeps crashing",
                message: "Atoll stopped reloading it automatically to avoid a loop. You can try again, or switch to another service.",
                retryURLString: retryURL?.absoluteString
            )
            // A page that keeps crashing is a failure the rail should show, and
            // the recovery page's own load must not report it healthy.
            if let instanceID { onHealthEvent?(instanceID, .failed) }
            errorPageLoadInFlight = true
            webView.loadHTMLString(html, baseURL: nil)
            return
        }

        AppLogger.webView.warning("WebContent process terminated — reloading")
        if webView.url != nil {
            webView.reload()
        } else if let fallback = fallbackURL {
            webView.load(URLRequest(url: fallback))
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        // Don't overwrite the popup with our generic error page: a transient
        // provisional failure mid sign-in (an intermediate redirect WebKit
        // can't render, a captive-portal blip) would break the OAuth flow.
        // Let the popup's own site handle it. (didFinish already skips the
        // popup; this keeps the failure path symmetric.)
        if webView === popupWebView { return }

        let nsError = error as NSError
        guard !Self.keepsCurrentPage(afterProvisionalFailure: nsError) else { return }

        // Same page the generic error page below is about, reported to the rail
        // so a service that failed while you were looking at another one still
        // says so.
        if let instanceID { onHealthEvent?(instanceID, .failed) }

        // The URL that failed isn't `webView.url` (which still points at the
        // last committed page); pull it from the error so "Try Again" retries
        // the right page.
        let failingURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString
            ?? webView.url?.absoluteString
            ?? fallbackURL?.absoluteString

        let html = Self.errorPageHTML(
            title: "Unable to connect",
            message: error.localizedDescription,
            retryURLString: failingURL
        )
        errorPageLoadInFlight = true
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Crash backoff / error page (pure, testable)

    /// Whether to keep auto-reloading after a WebContent crash. Returns false
    /// once `maxCrashes` terminations occur within `window` seconds, so a
    /// deterministically-crashing page stops looping.
    nonisolated static func shouldAutoReload(
        crashTimestamps: [Date],
        now: Date,
        maxCrashes: Int = maxCrashesInWindow,
        window: TimeInterval = crashWindow
    ) -> Bool {
        let recent = crashTimestamps.filter { now.timeIntervalSince($0) <= window }
        return recent.count < maxCrashes
    }

    /// Builds the in-webview error/recovery page. When `retryURLString` is
    /// non-nil a "Try Again" button navigates to that exact URL (JSON-encoded
    /// so it can't break out of the JS string) — never `location.reload()`,
    /// which would just reload this about:blank error document.
    nonisolated static func errorPageHTML(
        title: String,
        message: String,
        retryURLString: String?
    ) -> String {
        func escapeHTML(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
        }

        let retryBlock: String
        // Only wire the retry button for http/https targets — the URL derives from
        // the failing navigation, but refuse `javascript:`/`data:` so a crafted
        // failing URL can't run script when the user clicks Try Again.
        if let retryURLString,
           let retryScheme = URL(string: retryURLString)?.scheme?.lowercased(),
           retryScheme == "http" || retryScheme == "https" {
            // Escape for embedding inside a double-quoted JS string literal so
            // a URL with quotes/newlines can't break out (or close the script).
            let escaped = retryURLString
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "<", with: "\\x3C")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
            retryBlock = """
                <button id="atoll-retry">Try Again</button>
                <script>
                    var target = "\(escaped)";
                    document.getElementById('atoll-retry')
                        .addEventListener('click', function() { location.href = target; });
                </script>
            """
        } else {
            retryBlock = ""
        }

        return """
        <html>
        <head>
            <meta name="viewport" content="width=device-width">
            <style>
                body { display:flex;justify-content:center;align-items:center;
                    height:100vh;font-family:-apple-system,system-ui;color:#64748b;
                    text-align:center;background:#f8fafc;margin:0; }
                h2 { color:#1e293b;font-weight:600;margin:0 0 8px; }
                p { margin:0 0 20px;line-height:1.5; }
                button { padding:10px 24px;font-size:14px;cursor:pointer;
                    background:#2563eb;color:white;border:none;border-radius:8px;
                    font-weight:500; }
                .icon { font-size:48px;margin-bottom:16px; }
                .container { max-width:400px;padding:20px; }
                @media (prefers-color-scheme: dark) {
                    body { background:#0f172a;color:#94a3b8; }
                    h2 { color:#e2e8f0; }
                    button { background:#3b82f6; }
                }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="icon">⚠️</div>
                <h2>\(escapeHTML(title))</h2>
                <p>\(escapeHTML(message))</p>
                \(retryBlock)
            </div>
        </body></html>
        """
    }

    // MARK: - UI Delegate (OAuth Pop-ups)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // If the new-window request is for the same service — e.g. Slack opening
        // a workspace via a target=_blank link — load it in the existing web
        // view instead of spawning a separate NSWindow. Only genuinely
        // cross-service popups (real OAuth sign-in windows to another domain)
        // fall through and get their own window below.
        //
        // Restricted to real link clicks. A programmatic `window.open()` hands
        // the caller a window handle, and sign-in flows test it:
        //
        //     const w = window.open(url); if (!w) return;
        //
        // Returning nil there reads as "popup blocked", so the page abandons
        // whatever it was starting with no window and no error to show for it.
        // Same-service `window.open` therefore falls through to a real window,
        // which shares the opener's data store so a session started in it lands
        // in the right place.
        if WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: navigationAction.navigationType == .linkActivated,
            targetHost: navigationAction.request.url?.host,
            openerHost: webView.url?.host
        ) {
            webView.load(navigationAction.request)
            return nil
        }

        // Clean up any existing popup before opening a new one
        cleanupPopup()

        // Remember the service's main web view so we can reload it after the
        // popup closes. The popup shares this data store, so once sign-in
        // finishes the session cookies are already here — the main view just
        // needs to reload to leave its signed-out page.
        openerWebView = webView

        // The sign-in signal, taken from the URL that opened the popup and not
        // touched again: a service asking the user to sign in again opens
        // straight at its provider. See `WebRoutingPolicy.shouldReloadOpener`.
        popupOpenedAtAuthHost = navigationAction.request.url?.host.map(WebRoutingPolicy.isAuthenticationHost) ?? false

        // CRITICAL: Use the configuration passed in — it inherits the parent's data store
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self

        // Honor the page's requested popup size when reasonable; otherwise
        // default to a comfortable 1100×800 (the previous 800×600 was too
        // cramped for modern OAuth screens and standalone editors).
        let requestedWidth = (windowFeatures.width?.doubleValue ?? 0)
        let requestedHeight = (windowFeatures.height?.doubleValue ?? 0)
        let width = max(640, min(1400, requestedWidth > 0 ? requestedWidth : 1100))
        let height = max(480, min(1000, requestedHeight > 0 ? requestedHeight : 800))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // We hold this window in a strong property (`popupWindow`) and release
        // it ourselves in cleanupPopup. Left at its `true` default, AppKit would
        // also release the window when it closes — an over-release that crashes
        // the app when an OAuth/sign-in popup (e.g. Gmail) window is closed.
        window.isReleasedWhenClosed = false
        window.contentView = popup
        window.title = navigationAction.request.url?.host ?? "Atoll"
        window.center()
        window.makeKeyAndOrderFront(nil)

        self.popupWebView = popup
        self.popupWindow = window

        // Mirror the page's <title> into the NSWindow title bar so the user
        // sees what's actually loaded (e.g. "Google Drive — Sign in") rather
        // than the stale initial host name.
        popupTitleObservation?.invalidate()
        // Read the new title from the (Sendable String?) KVO change value rather
        // than reaching back into the web view — the observe closure is
        // nonisolated/@Sendable, and touching the main-actor-isolated WKWebView
        // from it is a data race under Swift 6. An empty title leaves the bar on
        // its current text (the host it was seeded with) instead of clearing it.
        popupTitleObservation = popup.observe(\.title, options: [.new]) { [weak window] _, change in
            guard let newTitle = change.newValue ?? nil, !newTitle.isEmpty else { return }
            Task { @MainActor in
                window?.title = newTitle
            }
        }

        // Observe window close to clean up even when closed via OS button
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popupWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: window
        )

        return popup
    }

    @objc private func popupWindowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === popupWindow else { return }
        // Closed by the user (red button / ⌘W), not by the page.
        reloadOpenerAfterPopup(selfClosed: false)
        cleanupPopup()
    }

    /// Reloads the service that opened the popup when the Core rule says to.
    private func reloadOpenerAfterPopup(selfClosed: Bool) {
        guard WebRoutingPolicy.shouldReloadOpener(
            selfClosed: selfClosed,
            openedAtAuthenticationHost: popupOpenedAtAuthHost
        ) else { return }
        guard let opener = openerWebView else { return }
        if opener.url != nil {
            opener.reload()
        } else if let fallback = fallbackURL {
            opener.load(URLRequest(url: fallback))
        }
    }

    private func cleanupPopup() {
        if let window = popupWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.willCloseNotification,
                object: window
            )
        }
        popupTitleObservation?.invalidate()
        popupTitleObservation = nil
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWindow?.close()
        popupWebView = nil
        popupWindow = nil
        // Give the next popup its own crash budget — a prior popup's tally must
        // not shorten the backoff for an unrelated sign-in opened soon after.
        popupCrashTimestamps = []
        // Likewise the sign-in signal: a link popup opened after a sign-in must
        // not inherit its predecessor's reason to reload the service.
        popupOpenedAtAuthHost = false
    }

    func webViewDidClose(_ webView: WKWebView) {
        if webView === popupWebView {
            // The page called window.close() on itself — the shape an OAuth
            // popup takes when it finishes.
            reloadOpenerAfterPopup(selfClosed: true)
            cleanupPopup()
        }
    }

    // MARK: - File Upload Picker

    /// Presents the native file picker when a page triggers an
    /// `<input type="file">` (e.g. Slack's "Upload File" for a profile photo).
    /// WKWebView shows no picker at all unless this delegate method is
    /// implemented, so without it every file-upload button silently does
    /// nothing. Honors the input's `multiple` and `webkitdirectory` attributes.
    ///
    /// CRITICAL: `completionHandler` MUST be `@MainActor`. The WebKit header
    /// annotates the block `WK_SWIFT_UI_ACTOR` (= `@MainActor`), so the imported
    /// optional-protocol requirement carries that isolation. Drop it and Swift
    /// silently declines to treat this as the witness — the method never reaches
    /// the Objective-C runtime (`responds(to:)` is false), WebKit never calls it,
    /// and the picker never opens, with no error or warning.
    func webView(
        _ webView: WKWebView,
        runOpenPanelWith parameters: WKOpenPanelParameters,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor ([URL]?) -> Void
    ) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.resolvesAliases = true

        // WebKit hangs the page's `<input type=file>` until `completionHandler`
        // fires exactly once. Route it through a one-shot latch so it can't fire
        // twice and — crucially — so the page is released even if the host window
        // closes while the sheet is open, in which case the sheet's own handler
        // may never run and the input would hang forever.
        let session = FilePickerSession(completionHandler)
        let handleResponse: (NSApplication.ModalResponse) -> Void = { response in
            session.finish(response == .OK ? panel.urls : nil)
        }

        // Attach as a sheet to the web view's window when we have one; fall back
        // to a standalone modal panel otherwise (e.g. an OAuth popup web view).
        if let window = webView.window {
            session.observeClose(of: window)
            panel.beginSheetModal(for: window, completionHandler: handleResponse)
        } else {
            panel.begin(completionHandler: handleResponse)
        }
    }

    // MARK: - Media Capture (camera / microphone) permission

    /// Gates every `getUserMedia()` call. Without this method WKWebView denies
    /// all capture, so video/voice services never get the camera or mic.
    ///
    /// CRITICAL: `decisionHandler` MUST be `@escaping @MainActor (…)`. The WebKit
    /// header annotates the block `WK_SWIFT_UI_ACTOR` (= `@MainActor`); drop it and
    /// Swift silently declines to treat this as the protocol witness — the method
    /// never reaches the Obj-C runtime, WebKit never calls it, and capture fails
    /// with no error. Same trap as `runOpenPanelWith` above. The `origin`
    /// parameter is `WKSecurityOrigin` (not URL); getting it wrong also breaks the
    /// witness. The `Task` captures only locals — never `self` — so a coordinator
    /// torn down mid-decision leaves the handler a safe no-op.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void
    ) {
        // A breadcrumb so QA can confirm the witness actually fires (the trap is
        // silent, so "did the method get called at all?" is the first question).
        AppLogger.webView.info("Media capture request (type \(type.rawValue), mainFrame \(frame.isMainFrame))")
        guard let id = instanceID, let provider = mediaCapturePolicyProvider else {
            AppLogger.webView.info("Media capture decision: denied because no service policy provider is available")
            decisionHandler(.deny)
            return
        }
        Task { @MainActor in
            let decision = await provider(id, type, frame)
            AppLogger.webView.info(
                "Media capture decision type=\(type.rawValue, privacy: .public) mainFrame=\(frame.isMainFrame, privacy: .public) decision=\(decision.rawValue, privacy: .public)"
            )
            decisionHandler(decision)
        }
    }

    // MARK: - JavaScript Dialogs (alert / confirm / prompt)

    /// Presents a native panel for `window.alert()`. Without this method WebKit
    /// shows nothing and returns at once — harmless for alert, but the same
    /// missing-delegate default silently answers `confirm()` with "Cancel" and
    /// `prompt()` with nil (see below), which strands any page flow gated on a
    /// dialog. Gmail's Send runs through `confirm()` (the attachment reminder and
    /// the no-subject prompt), so a signed-in user clicking Send just saw nothing
    /// happen. Implementing all three restores the expected behaviour.
    ///
    /// CRITICAL: `completionHandler` MUST be `@escaping @MainActor`. The WebKit
    /// header annotates the block `WK_SWIFT_UI_ACTOR` (= `@MainActor`); drop it
    /// and Swift silently declines to treat this as the protocol witness — the
    /// method never reaches the Obj-C runtime, WebKit never calls it, and the
    /// page hangs. Same trap as `runOpenPanelWith` above.
    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor () -> Void
    ) {
        AppLogger.webView.info("JS alert panel")
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        let session = JSDialogSession(cancelValue: (), completionHandler)
        present(alert, over: webView, session: session) { _ in () }
    }

    /// Presents a native OK / Cancel panel for `window.confirm()`. Returns `true`
    /// only when the user chooses OK; window-close-first resolves to `false`, the
    /// same as clicking Cancel. See the alert method above for the `@MainActor`
    /// witness requirement — it applies identically here.
    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (Bool) -> Void
    ) {
        AppLogger.webView.info("JS confirm panel")
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let session = JSDialogSession(cancelValue: false, completionHandler)
        present(alert, over: webView, session: session) { $0 == .alertFirstButtonReturn }
    }

    /// Presents a native text-input panel for `window.prompt()`. Returns the
    /// entered text on OK, or nil on Cancel / window-close-first (which the page
    /// reads as a dismissed prompt). See the alert method above for the
    /// `@MainActor` witness requirement.
    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping @MainActor (String?) -> Void
    ) {
        AppLogger.webView.info("JS text-input panel")
        let alert = NSAlert()
        alert.messageText = prompt
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let session = JSDialogSession(cancelValue: String?.none, completionHandler)
        present(alert, over: webView, session: session) { response in
            response == .alertFirstButtonReturn ? field.stringValue : nil
        }
    }

    /// Runs `alert` as a sheet on the web view's window when there is one, falling
    /// back to an app-modal panel otherwise (e.g. an OAuth popup web view). The
    /// session guarantees the page's completion handler fires exactly once — on a
    /// button press or, for a sheet, if the host window closes first — mirroring
    /// the file-picker path. `map` turns the modal response into the value the
    /// page's handler expects.
    private func present<T>(
        _ alert: NSAlert,
        over webView: WKWebView,
        session: JSDialogSession<T>,
        map: @escaping (NSApplication.ModalResponse) -> T
    ) {
        if let window = webView.window {
            session.observeClose(of: window)
            alert.beginSheetModal(for: window) { response in
                session.finish(map(response))
            }
        } else {
            session.finish(map(alert.runModal()))
        }
    }

    // MARK: - Context Menu

    // WKWebView provides native context menus by default on macOS.
    // We add "Open Link in Browser" and "Copy Link" via the default
    // context menu handling. Custom context menus can be added via
    // WKUIDelegate methods if needed in the future.

    // MARK: - Download Delegate

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        download.delegate = self
        trackDownload(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        download.delegate = self
        trackDownload(download)
    }

    /// Maps each in-flight download to the destination we chose for it, so the
    /// finish handler can reveal the right file (WKDownload doesn't hand the
    /// destination back). Keyed by object identity; cleared on finish/failure.
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    /// Downloads still running. The set holds the `WKDownload` objects, not
    /// only their identities, so a cancel can reach a download that never
    /// delivers a terminal callback.
    private var activeDownloads: Set<WKDownload> = []

    /// Coordinators with a download in flight.
    ///
    /// Membership keeps a coordinator alive until its last download ends. The
    /// coordinator is otherwise retained only by `WebViewPool.coordinators`,
    /// and `WKDownload.delegate` is weak. Without this set, evicting or
    /// hibernating the web view mid-download would release the coordinator,
    /// drop the delegate, lose `downloadDestinations`, and silently abort the
    /// transfer. The set also lets `cancelAllDownloads()` reach downloads whose
    /// web view is already gone, so quitting stops every transfer.
    private static var coordinatorsWithDownloads: Set<WebViewCoordinator> = []

    private func trackDownload(_ download: WKDownload) {
        activeDownloads.insert(download)
        Self.coordinatorsWithDownloads.insert(self)
    }

    private func untrackDownload(_ download: WKDownload) {
        activeDownloads.remove(download)
        if activeDownloads.isEmpty { Self.coordinatorsWithDownloads.remove(self) }
    }

    /// Cancels every in-flight download of this coordinator and releases it
    /// from the download registry. Called when the content process dies (such
    /// downloads cannot be relied on to deliver a terminal callback) and during
    /// shutdown. An aborted transfer is acceptable in both cases; the user can
    /// retry.
    func cancelActiveDownloads() {
        guard !activeDownloads.isEmpty else { return }
        for download in activeDownloads { download.cancel(nil) }
        activeDownloads.removeAll()
        downloadDestinations.removeAll()
        Self.coordinatorsWithDownloads.remove(self)
    }

    /// Cancels every in-flight download in the process, including downloads
    /// whose web view was already torn down. `Command-Q` must stop all work.
    static func cancelAllDownloads() {
        for coordinator in coordinatorsWithDownloads {
            coordinator.cancelActiveDownloads()
        }
        coordinatorsWithDownloads.removeAll()
    }

    // Save straight to the user's Downloads folder — the browser-like default —
    // rather than prompting with a save panel for every file. WKDownload fails
    // if the destination already exists, so we pick a non-colliding name.
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String
    ) async -> URL? {
        let fileManager = FileManager.default
        let downloads: URL
        do {
            downloads = try fileManager.url(
                for: .downloadsDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        } catch {
            AppLogger.webView.error("Couldn't locate the Downloads folder: \(error.localizedDescription)")
            return nil
        }

        let filename = WebRoutingPolicy.sanitizedDownloadFilename(suggestedFilename)
        let destination = Self.nonCollidingURL(
            in: downloads,
            filename: filename,
            fileExists: { fileManager.fileExists(atPath: $0.path) }
        )
        downloadDestinations[ObjectIdentifier(download)] = destination
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let destination = downloadDestinations.removeValue(forKey: key)
        untrackDownload(download)
        guard let destination else { return }
        AppLogger.webView.info("Download finished: \(destination.lastPathComponent)")
        // Bounce the Downloads stack in the Dock — the standard macOS
        // "download finished" feedback, so the user can see where it landed.
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("com.apple.DownloadFileFinished"),
            object: destination.path
        )
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        untrackDownload(download)
        AppLogger.webView.error("Download failed: \(error.localizedDescription)")
    }

    // MARK: - Helpers

    /// Whether the response asks to be saved rather than displayed, i.e. it
    /// carries a `Content-Disposition: attachment` header. Used so a downloadable
    /// file WebKit could otherwise render inline (a PDF, an image) still saves.
    nonisolated static func isAttachment(_ response: URLResponse) -> Bool {
        guard let http = response as? HTTPURLResponse,
              let disposition = http.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }
        return disposition.lowercased().contains("attachment")
    }

    /// Returns a URL in `directory` for `filename` that no file occupies,
    /// inserting " (1)", " (2)", … before the extension on collisions — matching
    /// how browsers de-duplicate downloads. `fileExists` is injected so the
    /// logic is testable without touching the disk.
    nonisolated static func nonCollidingURL(
        in directory: URL,
        filename: String,
        fileExists: (URL) -> Bool
    ) -> URL {
        let candidate = directory.appendingPathComponent(filename)
        guard fileExists(candidate) else { return candidate }

        let ns = filename as NSString
        let ext = ns.pathExtension
        let base = ns.deletingPathExtension
        var index = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            let url = directory.appendingPathComponent(name)
            if !fileExists(url) { return url }
            index += 1
        }
    }

}

/// Drives a file-open panel to a single completion. WebKit hangs the page's
/// `<input type=file>` until the handler fires exactly once, so this guarantees
/// it fires — on selection, cancel, or the host window closing first — and never
/// twice. `@MainActor` (hence Sendable) so the close observer can hold it.
@MainActor
private final class FilePickerSession {
    private var completion: (@MainActor ([URL]?) -> Void)?
    private var closeObserver: NSObjectProtocol?

    init(_ completion: @escaping @MainActor ([URL]?) -> Void) {
        self.completion = completion
    }

    /// Fires the completion with nil if `window` closes before the panel does,
    /// releasing the page's file input instead of leaving it hung.
    func observeClose(of window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // The .main queue delivers this on the main thread, so assuming main
            // isolation to reach the @MainActor method is safe here.
            MainActor.assumeIsolated { self?.finish(nil) }
        }
    }

    /// Idempotent: the first call fires the handler and detaches the observer;
    /// later calls are no-ops.
    func finish(_ urls: [URL]?) {
        guard let completion else { return }
        self.completion = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        completion(urls)
    }
}

/// Drives a JavaScript dialog (`alert` / `confirm` / `prompt`) to a single
/// completion. WebKit blocks the page's script until the handler fires exactly
/// once, so this guarantees it fires — on a button press or the host window
/// closing first — and never twice. `cancelValue` is what a window-close-first
/// resolves to (`()` for alert, `false` for confirm, nil for prompt). `@MainActor`
/// (hence Sendable) so the close observer can hold it.
@MainActor
private final class JSDialogSession<T> {
    private var completion: (@MainActor (T) -> Void)?
    private var closeObserver: NSObjectProtocol?
    private let cancelValue: T

    init(cancelValue: T, _ completion: @escaping @MainActor (T) -> Void) {
        self.cancelValue = cancelValue
        self.completion = completion
    }

    /// Fires the completion with `cancelValue` if `window` closes before the sheet
    /// resolves, releasing the page's blocked script instead of leaving it hung.
    func observeClose(of window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            // The .main queue delivers this on the main thread, so assuming main
            // isolation to reach the @MainActor method is safe here.
            MainActor.assumeIsolated { self?.finish(self?.cancelValue) }
        }
    }

    /// Idempotent: the first call fires the handler and detaches the observer;
    /// later calls are no-ops. `value` is nil only on the close path above, where
    /// it falls back to `cancelValue`.
    func finish(_ value: T?) {
        guard let completion else { return }
        self.completion = nil
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
            self.closeObserver = nil
        }
        completion(value ?? cancelValue)
    }
}
