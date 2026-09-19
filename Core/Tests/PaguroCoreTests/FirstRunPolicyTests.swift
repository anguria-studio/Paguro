import Testing
@testable import PaguroCore

struct FirstRunPolicyTests {
    private func presentation(
        serviceCount: Int,
        isLocked: Bool = false,
        authorization: NotificationAuthorizationState = .authorized,
        islandIsAvailable: Bool = false,
        forcesPreview: Bool = false
    ) -> FirstRunPresentation {
        FirstRunPolicy.presentation(
            serviceCount: serviceCount,
            isLocked: isLocked,
            authorization: authorization,
            islandIsAvailable: islandIsAvailable,
            forcesPreview: forcesPreview
        )
    }

    /// A workspace with nothing in it is still an empty window, so the
    /// workspaces say nothing here. The service count is the whole rule.
    @Test
    func workspacesWithoutServicesStillShowTheHomeScreen() {
        #expect(presentation(serviceCount: 0).showsHome)
    }

    @Test
    func oneServiceShowsTheShell() {
        #expect(presentation(serviceCount: 1).showsHome == false)
        #expect(presentation(serviceCount: 12).showsHome == false)
    }

    /// The shell needs no setup rows, because it has no screen to carry them.
    @Test
    func theShellCarriesNoSetupRows() {
        #expect(
            presentation(serviceCount: 1, authorization: .notDetermined).setup == nil
        )
    }

    /// Intended: an empty window is what the screen describes, so a user who
    /// removed every service reaches it again.
    @Test
    func deletingEveryServiceShowsTheHomeScreenAgain() {
        #expect(presentation(serviceCount: 0).showsHome)
    }

    /// The lock screen draws over the home screen. The screen waits under it,
    /// and none of its actions can run, so the import line stays refused.
    @Test
    func aLockedWindowKeepsTheHomeScreenUnderneathWithoutItsActions() {
        let locked = presentation(serviceCount: 0, isLocked: true)

        #expect(locked.showsHome)
        #expect(locked.allowsActions == false)
    }

    @Test
    func anUnlockedWindowAllowsTheActions() {
        #expect(presentation(serviceCount: 0).allowsActions)
    }

    /// The permission has not been read yet, and no notch: no row applies, so
    /// the screen leaves its card out.
    @Test
    func anUnreadPermissionWithoutANotchNeedsNoCard() {
        let home = presentation(serviceCount: 0, authorization: .unknown)

        #expect(home.showsHome)
        #expect(home.setup == nil)
    }

    /// The row reports a permission macOS already holds. It is the one place a
    /// new user sees that state before they open Settings.
    @Test
    func aGrantedPermissionStillShowsTheNotificationRow() {
        #expect(
            presentation(serviceCount: 0, authorization: .authorized)
                .setup?.showsNotificationRow == true
        )
    }

    @Test
    func aStoredRefusalStillShowsTheNotificationRow() {
        #expect(
            presentation(serviceCount: 0, authorization: .denied)
                .setup?.showsNotificationRow == true
        )
    }

    /// An unread permission on a notched Mac keeps the island row and drops the
    /// notification row alone.
    @Test
    func anUnreadPermissionKeepsTheIslandRow() {
        let setup = presentation(
            serviceCount: 0,
            authorization: .unknown,
            islandIsAvailable: true
        ).setup

        #expect(setup?.showsNotificationRow == false)
        #expect(setup?.showsIslandRow == true)
    }

    @Test
    func theIslandRowNeedsANotchedDisplay() {
        #expect(
            presentation(serviceCount: 0, islandIsAvailable: false)
                .setup?.showsIslandRow == false
        )
        #expect(
            presentation(serviceCount: 0, islandIsAvailable: true)
                .setup?.showsIslandRow == true
        )
    }

    /// The preview argument shows the screen over a full workspace.
    @Test
    func thePreviewArgumentShowsTheScreenOverExistingServices() {
        let preview = presentation(
            serviceCount: 7,
            authorization: .notDetermined,
            forcesPreview: true
        )

        #expect(preview.showsHome)
        #expect(preview.setup?.showsNotificationRow == true)
    }

    @Test
    func everyStateIsDecided() {
        for state in NotificationAuthorizationState.allCases {
            for count in [0, 1] {
                _ = presentation(serviceCount: count, authorization: state)
            }
        }
    }
}
