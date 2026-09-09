import AppKit
import PaguroCore
import Foundation
import WebKit

/// Owns the window and lifecycle of one authentication or new-window popup.
@MainActor
final class AuthPopupController: NSObject, NSWindowDelegate {
    private var popupWebView: WKWebView?
    private var popupWindow: NSWindow?
    private var titleObservation: NSKeyValueObservation?
    private weak var openerWebView: WKWebView?
    private var openerFallbackURL: URL?
    private var openedAtAuthenticationHost = false
    private var crashTimestamps: [Date] = []

    deinit {
        titleObservation?.invalidate()
        if let window = popupWindow {
            Task { @MainActor in
                window.delegate = nil
                window.close()
            }
        }
    }

    /// Creates a popup or loads a same-service link in the existing web view.
    func createWebView(
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
        opener: WKWebView,
        fallbackURL: URL?,
        navigationDelegate: any WKNavigationDelegate,
        uiDelegate: any WKUIDelegate
    ) -> WKWebView? {
        // Real same-service links can reuse the current view. Programmatic
        // window.open calls need a real window handle or sign-in flows can
        // mistake the request for a blocked popup.
        if WebRoutingPolicy.shouldLoadNewWindowInPlace(
            isLinkActivated: navigationAction.navigationType == .linkActivated,
            targetHost: navigationAction.request.url?.host,
            openerHost: opener.url?.host
        ) {
            opener.load(navigationAction.request)
            return nil
        }

        cleanup()
        openerWebView = opener
        openerFallbackURL = fallbackURL
        openedAtAuthenticationHost = navigationAction.request.url?.host
            .map(WebRoutingPolicy.isAuthenticationHost) ?? false

        // The supplied configuration shares the opener's website data store.
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.customUserAgent = opener.customUserAgent ?? UserAgentProvider.safariDefault
        popup.navigationDelegate = navigationDelegate
        popup.uiDelegate = uiDelegate

        let requestedWidth = windowFeatures.width?.doubleValue ?? 0
        let requestedHeight = windowFeatures.height?.doubleValue ?? 0
        let width = max(640, min(1400, requestedWidth > 0 ? requestedWidth : 1100))
        let height = max(480, min(1000, requestedHeight > 0 ? requestedHeight : 800))

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // This controller owns the window and releases it after close. AppKit
        // must not also release it.
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = popup
        window.title = navigationAction.request.url?.host ?? "Paguro"
        window.center()
        window.makeKeyAndOrderFront(nil)

        popupWebView = popup
        popupWindow = window
        observeTitle(of: popup, in: window)
        return popup
    }

    func isPopup(_ webView: WKWebView) -> Bool {
        webView === popupWebView
    }

    /// Handles a completed popup navigation and closes a returned sign-in flow.
    /// Returns true when the web view is the managed popup.
    func handleNavigationFinished(_ webView: WKWebView) -> Bool {
        guard isPopup(webView) else { return false }
        if WebRoutingPolicy.shouldCloseAuthenticationPopup(
            openedAtAuthenticationHost: openedAtAuthenticationHost,
            landedHost: webView.url?.host,
            openerHost: openerWebView?.url?.host,
            serviceHost: openerFallbackURL?.host
        ) {
            AppLogger.webView.info("Authentication popup returned to the service; closing it")
            reloadOpener(selfClosed: false)
            cleanup()
        }
        return true
    }

    /// Handles popup process failure with the coordinator's crash rule. Returns
    /// true when the web view is the managed popup.
    func handleProcessTermination(
        _ webView: WKWebView,
        at now: Date,
        within window: TimeInterval,
        shouldAutoReload: ([Date], Date) -> Bool
    ) -> Bool {
        guard isPopup(webView) else { return false }
        crashTimestamps.append(now)
        crashTimestamps = crashTimestamps.filter { now.timeIntervalSince($0) <= window }

        guard shouldAutoReload(crashTimestamps, now) else {
            AppLogger.webView.error("OAuth popup WebContent terminated repeatedly — closing popup")
            cleanup()
            return true
        }
        if webView.url != nil { webView.reload() }
        return true
    }

    /// Handles a popup that closes itself with JavaScript.
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        guard isPopup(webView) else { return false }
        reloadOpener(selfClosed: true)
        cleanup()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === popupWindow else { return }
        reloadOpener(selfClosed: false)
        cleanup(closeWindow: false)
    }

    private func observeTitle(of popup: WKWebView, in window: NSWindow) {
        titleObservation?.invalidate()
        titleObservation = popup.observe(\.title, options: [.new]) { [weak window] _, change in
            guard let newTitle = change.newValue ?? nil, !newTitle.isEmpty else { return }
            Task { @MainActor in
                window?.title = newTitle
            }
        }
    }

    private func reloadOpener(selfClosed: Bool) {
        guard WebRoutingPolicy.shouldReloadOpener(
            selfClosed: selfClosed,
            openedAtAuthenticationHost: openedAtAuthenticationHost
        ), let opener = openerWebView else { return }

        if let openerFallbackURL,
           opener.url == nil || WebRoutingPolicy.shouldLoadServiceHomeAfterAuthentication(
               openedAtAuthenticationHost: openedAtAuthenticationHost,
               openerHost: opener.url?.host,
               serviceHost: openerFallbackURL.host
           ) {
            opener.load(URLRequest(url: openerFallbackURL))
        } else if opener.url != nil {
            opener.reload()
        }
    }

    private func cleanup(closeWindow: Bool = true) {
        titleObservation?.invalidate()
        titleObservation = nil
        popupWebView?.navigationDelegate = nil
        popupWebView?.uiDelegate = nil
        popupWindow?.delegate = nil
        if closeWindow { popupWindow?.close() }
        popupWebView = nil
        popupWindow = nil
        openerWebView = nil
        openerFallbackURL = nil
        crashTimestamps = []
        openedAtAuthenticationHost = false
    }
}
