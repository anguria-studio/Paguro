import Foundation
import WebKit
import AppKit
import os
import BlattaCore

@MainActor
final class WebViewCoordinator: NSObject, WKNavigationDelegate, WKUIDelegate {

    private let downloadHandler = WebDownloadHandler()
    private let dialogPresenter = WebDialogPresenter()
    private let authPopupController = AuthPopupController()

    /// Fallback URL to load if the WebContent process crashes before any
    /// navigation has committed (so `webView.reload()` has nothing to retry).
    var fallbackURL: URL?

    /// Timestamps of recent WebContent terminations, used to break a crash →
    /// reload → crash loop. Accessed only from main-thread delegate callbacks.
    private var crashTimestamps: [Date] = []
    // nonisolated so the nonisolated `shouldAutoReload` can use them as default
    // argument values — they're immutable Sendable constants.
    private nonisolated static let maxCrashesInWindow = 3
    private nonisolated static let crashWindow: TimeInterval = 30

    /// Routes external/cross-domain navigations through AppState so it can
    /// match the URL against an existing Blatta service before falling back
    /// to the system browser. The second argument is the source service's id
    /// (`instanceID`), so AppState can honour that service's "open links in
    /// Blatta" choice. When nil the coordinator falls back to `NSWorkspace.open`
    /// directly.
    var externalLinkHandler: ((URL, UUID?) -> Void)?

    /// The service this coordinator drives, set by `WebViewPool` so navigation
    /// callbacks can be attributed to a specific service.
    var instanceID: UUID? {
        didSet { downloadHandler.serviceID = instanceID }
    }

    /// The header's download list, set by `WebViewPool`. The coordinator only
    /// forwards it to the handler that owns the transfers.
    var downloadTracker: DownloadTracker? {
        didSet { downloadHandler.tracker = downloadTracker }
    }

    /// Called when a top-level navigation finishes (fresh load or login
    /// redirect) so the app can fire an immediate badge poll instead of waiting
    /// for the next poll tick. Never called for OAuth popup web views.
    var onNavigationFinished: ((UUID) -> Void)?

    /// Reports a navigation event for this service so the pool can keep a health
    /// state the rail can draw. Set by `WebViewPool`. Never called for OAuth
    /// popup web views: a popup's failure is the popup's business, and the
    /// service behind it is still fine.
    var onHealthEvent: ((UUID, ServiceHealth.Event) -> Void)?

    /// Set just before Blatta loads one of its own error pages into the web
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

    /// Whether a link that leaves a service (and that no other Blatta service
    /// owns) should open in an in-app Blatta window rather than the system
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
            let context = authPopupController.isPopup(webView) ? "popup" : "service"
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
        if WebDownloadHandler.isAttachment(navigationResponse.response) {
            return .download
        }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if authPopupController.handleNavigationFinished(webView) { return }

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
        let now = Date()
        if authPopupController.handleProcessTermination(
            webView,
            at: now,
            within: Self.crashWindow,
            shouldAutoReload: { timestamps, date in
                Self.shouldAutoReload(crashTimestamps: timestamps, now: date)
            }
        ) { return }

        // A terminated content process cannot be trusted to deliver a final
        // download callback. Cancel its transfers and release their handler.
        downloadHandler.cancelActiveDownloads()

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
            let html = ErrorPage.html(
                title: "This page keeps crashing",
                message: "Blatta stopped reloading it automatically to avoid a loop. You can try again, or switch to another service.",
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
        if authPopupController.isPopup(webView) { return }

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

        let html = ErrorPage.html(
            title: "Unable to connect",
            message: error.localizedDescription,
            retryURLString: failingURL
        )
        errorPageLoadInFlight = true
        webView.loadHTMLString(html, baseURL: nil)
    }

    // MARK: - Crash backoff

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

    // MARK: - UI Delegate (OAuth Pop-ups)

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        authPopupController.createWebView(
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures,
            opener: webView,
            fallbackURL: fallbackURL,
            navigationDelegate: self,
            uiDelegate: self
        )
    }

    func webViewDidClose(_ webView: WKWebView) {
        _ = authPopupController.handleWebViewDidClose(webView)
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
        dialogPresenter.presentOpenPanel(
            with: parameters,
            over: webView,
            completion: completionHandler
        )
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
        dialogPresenter.presentAlert(message: message, over: webView, completion: completionHandler)
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
        dialogPresenter.presentConfirm(message: message, over: webView, completion: completionHandler)
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
        dialogPresenter.presentPrompt(
            prompt: prompt,
            defaultText: defaultText,
            over: webView,
            completion: completionHandler
        )
    }

    // MARK: - Context Menu

    // WKWebView provides native context menus by default on macOS.
    // We add "Open Link in Browser" and "Copy Link" via the default
    // context menu handling. Custom context menus can be added via
    // WKUIDelegate methods if needed in the future.

    // MARK: - Download handoff

    func webView(
        _ webView: WKWebView,
        navigationAction: WKNavigationAction,
        didBecome download: WKDownload
    ) {
        downloadHandler.track(download)
    }

    func webView(
        _ webView: WKWebView,
        navigationResponse: WKNavigationResponse,
        didBecome download: WKDownload
    ) {
        downloadHandler.track(download)
    }

}
