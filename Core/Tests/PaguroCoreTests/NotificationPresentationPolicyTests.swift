import Testing
@testable import PaguroCore

struct NotificationPresentationPolicyTests {
    @Test
    func lockSuppressesAllRoutesIncludingFallback() {
        for system in [false, true] {
            for island in [false, true] {
                for available in [false, true] {
                    let plan = NotificationPresentationPolicy.plan(for: .init(
                        isLocked: true,
                        isSystemNotificationEnabled: system,
                        isIslandEnabled: island,
                        isIslandAvailable: available
                    ))
                    #expect(plan.routes.isEmpty)
                    #expect(plan.suppressionReason == .locked)
                }
            }
        }
    }

    @Test
    func defaultsToOneSystemNotificationRoute() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions()
        )

        #expect(plan.routes == [.systemNotification])
        #expect(plan.suppressionReason == nil)
    }

    @Test
    func supportsAnIslandOnlyRoute() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: false,
                isIslandEnabled: true
            )
        )

        #expect(plan.routes == [.island])
        #expect(plan.suppressionReason == nil)
    }

    /// The island wins when both routes are on, rather than both firing.
    ///
    /// Routing to both put two banners on screen for one message: the island,
    /// and a macOS notification that outlived it and had to be cleared by hand.
    @Test
    func theIslandTakesTheEventWhenBothRoutesAreEnabled() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: true,
                isIslandEnabled: true
            )
        )

        #expect(plan.routes == [.island])
        #expect(plan.suppressionReason == nil)
    }

    @Test
    func unavailableIslandFallsBackToOneSystemNotification() {
        let islandOnlyPlan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: false,
                isIslandEnabled: true,
                isIslandAvailable: false
            )
        )
        let bothRoutesPlan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: true,
                isIslandEnabled: true,
                isIslandAvailable: false
            )
        )

        #expect(islandOnlyPlan.routes == [.systemNotification])
        #expect(bothRoutesPlan.routes == [.systemNotification])
    }

    @Test
    func muteTakesPriorityOverAllRoutes() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isMuted: true,
                isDoNotDisturbActive: true,
                isSystemNotificationEnabled: true,
                isIslandEnabled: true
            )
        )

        #expect(plan.routes.isEmpty)
        #expect(plan.suppressionReason == .muted)
    }

    @Test
    func doNotDisturbSuppressesAllRoutes() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isDoNotDisturbActive: true,
                isSystemNotificationEnabled: true,
                isIslandEnabled: true
            )
        )

        #expect(plan.routes.isEmpty)
        #expect(plan.suppressionReason == .doNotDisturb)
    }

    @Test
    func reportsWhenNoRouteIsEnabled() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: false,
                isIslandEnabled: false
            )
        )

        #expect(plan.routes.isEmpty)
        #expect(plan.suppressionReason == .noRouteEnabled)
    }
}
