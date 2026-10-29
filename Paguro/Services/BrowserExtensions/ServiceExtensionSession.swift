#if !APP_STORE
import AppKit
import Foundation
import PaguroCore
import SwiftUI
import WebKit

/// Each controller sees one account and its visible extension pages.
@available(macOS 15.4, *)
@MainActor
final class ServiceExtensionSession: NSObject, WKWebExtensionControllerDelegate, WKWebExtensionTab, WKWebExtensionWindow {
    let controller: WKWebExtensionController
    let profile: ExtensionRuntimeProfile
    private(set) var contexts: [UUID: WKWebExtensionContext] = [:]
    private weak var serviceWebView: WKWebView?
    /// The pool can release the view before it calls `close()`, so the weak
    /// reference alone cannot tell whether WebKit still has an open tab.
    private var hasOpenTab = false
    private weak var actionAnchor: NSView?
    private var isActive = false
    private(set) var pages: [BrowserExtensionPageController] = []
    private(set) var runtimeIssues: [UUID: [String]] = [:]
    private var issuePopover: NSPopover?
    private var popupRequest = UUID()
    private let serviceName: String
    var permissionServiceName: String { serviceName }
    let permissionPrompt = BrowserExtensionPermissionPrompt()
    var optionalChoices: [UUID: ExtensionOptionalAccess] = [:]
    var isApplyingOptionalAccess = false
    var permissionEpoch = UUID()
    var permissionPopupHolds: [ObjectIdentifier: (popover: NSPopover, behavior: NSPopover.Behavior, count: Int)] = [:]
    var saveOptionalAccess: (UUID, ExtensionOptionalAccess) -> Bool = { _, _ in false }
    var onIssuesChanged: (() -> Void)?
    var onActionChanged: (() -> Void)?

    init(serviceID: UUID, storeID: UUID, dataStore: WKWebsiteDataStore, serviceName: String = "Service",
         profile: ExtensionRuntimeProfile = .standard,
         extensionViewConfiguration: WKWebViewConfiguration = WKWebViewConfiguration()) {
        self.serviceName = serviceName
        self.profile = profile
        let configuration = dataStore.isPersistent
            ? WKWebExtensionController.Configuration(identifier: storeID)
            : .nonPersistent()
        // The default is WebKit's shared store, even when the tab has its own store.
        configuration.defaultWebsiteDataStore = dataStore
        let extensionViews = extensionViewConfiguration
        BrowserExtensionAPICompatibility.configure(extensionViews)
        extensionViews.websiteDataStore = dataStore
        if let name = profile.applicationNameForUserAgent { extensionViews.applicationNameForUserAgent = name }
        configuration.webViewConfiguration = extensionViews
        controller = WKWebExtensionController(configuration: configuration)
        super.init()
        controller.delegate = self
    }

