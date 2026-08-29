import Testing
@testable import BlattaCore

struct HibernationResolverTests {
    @Test
    func thresholdFollowsEachPolicy() {
        #expect(HibernationResolver.idleThreshold(
            policy: .never,
            globalEnabled: true,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == nil)
        #expect(HibernationResolver.idleThreshold(
            policy: .never,
            globalEnabled: false,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == nil)

        #expect(HibernationResolver.idleThreshold(
            policy: .followGlobal,
            globalEnabled: true,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == 1_800)
        #expect(HibernationResolver.idleThreshold(
            policy: .followGlobal,
            globalEnabled: false,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == nil)

        #expect(HibernationResolver.idleThreshold(
            policy: .after,
            globalEnabled: false,
            globalIdleMinutes: 30,
            afterMinutes: 5
        ) == 300)
        #expect(HibernationResolver.idleThreshold(
            policy: .after,
            globalEnabled: true,
            globalIdleMinutes: 30,
            afterMinutes: 45
        ) == 2_700)

        #expect(HibernationResolver.idleThreshold(
            policy: .immediate,
            globalEnabled: false,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == HibernationResolver.immediateBackstopSeconds)
        #expect(HibernationResolver.idleThreshold(
            policy: .immediate,
            globalEnabled: true,
            globalIdleMinutes: 30,
            afterMinutes: 10
        ) == HibernationResolver.immediateBackstopSeconds)
    }
}
