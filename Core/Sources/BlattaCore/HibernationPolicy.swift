import Foundation

/// Controls when an inactive service can release its web process.
public enum HibernationPolicy: String, CaseIterable, Sendable {
    case followGlobal, never, immediate, after
}

/// Pure rules for converting a hibernation policy into an idle threshold.
public enum HibernationResolver {
    /// The grace period and idle-sweep backstop for `.immediate` services.
    public static let immediateBackstopSeconds: TimeInterval = 5

    /// Returns the idle seconds before hibernation, or nil when disabled.
    public static func idleThreshold(
        policy: HibernationPolicy,
        globalEnabled: Bool,
        globalIdleMinutes: Int,
        afterMinutes: Int
    ) -> TimeInterval? {
        switch policy {
        case .never:
            return nil
        case .followGlobal:
            return globalEnabled ? TimeInterval(globalIdleMinutes * 60) : nil
        case .after:
            return TimeInterval(afterMinutes * 60)
        case .immediate:
            return immediateBackstopSeconds
        }
    }
}
