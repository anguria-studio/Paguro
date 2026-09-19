/// The setup rows that the first-run home screen carries on this Mac.
///
/// Both rows are conditional, so the screen can hold one, the other, or
/// neither. A value with no row is not built, and the screen then omits its
/// card.
public struct FirstRunSetup: Equatable, Sendable {
    /// The notification row applies.
    ///
    /// The row reports a permission that macOS already holds as well as one it
    /// has not been asked for, because the home screen is the one place a new
    /// user sees that state. Only a permission macOS has not decided carries
    /// the Allow button; a stored decision routes to System Settings.
    public let showsNotificationRow: Bool
    /// The island row applies, because a connected display has a notch.
    public let showsIslandRow: Bool

    public init(showsNotificationRow: Bool, showsIslandRow: Bool) {
        self.showsNotificationRow = showsNotificationRow
        self.showsIslandRow = showsIslandRow
    }
}

/// What the main window shows before the user has a service.
public struct FirstRunPresentation: Equatable, Sendable {
    /// The home screen replaces the rail, the header, and the web content.
    public let showsHome: Bool
    /// The setup rows on the home screen, or nil when no row applies.
    public let setup: FirstRunSetup?
    /// Whether the actions of the home screen can run.
    ///
    /// The lock screen draws over the home screen and owns every action until
    /// the user unlocks.
    public let allowsActions: Bool

    public init(showsHome: Bool, setup: FirstRunSetup?, allowsActions: Bool) {
        self.showsHome = showsHome
        self.setup = setup
        self.allowsActions = allowsActions
    }
}

/// Decides between the first-run home screen and the shell.
///
/// A window with no service had nothing in it: an empty rail, an empty header,
/// and one line of gray text. The home screen takes that place. It carries the
/// first action and the two setup decisions that a new user could otherwise
/// only reach by finding System Settings or the Settings window.
public enum FirstRunPolicy {
    /// Returns what the main window shows.
    ///
    /// - Parameters:
    ///   - serviceCount: How many services exist in every workspace together.
    ///     A workspace says nothing about first run, because a workspace with
    ///     nothing in it is still an empty window. Count services alone.
    ///   - isLocked: Whether App Lock holds the window.
    ///   - authorization: What macOS currently says about the permission.
    ///   - islandIsAvailable: Whether a notched display is present.
    ///   - forcesPreview: The Debug preview argument. It shows the screen over
    ///     a full workspace and changes no stored value.
    public static func presentation(
        serviceCount: Int,
        isLocked: Bool,
        authorization: NotificationAuthorizationState,
        islandIsAvailable: Bool,
        forcesPreview: Bool = false
    ) -> FirstRunPresentation {
        // A user who deletes every service sees the screen again. That is
        // intended: the window is empty again, and the screen is what an empty
        // window says.
        let showsHome = serviceCount == 0 || forcesPreview
        return FirstRunPresentation(
            showsHome: showsHome,
            setup: showsHome
                ? setup(
                    authorization: authorization,
                    islandIsAvailable: islandIsAvailable
                )
                : nil,
            allowsActions: !isLocked
        )
    }

    /// Which setup rows this Mac needs, or nil when it needs none.
    ///
    /// An unread permission shows no notification row: the state would change
    /// under the user as soon as the launch read returns.
    public static func setup(
        authorization: NotificationAuthorizationState,
        islandIsAvailable: Bool
    ) -> FirstRunSetup? {
        let showsNotificationRow = authorization != .unknown
        guard showsNotificationRow || islandIsAvailable else { return nil }
        return FirstRunSetup(
            showsNotificationRow: showsNotificationRow,
            showsIslandRow: islandIsAvailable
        )
    }
}
