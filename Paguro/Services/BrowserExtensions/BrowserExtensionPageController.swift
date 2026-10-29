#if !APP_STORE
import AppKit
import PaguroCore
import WebKit

/// A visible extension page belongs to the service that created it.
@available(macOS 15.4, *)
@MainActor
final class BrowserExtensionPageController: NSWindowController, NSWindowDelegate,
    WKNavigationDelegate, WKUIDelegate, WKWebExtensionTab, WKWebExtensionWindow {
    private(set) var pageView: WKWebView
    private let context: WKWebExtensionContext
    private var usesExtensionConfiguration: Bool
    private let baseURL: URL
    private weak var session: ServiceExtensionSession?
    private let address = NSTextField(labelWithString: "")
    private let message = NSTextField(wrappingLabelWithString: "")
    private var isClosed = false
    private let windowTitle: String

    init(configuration: WKWebViewConfiguration, baseURL: URL, context: WKWebExtensionContext, title: String, session: ServiceExtensionSession) {
        pageView = WKWebView(frame: NSRect(x: 0, y: 0, width: 900, height: 650), configuration: configuration)
        self.baseURL = baseURL
        self.context = context
        usesExtensionConfiguration = false
        self.session = session
        windowTitle = title
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = title
        window.minSize = NSSize(width: 480, height: 360)
        super.init(window: window)
        window.delegate = self
        pageView.navigationDelegate = self
        pageView.uiDelegate = self
        buildContent(window)
    }

    required init?(coder: NSCoder) { nil }

    private func buildContent(_ window: NSWindow) {
        let back = NSButton(title: "Back", target: self, action: #selector(goBack))
        let reload = NSButton(title: "Reload", target: self, action: #selector(reloadPage))
        address.lineBreakMode = .byTruncatingMiddle
        address.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        address.isSelectable = true
        address.setAccessibilityLabel("Extension page address")
        message.textColor = .systemRed
        message.isHidden = true
        let bar = NSStackView(views: [back, reload, address])
        bar.spacing = 8
        bar.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
        let stack = NSStackView(views: [bar, message, pageView])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        window.contentView = stack
        for item in [bar, message, pageView] {
            item.translatesAutoresizingMaskIntoConstraints = false
            item.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        pageView.setContentHuggingPriority(.defaultLow, for: .vertical)
    }

    func show(_ url: URL) {
        usesExtensionConfiguration = url.scheme?.lowercased() == baseURL.scheme?.lowercased()
        address.stringValue = url.absoluteString
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        pageView.load(URLRequest(url: url))
    }

    override func close() {
        tearDown()
        super.close()
    }

    private func tearDown() {
        guard !isClosed else { return }
        isClosed = true
        pageView.stopLoading()
        pageView.navigationDelegate = nil
        pageView.uiDelegate = nil
        session?.pageDidClose(self)
        session = nil
    }

    func windowWillClose(_ notification: Notification) { tearDown() }
    func windowDidBecomeKey(_ notification: Notification) { session?.pageDidFocus(self) }

    @objc private func goBack() { pageView.goBack() }
    @objc private func reloadPage() { message.isHidden = true; pageView.reload() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        let isMainFrame = navigationAction.targetFrame?.isMainFrame != false
        let isAllowed: (URL) -> Bool = { [baseURL] url in
            isMainFrame
                ? ExtensionPagePolicy.allows(url, extensionBaseURL: baseURL)
                : ExtensionPagePolicy.allowsSubframe(url, extensionBaseURL: baseURL)
        }
        guard let url = navigationAction.request.url, isAllowed(url),
              !navigationAction.shouldPerformDownload else {
            showMessage("This extension page requested an unsupported address or download.")
            return .cancel
        }
        let needsExtensionConfiguration = url.scheme?.lowercased() == baseURL.scheme?.lowercased()
        if isMainFrame, needsExtensionConfiguration != usesExtensionConfiguration {
            replacePage(for: navigationAction.request)
            return .cancel
        }
        return .allow
    }

    // WebKit requires different configurations for extension and ordinary pages.
    private func replacePage(for request: URLRequest) {
        guard let session, let url = request.url, let stack = pageView.superview as? NSStackView else { return }
        let old = pageView
        old.stopLoading()
        old.navigationDelegate = nil
        old.uiDelegate = nil
        let replacement = WKWebView(frame: old.frame, configuration: session.pageConfiguration(for: url, context: context))
        replacement.navigationDelegate = self
        replacement.uiDelegate = self
        replacement.translatesAutoresizingMaskIntoConstraints = false
        replacement.setContentHuggingPriority(.defaultLow, for: .vertical)
        stack.removeArrangedSubview(old)
        old.removeFromSuperview()
        stack.addArrangedSubview(replacement)
        replacement.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        pageView = replacement
        usesExtensionConfiguration = url.scheme?.lowercased() == baseURL.scheme?.lowercased()
        replacement.load(request)
        session.controller.didChangeTabProperties([.URL, .loading], for: self)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .cancel
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        address.stringValue = webView.url?.absoluteString ?? ""
        if let title = webView.title, !windowTitle.hasPrefix("\(title) · ") {
            window?.title = "\(title) · \(windowTitle)"
        } else {
            window?.title = windowTitle
        }
        session?.controller.didChangeTabProperties([.URL, .title, .loading], for: self)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        if (error as NSError).code != NSURLErrorCancelled { showMessage(error.localizedDescription) }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        showMessage(error.localizedDescription)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        showMessage("The extension page stopped. Select Reload to try again.")
    }

    private func showMessage(_ text: String) {
        message.stringValue = String(text.prefix(1_024))
        message.isHidden = false
    }

    // Keep page-owned links in this visible window. Do not create unmanaged views.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, ExtensionPagePolicy.allows(url, extensionBaseURL: baseURL) {
            pageView.load(navigationAction.request)
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping @MainActor (WKPermissionDecision) -> Void) {
        decisionHandler(.deny)
    }

    func webViewDidClose(_ webView: WKWebView) { close() }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { [self] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { self }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { pageView }
    func isSelected(for context: WKWebExtensionContext) -> Bool { true }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { false }

    func activate(for context: WKWebExtensionContext) async throws { window?.makeKeyAndOrderFront(nil) }
    func close(for context: WKWebExtensionContext) async throws { close() }
    func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws {
        guard ExtensionPagePolicy.allows(url, extensionBaseURL: baseURL) else { throw CocoaError(.fileReadUnsupportedScheme) }
        pageView.load(URLRequest(url: url))
    }
}
#endif
