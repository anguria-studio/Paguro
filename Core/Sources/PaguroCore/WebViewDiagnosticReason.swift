import Foundation

/// Why the pool releases a service web view.
///
/// The raw value is a fixed string for a log line. It never contains a name,
/// a URL, or a page title.
public enum WebViewTeardownReason: String, Sendable, CaseIterable {
    /// The idle sweep or the immediate policy hibernated the service.
    case idleHibernation
    /// The pool released the service to stay below its capacity.
    case capacityEviction
    /// The user selected Hibernate for the service.
    case manualHibernation
    /// A settings change rebuilds the web view.
    case rebuild
    /// The service was removed.
    case removal
    /// Paguro quits.
    case quit

    /// Whether the teardown gets a persisted diagnostic line.
    ///
    /// Only a chat app gets one, because a chat app must stay loaded and a
    /// teardown can explain a later sign-out. Quit is expected and has its own
    /// flush line.
    public static func isLogged(_ reason: WebViewTeardownReason, isChatApp: Bool) -> Bool {
        isChatApp && reason != .quit
    }
}

/// Why Paguro itself starts a main-frame navigation or a reload.
///
/// The raw value is a fixed string for a log line. It never contains a name,
/// a URL, or a page title.
public enum AppInitiatedNavigationReason: String, Sendable, CaseIterable {
    /// A new web view loads the service for the first time in this run.
    case initialLoad
    /// A background preload creates the web view.
    case preload
    /// A fully hibernated service loads again.
    case wakeFromHibernation
    /// A rebuilt web view loads again after a settings change.
    case rebuild
    /// The WebContent process stopped and Paguro reloads the page.
    case crashRecoveryReload
    /// Paguro shows its recovery page after repeated crashes.
    case crashRecoveryPage
    /// Paguro shows its error page after a failed load.
    case errorPage
    /// The user selected Try Again on Paguro's error or recovery page.
    case errorPageRetry
    /// The user selected Reload.
    case userReload
    /// A click on a notification opens its destination.
    case notificationDestination
    /// Paguro routes a link from another service or window to this service.
    case linkRouting
    /// The user changed the service URL.
    case serviceURLChange
    /// The user agent changed, which reloads the page.
    case userAgentChange
    /// Clear Session removed the website data and reloads the page.
    case clearSession
    /// A sign-in popup closed and Paguro reloads the service page.
    case signInPopupClosed

    /// The reason for the first load of a new web view.
    public static func forNewWebView(
        wasHibernated: Bool,
        wasRebuilt: Bool
    ) -> AppInitiatedNavigationReason {
        if wasHibernated { return .wakeFromHibernation }
        if wasRebuilt { return .rebuild }
        return .initialLoad
    }
}
