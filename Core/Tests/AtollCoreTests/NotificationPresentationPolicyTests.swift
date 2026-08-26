import Testing
@testable import AtollCore

struct NotificationPresentationPolicyTests {
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

    @Test
    func explicitRouteSettingsCanEnableBothDestinations() {
        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isSystemNotificationEnabled: true,
                isIslandEnabled: true
            )
        )

        #expect(plan.routes == [.systemNotification, .island])
        #expect(plan.suppressionReason == nil)
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
