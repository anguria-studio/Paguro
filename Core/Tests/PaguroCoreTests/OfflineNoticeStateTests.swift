import XCTest
@testable import PaguroCore

final class OfflineNoticeStateTests: XCTestCase {
    func testAnOnlineAppShowsNoNotice() {
        let state = OfflineNoticeState()

        XCTAssertFalse(state.showsNotice(isOnline: true))
    }

    func testALostConnectionShowsTheNotice() {
        var state = OfflineNoticeState()

        state.networkChanged(isOnline: false)

        XCTAssertTrue(state.showsNotice(isOnline: false))
    }

    func testDismissalRemovesTheNoticeWhileTheAppStaysOffline() {
        var state = OfflineNoticeState()
        state.networkChanged(isOnline: false)

        state.dismiss()

        XCTAssertFalse(state.showsNotice(isOnline: false))
    }

    /// A connection that drops again is a new event, so the notice returns.
    func testTheNextLossOfTheConnectionShowsTheNoticeAgain() {
        var state = OfflineNoticeState()
        state.networkChanged(isOnline: false)
        state.dismiss()

        state.networkChanged(isOnline: true)
        XCTAssertFalse(state.showsNotice(isOnline: true))

        state.networkChanged(isOnline: false)
        XCTAssertTrue(state.showsNotice(isOnline: false))
    }

    /// A returning connection alone does not put the notice back on screen.
    func testAReturningConnectionKeepsTheNoticeAway() {
        var state = OfflineNoticeState()
        state.networkChanged(isOnline: false)

        state.networkChanged(isOnline: true)

        XCTAssertFalse(state.showsNotice(isOnline: true))
    }
}
