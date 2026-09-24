import Testing
@testable import PaguroCore

struct TransientBadgeFetchPolicyTests {
    @Test
    func nonCriticalServiceWithoutALiveViewIsFetched() {
        #expect(TransientBadgeFetchPolicy.shouldFetch(
            hasLiveWebView: false,
            isMuted: false,
            showsBadge: true,
            isNotificationCritical: false
        ))
    }

    @Test
    func notificationCriticalServiceIsNeverFetched() {
        #expect(TransientBadgeFetchPolicy.shouldFetch(
            hasLiveWebView: false,
            isMuted: false,
            showsBadge: true,
            isNotificationCritical: true
        ) == false)
    }

    @Test
    func liveMutedAndHiddenBadgeServicesAreNotFetched() {
        #expect(TransientBadgeFetchPolicy.shouldFetch(
            hasLiveWebView: true, isMuted: false, showsBadge: true, isNotificationCritical: false
        ) == false)
        #expect(TransientBadgeFetchPolicy.shouldFetch(
            hasLiveWebView: false, isMuted: true, showsBadge: true, isNotificationCritical: false
        ) == false)
        #expect(TransientBadgeFetchPolicy.shouldFetch(
            hasLiveWebView: false, isMuted: false, showsBadge: false, isNotificationCritical: false
        ) == false)
    }
}
