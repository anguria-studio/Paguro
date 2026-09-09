import Testing
@testable import PaguroCore

struct FirstRunPolicyTests {
    @Test
    func aSecondRunShowsNothing() {
        #expect(
            FirstRunPolicy.welcome(
                hasSeenWelcome: true,
                authorization: .notDetermined,
                islandIsAvailable: true
            ) == nil
        )
    }

    /// Nothing to ask means no welcome, rather than an empty one.
    @Test
    func aGrantedPermissionOnAScreenWithoutANotchShowsNothing() {
        #expect(
            FirstRunPolicy.welcome(
                hasSeenWelcome: false,
                authorization: .authorized,
                islandIsAvailable: false
            ) == nil
        )
    }

    /// The permission has not been read yet, so asking would race the read.
    @Test
    func anUnreadPermissionIsNotAskedFor() {
        let welcome = FirstRunPolicy.welcome(
            hasSeenWelcome: false,
            authorization: .unknown,
            islandIsAvailable: true
        )

        #expect(welcome?.asksForNotificationPermission == false)
        #expect(welcome?.offersIsland == true)
    }

    @Test
    func aNotchedMacWithoutPermissionIsOfferedBoth() {
        let welcome = FirstRunPolicy.welcome(
            hasSeenWelcome: false,
            authorization: .notDetermined,
            islandIsAvailable: true
        )

        #expect(welcome?.asksForNotificationPermission == true)
        #expect(welcome?.offersIsland == true)
    }

    /// A refusal still gets the offer: it routes to System Settings, which is
    /// the only way back once macOS has stored a no.
    @Test
    func aStoredRefusalStillOffersTheWayBack() {
        let welcome = FirstRunPolicy.welcome(
            hasSeenWelcome: false,
            authorization: .denied,
            islandIsAvailable: false
        )

        #expect(welcome?.asksForNotificationPermission == true)
        #expect(welcome?.offersIsland == false)
    }

    @Test
    func everyStateIsDecided() {
        for state in NotificationAuthorizationState.allCases {
            _ = FirstRunPolicy.welcome(
                hasSeenWelcome: false,
                authorization: state,
                islandIsAvailable: false
            )
        }
    }
}
