import XCTest
@testable import PaguroCore

final class PasskeyNoticeStateTests: XCTestCase {
    func testOpeningMoreServicesKeepsTheSameNoticeUntilDismissed() {
        var state = PasskeyNoticeState(hasBeenSeen: false)
        state.present(isLocked: false, passkeysSupported: false)
        XCTAssertTrue(state.isVisible)
        let visible = state
        state.present(isLocked: false, passkeysSupported: false)
        XCTAssertEqual(state, visible)
        state.dismiss()
        state.present(isLocked: false, passkeysSupported: false)
        XCTAssertFalse(state.isVisible)
        XCTAssertTrue(state.hasBeenSeen)
    }

    func testLockedWindowDoesNotConsumeTheNotice() {
        var state = PasskeyNoticeState(hasBeenSeen: false)
        state.present(isLocked: true, passkeysSupported: false)
        XCTAssertFalse(state.hasBeenSeen)
        XCTAssertFalse(state.isVisible)
        state.present(isLocked: false, passkeysSupported: false)
        XCTAssertTrue(state.isVisible)
    }

    func testSupportedPasskeysNeedNoWarning() {
        var state = PasskeyNoticeState(hasBeenSeen: false)
        state.present(isLocked: false, passkeysSupported: true)
        XCTAssertFalse(state.hasBeenSeen)
        XCTAssertFalse(state.isVisible)
    }

    func testSeenNoticeDoesNotReturnOnRelaunch() {
        var state = PasskeyNoticeState(hasBeenSeen: true)
        state.present(isLocked: false, passkeysSupported: false)
        XCTAssertFalse(state.isVisible)
    }
}
