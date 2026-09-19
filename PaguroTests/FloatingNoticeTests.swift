import PaguroCore
import XCTest
@testable import Paguro

/// The window side of the floating notice cards.
///
/// `PaguroCoreTests` hold the rules themselves: the inset above the first card,
/// the cap on the stack, and the offline dismissal. These tests cover the state
/// that the window keeps for them.
final class FloatingNoticeTests: XCTestCase {
    /// The offline card reports one state, so the user can put it away. A
    /// connection that drops again is a new event and brings the card back.
    @MainActor
    func testTheOfflineCardReturnsOnTheNextLossOfTheConnection() {
        // The monitor reads no real network path here, so the test owns every
        // transition.
        let monitor = NetworkMonitor(monitorsPath: false)
        XCTAssertTrue(monitor.isOnline)
        XCTAssertFalse(monitor.showsOfflineNotice)

        monitor.apply(isOnline: false)
        XCTAssertTrue(monitor.showsOfflineNotice)

        monitor.dismissOfflineNotice()
        XCTAssertFalse(monitor.showsOfflineNotice, "the user put the card away")

        monitor.apply(isOnline: true)
        XCTAssertFalse(monitor.showsOfflineNotice)

        monitor.apply(isOnline: false)
        XCTAssertTrue(monitor.showsOfflineNotice, "a new loss reports itself")
    }

    /// The same status twice is no change, so one loss of the connection raises
    /// one card and a dismissal holds.
    @MainActor
    func testARepeatedStatusDoesNotBringTheCardBack() {
        let monitor = NetworkMonitor(monitorsPath: false)
        monitor.apply(isOnline: false)
        monitor.dismissOfflineNotice()

        monitor.apply(isOnline: false)

        XCTAssertFalse(monitor.showsOfflineNotice)
    }

    /// The network change still reaches `NotificationRuntime`, which suspends
    /// polling while the network is unreachable.
    @MainActor
    func testANetworkChangeStillReportsToItsObserver() {
        let monitor = NetworkMonitor(monitorsPath: false)
        var reported: [Bool] = []
        monitor.onChange = { reported.append($0) }

        monitor.apply(isOnline: false)
        monitor.apply(isOnline: false)
        monitor.apply(isOnline: true)

        XCTAssertEqual(reported, [false, true])
    }

    @MainActor
    func testQueuedNetworkChangesAfterStopDoNothing() {
        let monitor = NetworkMonitor(monitorsPath: false)
        monitor.stop()
        monitor.apply(isOnline: false)
        XCTAssertTrue(monitor.isOnline)
        XCTAssertFalse(monitor.showsOfflineNotice)
    }

    func testEachServicesPasskeyNoticeHasItsOwnTimerIdentity() {
        let first = FloatingNotice.ID.passkeyUnavailable(UUID())
        let second = FloatingNotice.ID.passkeyUnavailable(UUID())
        XCTAssertNotEqual(first, second)
    }

    /// VoiceOver reads a card with no explanation as its title alone, so the
    /// microphone card does not speak an empty second line.
    func testACardWithoutAnExplanationSpeaksItsTitleAlone() {
        let withMessage = FloatingNotice(
            id: .offline,
            systemImage: "wifi.slash",
            title: "You're offline",
            message: "Services won't load new content until your connection returns.",
            dismiss: {}
        )
        let titleOnly = FloatingNotice(
            id: .microphoneFeedback,
            systemImage: "mic.slash.fill",
            title: "Muted 2 microphones.",
            dismiss: {}
        )

        XCTAssertEqual(
            withMessage.spokenText,
            "You're offline. Services won't load new content until your connection returns."
        )
        XCTAssertEqual(titleOnly.spokenText, "Muted 2 microphones.")
    }

    /// A notice leaves on its own unless it says that it waits for the user.
    func testANoticeLeavesOnItsOwnByDefault() {
        let notice = FloatingNotice(
            id: .capacityEviction,
            systemImage: "moon.zzz.fill",
            title: CapacityEvictionNotice.title,
            message: "A service was released.",
            dismiss: {}
        )

        XCTAssertEqual(notice.dismissal, .transient(seconds: nil))
        XCTAssertTrue(notice.actions.isEmpty)
        XCTAssertEqual(notice.severity, .info)
    }

    /// The buttons of one card keep separate identities in the row.
    func testTheButtonsOfACardAreDistinct() {
        let actions = [
            FloatingNoticeAction(title: "Not now") {},
            FloatingNoticeAction(title: "Review backups…") {}
        ]

        XCTAssertEqual(actions.map(\.id), ["Not now", "Review backups…"])
    }
}
