/// What the first-run welcome has to offer on this machine.
///
/// Both offers are conditional, so the welcome can carry one, the other, or
/// neither. A welcome with nothing to offer is not shown at all.
public struct FirstRunWelcome: Equatable, Sendable {
    /// Blatta should ask macOS for the notification permission.
    public let asksForNotificationPermission: Bool
    /// The machine has a notch, so the island is worth offering.
    public let offersIsland: Bool

    public init(asksForNotificationPermission: Bool, offersIsland: Bool) {
        self.asksForNotificationPermission = asksForNotificationPermission
        self.offersIsland = offersIsland
    }
}

/// Decides what Blatta asks a new user before they have to find Settings.
///
/// Two things were unreachable without opening System Settings or the Settings
/// window: the notification permission, and the island. Both are decisions only
/// the user can make, and both are cheap to offer once at the start.
public enum FirstRunPolicy {
    /// Returns the welcome to show, or nil when there is nothing to ask.
    ///
    /// - Parameters:
    ///   - hasSeenWelcome: Whether the welcome already ran on this machine.
    ///   - authorization: What macOS currently says about the permission.
    ///   - islandIsAvailable: Whether a notched display is present.
    /// - Returns: The welcome to present, or nil.
    public static func welcome(
        hasSeenWelcome: Bool,
        authorization: NotificationAuthorizationState,
        islandIsAvailable: Bool
    ) -> FirstRunWelcome? {
        guard !hasSeenWelcome else { return nil }

        // `unknown` means the permission has not been read yet. Asking then
        // would race the read, and the welcome would offer a decision macOS
        // may already hold.
        let asks: Bool
        switch authorization {
        case .unknown, .authorized, .provisional:
            asks = false
        case .notDetermined, .denied, .unavailable:
            asks = true
        }

        guard asks || islandIsAvailable else { return nil }
        return FirstRunWelcome(
            asksForNotificationPermission: asks,
            offersIsland: islandIsAvailable
        )
    }
}