    func load(_ webExtension: WKWebExtension, id: UUID, packageSHA256: String = "", optionalAccess: ExtensionOptionalAccess? = nil) throws {
        let context = WKWebExtensionContext(for: webExtension)
        context.uniqueIdentifier = id.uuidString
        context.baseURL = URL(string: "webkit-extension://\(id.uuidString.lowercased())/")!
        optionalChoices[id] = optionalAccess ?? ExtensionOptionalAccess(packageSHA256: packageSHA256)
        applyOptionalAccess(optionalChoices[id], to: context)
        try controller.load(context)
        contexts[id] = context
        NotificationCenter.default.addObserver(self, selector: #selector(contextErrorsChanged(_:)),
            name: WKWebExtensionContext.errorsDidUpdateNotification, object: context)
        for name in [WKWebExtensionContext.grantedPermissionsWereRemovedNotification,
                     WKWebExtensionContext.grantedPermissionMatchPatternsWereRemovedNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(optionalAccessRemoved(_:)), name: name, object: context)
        }
        refreshIssues(context, id: id)
    }

    func open(_ webView: WKWebView) {
        serviceWebView = webView
        hasOpenTab = true
        controller.didOpenWindow(self)
        controller.didOpenTab(self)
    }

    func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        controller.didFocusWindow(active ? self : nil)
        if active {
            controller.didActivateTab(self, previousActiveTab: nil)
            controller.didSelectTabs([self])
        } else {
            controller.didDeselectTabs([self])
            closeSurfaces()
        }
    }

    func didNavigate() { controller.didChangeTabProperties([.URL, .title, .loading], for: self) }

    var actions: [(id: UUID, action: WKWebExtension.Action)] {
        contexts.compactMap { id, context in context.action(for: self).map { (id, $0) } }
            .sorted { $0.action.label.localizedStandardCompare($1.action.label) == .orderedAscending }
    }

    /// Items the extension registered with `menus.create` for its toolbar
    /// button and for the tab. WebKit leaves showing them to the app. It adds
    /// page items to the page's own context menu by itself. The items can
    /// change at any time, so fetch them right before a menu opens.
    func menuItems(_ id: UUID) -> [NSMenuItem] {
        guard isActive, serviceWebView != nil, let context = contexts[id] else { return [] }
        return (context.action(for: self)?.menuItems ?? []) + context.menuItems(for: self)
    }

    func perform(_ id: UUID, from anchor: NSView) {
        guard isActive, serviceWebView != nil, let context = contexts[id] else { return }
        actionAnchor = anchor
        popupRequest = UUID()
        issuePopover?.close()
        refreshIssues(context, id: id)
        context.userGesturePerformed(in: self)
        context.performAction(for: self)
    }

    func close() {
        isActive = false
        closeSurfaces()
        NotificationCenter.default.removeObserver(self)
        runtimeIssues.removeAll()
        optionalChoices.removeAll()
        if hasOpenTab {
            hasOpenTab = false
            controller.didCloseTab(self, windowIsClosing: true)
            controller.didCloseWindow(self)
        }
        for context in contexts.values { try? controller.unload(context) }
        contexts.removeAll()
        controller.delegate = nil
        serviceWebView = nil
        actionAnchor = nil
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openWindowsFor context: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        serviceWebView == nil ? [] : [self] + pages
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                focusedWindowFor context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        isActive ? (pages.first { $0.window?.isKeyWindow == true } ?? self) : nil
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        onActionChanged?()
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext) async throws {
        guard isActive, let anchor = actionAnchor, anchor.window != nil,
              let popover = action.popupPopover else {
            throw CocoaError(.userCancelled)
        }
        let request = popupRequest
        try await BrowserExtensionPopupContentController.present(popover, relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY) { [weak self] in
            guard let self else { return false }
            return self.isActive && self.popupRequest == request && self.actionAnchor === anchor
                && self.contexts.values.contains(where: { $0 === context })
        }
    }

    // New windows, native messages, and downloads stay denied.
    // New tabs are visible account-owned windows, with a bounded lifetime.
    func webExtensionController(_ controller: WKWebExtensionController,
                                openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for context: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        if let requestedWindow = configuration.window {
            guard requestedWindow === self || pages.contains(where: { $0 === requestedWindow }) else {
                throw CocoaError(.userCancelled)
            }
        }
        return try openPage(configuration.url ?? URL(string: "about:blank")!, for: context)
    }

    func webExtensionController(_ controller: WKWebExtensionController,
                                openOptionsPageFor context: WKWebExtensionContext) async throws {
        guard let url = context.optionsPageURL else { throw CocoaError(.fileNoSuchFile) }
        _ = try openPage(url, for: context)
    }

    @discardableResult
    func openPage(_ url: URL, for context: WKWebExtensionContext) throws -> BrowserExtensionPageController {
        guard isActive, serviceWebView != nil, contexts.values.contains(where: { $0 === context }),
              (context.hasActiveUserGesture(in: self) || pages.contains { context.hasActiveUserGesture(in: $0) }),
              pages.count < ExtensionPagePolicy.maximumOpenPages,
              ExtensionPagePolicy.allows(url, extensionBaseURL: context.baseURL) else { throw CocoaError(.userCancelled) }
        let page = BrowserExtensionPageController(configuration: pageConfiguration(for: url, context: context),
            baseURL: context.baseURL, context: context,
            title: "\(context.webExtension.displayName ?? "Extension") · \(serviceName)", session: self)
        pages.append(page)
        controller.didOpenWindow(page)
        controller.didOpenTab(page)
        context.action(for: self)?.closePopup()
        page.show(url)
        return page
    }

    func openOptions(_ id: UUID, from anchor: NSView) {
        guard isActive, let context = contexts[id], let url = context.optionsPageURL else { return }
        actionAnchor = anchor
        popupRequest = UUID()
        context.userGesturePerformed(in: self)
        do { try openPage(url, for: context) }
        catch {
            showDiagnostics(id, from: anchor, summary:
                "Could not open the settings page. Close other extension pages and try again.")
        }
    }

    func pageConfiguration(for url: URL, context: WKWebExtensionContext) -> WKWebViewConfiguration {
        let configuration = url.scheme?.lowercased() == context.baseURL.scheme?.lowercased()
            ? (context.webViewConfiguration ?? WKWebViewConfiguration()) : WKWebViewConfiguration()
        configuration.websiteDataStore = controller.configuration.defaultWebsiteDataStore
        configuration.webExtensionController = controller
        if let name = profile.applicationNameForUserAgent { configuration.applicationNameForUserAgent = name }
        return configuration
    }

    func pageDidClose(_ page: BrowserExtensionPageController) {
        guard pages.contains(where: { $0 === page }) else { return }
        controller.didCloseTab(page, windowIsClosing: true)
        controller.didCloseWindow(page)
        pages.removeAll { $0 === page }
        controller.didFocusWindow(isActive ? self : nil)
    }

    func pageDidFocus(_ page: BrowserExtensionPageController) {
        guard isActive, pages.contains(where: { $0 === page }) else { return }
        controller.didFocusWindow(page)
        controller.didActivateTab(page, previousActiveTab: nil)
    }

    private func closeSurfaces() {
        popupRequest = UUID()
        permissionEpoch = UUID()
        permissionPrompt.cancel()
        issuePopover?.close()
        issuePopover = nil
        for context in contexts.values {
            context.action(for: self)?.closePopup()
            context.clearUserGesture(in: self)
        }
        for page in pages { page.close() }
    }

    @objc private func contextErrorsChanged(_ notification: Notification) {
        guard let context = notification.object as? WKWebExtensionContext,
              let id = contexts.first(where: { $0.value === context })?.key else { return }
        refreshIssues(context, id: id)
    }

    private func refreshIssues(_ context: WKWebExtensionContext, id: UUID) {
        let messages = Array(Set(context.errors.prefix(8).map { String($0.localizedDescription.prefix(1_024)) })).sorted()
        guard runtimeIssues[id] != messages else { return }
        runtimeIssues[id] = messages
        onIssuesChanged?()
    }

    func showDiagnostics(_ id: UUID, from anchor: NSView,
                         summary: String = "WebKit reported runtime diagnostics. Some features may not work.") {
        guard isActive, serviceWebView != nil, anchor.window != nil, let context = contexts[id] else { return }
        popupRequest = UUID()
        context.action(for: self)?.closePopup()
        issuePopover?.close()
        refreshIssues(context, id: id)
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: BrowserExtensionIssueView(
            name: context.webExtension.displayName ?? "Extension", summary: summary,
            messages: runtimeIssues[id] ?? []))
        issuePopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    func permissionWindow(for context: WKWebExtensionContext, in tab: (any WKWebExtensionTab)?) -> NSWindow? {
        guard isActive, contexts.values.contains(where: { $0 === context }), serviceWebView != nil else { return nil }
        if let tab, tab !== self, !pages.contains(where: { $0 === tab }) { return nil }
        guard context.hasActiveUserGesture(in: tab ?? self) || context.hasActiveUserGesture(in: self) else { return nil }
        let window = (tab as? BrowserExtensionPageController)?.window ?? serviceWebView?.window
        return window?.isVisible == true ? window : nil
    }

    func permissionRequestIsCurrent(_ epoch: UUID, context: WKWebExtensionContext) -> Bool {
        isActive && permissionEpoch == epoch && contexts.values.contains(where: { $0 === context })
    }

    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { serviceWebView == nil ? [] : [self] }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { isActive ? self : nil }
    func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { self }
    func indexInWindow(for context: WKWebExtensionContext) -> Int { 0 }
    func webView(for context: WKWebExtensionContext) -> WKWebView? { serviceWebView }
    func isSelected(for context: WKWebExtensionContext) -> Bool { isActive }
    func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { false }
}
#endif
