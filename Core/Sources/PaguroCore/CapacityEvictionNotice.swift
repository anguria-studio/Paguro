import Foundation

/// Builds the notice that explains one capacity-triggered hibernation.
///
/// The pool can release a background service because of `WebViewPoolCapacity`,
/// not because the service was idle. That reason is invisible in the interface,
/// so the user can read it as a fault. The notice states the reason one time in
/// each app run and names the control that prevents it.
public enum CapacityEvictionNotice {
    /// The longest service name that the notice shows in full.
    ///
    /// A longer name is cut, so one service cannot push the explanation out of
    /// the notice strip.
    public static let maximumServiceNameLength = 40

    /// The name that the notice uses when the service has no usable label.
    public static let fallbackServiceName = "a background service"

    /// True while the app run has not shown the notice yet.
    ///
    /// The notice explains a fixed rule, so it is useful one time. Later
    /// evictions repeat the same fact and become noise.
    public static func shouldAnnounce(hasAnnouncedThisRun: Bool) -> Bool {
        !hasAnnouncedThisRun
    }

    /// The notice text for the service that the pool released.
    public static func message(serviceName: String) -> String {
        """
        Paguro released \(displayName(for: serviceName)) to control memory. \
        It keeps a limited number of services loaded at the same time. \
        Mark a service "Keep Loaded" to always keep it live.
        """
    }

    /// Trims the stored label and keeps the notice to one readable line.
    private static func displayName(for serviceName: String) -> String {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return fallbackServiceName }
        guard trimmed.count > maximumServiceNameLength else { return trimmed }
        return trimmed.prefix(maximumServiceNameLength) + "…"
    }
}
