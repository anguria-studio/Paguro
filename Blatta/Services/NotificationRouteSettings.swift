import Foundation
import Observation

/// Stores the user-selected notification presentation routes.
@MainActor
@Observable
final class NotificationRouteSettings {
    private(set) var isSystemRouteEnabled: Bool
    private(set) var isIslandRouteEnabled: Bool

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        isSystemRouteEnabled = Self.bool(
            forKey: DefaultsKey.systemNotificationRouteEnabled,
            defaultValue: true,
            in: defaults
        )
        isIslandRouteEnabled = Self.bool(
            forKey: DefaultsKey.islandNotificationRouteEnabled,
            defaultValue: false,
            in: defaults
        )
    }

    func setSystemRouteEnabled(_ isEnabled: Bool) {
        isSystemRouteEnabled = isEnabled
        defaults.set(isEnabled, forKey: DefaultsKey.systemNotificationRouteEnabled)
    }

    func setIslandRouteEnabled(_ isEnabled: Bool) {
        isIslandRouteEnabled = isEnabled
        defaults.set(isEnabled, forKey: DefaultsKey.islandNotificationRouteEnabled)
    }

    private static func bool(
        forKey key: String,
        defaultValue: Bool,
        in defaults: UserDefaults
    ) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
