import Foundation

/// Whether the offline notice belongs on screen.
///
/// The notice reports one state and carries no action, so the user can put it
/// away and keep working in the services that are already loaded. A connection
/// that drops again is a new event, so the notice returns for it. Without that
/// reset one dismissal would silence every later loss of the connection for the
/// rest of the app run.
public struct OfflineNoticeState: Equatable, Sendable {
    private var isDismissed = false

    public init() {}

    /// True while the notice belongs on screen.
    public func showsNotice(isOnline: Bool) -> Bool {
        !isOnline && !isDismissed
    }

    /// Takes the notice off the screen until the connection drops again.
    public mutating func dismiss() {
        isDismissed = true
    }

    /// Reports a change of the network status.
    ///
    /// A change to offline clears the dismissal, so the next loss of the
    /// connection reports itself. Call this for a change only.
    public mutating func networkChanged(isOnline: Bool) {
        guard !isOnline else { return }
        isDismissed = false
    }
}
