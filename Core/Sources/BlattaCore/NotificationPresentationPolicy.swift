/// A visible destination for one normalized notification event.
public enum NotificationPresentationRoute: String, Equatable, Sendable {
    case systemNotification
    case island
}

/// Why a notification event has no visible presentation route.
public enum NotificationSuppressionReason: String, Equatable, Sendable {
    case locked
    case muted
    case doNotDisturb
    case noRouteEnabled
}

/// The current settings and policy state for one notification event.
public struct NotificationPresentationOptions: Equatable, Sendable {
    public let isLocked: Bool
    public let isMuted: Bool
    public let isDoNotDisturbActive: Bool
    public let isSystemNotificationEnabled: Bool
    public let isIslandEnabled: Bool
    public let isIslandAvailable: Bool

    public init(
        isLocked: Bool = false,
        isMuted: Bool = false,
        isDoNotDisturbActive: Bool = false,
        isSystemNotificationEnabled: Bool = true,
        isIslandEnabled: Bool = false,
        isIslandAvailable: Bool = true
    ) {
        self.isLocked = isLocked
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
        if options.isLocked {
            return NotificationPresentationPlan(routes: [], suppressionReason: .locked)
        }
        if options.isMuted {
            return NotificationPresentationPlan(routes: [], suppressionReason: .muted)
        }
        if options.isDoNotDisturbActive {
            return NotificationPresentationPlan(
                routes: [],
                suppressionReason: .doNotDisturb
            )
        }

        // One event is one notification. The island takes the event when it
        // can, and macOS is the fallback rather than a second copy: routing to
        // both put two banners on screen for the same message, one of which
        // outlives the island and has to be cleared by hand.
        var routes: [NotificationPresentationRoute] = []
        let islandHandlesEvent = options.isIslandEnabled
            && options.isIslandAvailable
        if islandHandlesEvent {
            routes.append(.island)
        } else if options.isSystemNotificationEnabled || options.isIslandEnabled {
            // The second case is the fallback: the island was asked for and
            // cannot run, so the event still has somewhere to go.
            routes.append(.systemNotification)
        }

        return NotificationPresentationPlan(
            routes: routes,
            suppressionReason: routes.isEmpty ? .noRouteEnabled : nil
        )
    }
}
