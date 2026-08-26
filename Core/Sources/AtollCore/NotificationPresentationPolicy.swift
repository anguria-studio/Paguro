/// A visible destination for one normalized notification event.
public enum NotificationPresentationRoute: String, Equatable, Sendable {
    case systemNotification
    case island
}

/// Why a notification event has no visible presentation route.
public enum NotificationSuppressionReason: String, Equatable, Sendable {
    case muted
    case doNotDisturb
    case noRouteEnabled
}

/// The current settings and policy state for one notification event.
public struct NotificationPresentationOptions: Equatable, Sendable {
    public let isMuted: Bool
    public let isDoNotDisturbActive: Bool
    public let isSystemNotificationEnabled: Bool
    public let isIslandEnabled: Bool
    public let isIslandAvailable: Bool

    public init(
        isMuted: Bool = false,
        isDoNotDisturbActive: Bool = false,
        isSystemNotificationEnabled: Bool = true,
        isIslandEnabled: Bool = false,
        isIslandAvailable: Bool = true
    ) {
        self.isMuted = isMuted
        self.isDoNotDisturbActive = isDoNotDisturbActive
        self.isSystemNotificationEnabled = isSystemNotificationEnabled
        self.isIslandEnabled = isIslandEnabled
        self.isIslandAvailable = isIslandAvailable
    }
}

/// The deterministic presentation result for one notification event.
public struct NotificationPresentationPlan: Equatable, Sendable {
    public let routes: [NotificationPresentationRoute]
    public let suppressionReason: NotificationSuppressionReason?

    init(
        routes: [NotificationPresentationRoute],
        suppressionReason: NotificationSuppressionReason?
    ) {
        self.routes = routes
        self.suppressionReason = suppressionReason
    }
}

/// Selects visible routes without using a platform presentation API.
public enum NotificationPresentationPolicy {
    public static func plan(
        for options: NotificationPresentationOptions
    ) -> NotificationPresentationPlan {
        if options.isMuted {
            return NotificationPresentationPlan(routes: [], suppressionReason: .muted)
        }
        if options.isDoNotDisturbActive {
            return NotificationPresentationPlan(
                routes: [],
                suppressionReason: .doNotDisturb
            )
        }

        var routes: [NotificationPresentationRoute] = []
        let needsSystemFallback = options.isIslandEnabled
            && !options.isIslandAvailable
        if options.isSystemNotificationEnabled || needsSystemFallback {
            routes.append(.systemNotification)
        }
        if options.isIslandEnabled && options.isIslandAvailable {
            routes.append(.island)
        }

        return NotificationPresentationPlan(
            routes: routes,
            suppressionReason: routes.isEmpty ? .noRouteEnabled : nil
        )
    }
}
