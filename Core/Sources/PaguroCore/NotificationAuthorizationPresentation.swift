/// The macOS notification permission, held without a platform API.
///
/// The app maps `UNAuthorizationStatus` to this value at the platform
/// boundary, so presentation rules stay testable in `PaguroCore`.
public enum NotificationAuthorizationState: String, Equatable, Sendable, CaseIterable {
    /// Paguro has not read the permission yet.
    case unknown
    /// macOS has no stored decision for Paguro.
    case notDetermined
    /// macOS withholds the permission.
    case denied
    /// macOS permits banners and sounds.
    case authorized
    /// macOS delivers to the Notification Center without a banner.
    case provisional
    /// The permission request could not run.
    ///
    /// macOS never registered Paguro for notifications, so it refused the
    /// request instead of asking the user. This is not a refusal by the user,
    /// and Paguro must try again on the next launch.
    case unavailable
}

/// The Settings warning that explains a missing notification permission.
public struct NotificationAuthorizationWarning: Equatable, Sendable {
    public let title: String
    public let message: String
    public let actionTitle: String

    public init(title: String, message: String, actionTitle: String) {
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
    }
}

/// Maps the notification permission to the state that Settings shows.
///
/// A denied or undetermined permission makes macOS drop every banner. The
/// app still adds each request, and `UNUserNotificationCenter` still accepts
/// it, so nothing else reports the loss. Settings must therefore name it.
public enum NotificationAuthorizationPresentation {
    /// The System Settings pane that holds the per-app notification controls.
    public static let systemSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.notifications"

    /// Tells whether macOS shows a banner for a Paguro notification.
    public static func showsSystemBanners(
        for state: NotificationAuthorizationState
    ) -> Bool {
        state == .authorized
    }

    /// Returns the warning for a permission that hides banners.
    ///
    /// An authorized permission returns `nil`, so Settings shows no row.
    /// An unknown permission also returns `nil`: Paguro has not read the
    /// permission yet, and a warning before the first read would flash.
    public static func warning(
        for state: NotificationAuthorizationState
    ) -> NotificationAuthorizationWarning? {
        switch state {
        case .authorized, .unknown:
            return nil
        case .notDetermined:
            return NotificationAuthorizationWarning(
                title: "macOS has not granted notification permission",
                message: """
                    Paguro cannot show a macOS notification until you allow \
                    notifications for Paguro. Island alerts on a display \
                    without a notch use the same permission.
                    """,
                actionTitle: "Open Notification Settings"
            )
        case .denied:
            return NotificationAuthorizationWarning(
                title: "macOS blocks Paguro notifications",
                message: """
                    Notifications for Paguro are off in System Settings, so \
                    macOS drops every banner. Turn on "Allow notifications" \
                    for Paguro to see service alerts again.
                    """,
                actionTitle: "Open Notification Settings"
            )
        case .provisional:
            return NotificationAuthorizationWarning(
                title: "macOS delivers Paguro notifications quietly",
                message: """
                    macOS sends Paguro alerts to the Notification Center \
                    without a banner. Turn on "Allow notifications" for \
                    Paguro to see each alert on screen.
                    """,
                actionTitle: "Open Notification Settings"
            )
        case .unavailable:
            return NotificationAuthorizationWarning(
                title: "macOS did not register Paguro for notifications",
                message: """
                    macOS refused the permission request, so it never asked \
                    you and Paguro does not appear in the notification \
                    settings. Move Paguro to the Applications folder and open \
                    it once from there. macOS then registers the app and asks \
                    for the permission. Paguro tries again at each start.
                    """,
                actionTitle: "Open Notification Settings"
            )
        }
    }
}
