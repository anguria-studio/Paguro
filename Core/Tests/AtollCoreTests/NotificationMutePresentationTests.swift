import XCTest
@testable import AtollCore

final class NotificationMutePresentationTests: XCTestCase {
    func testScopeOrGlobalMuteShowsMutedState() {
        XCTAssertFalse(NotificationMutePresentation.showsMutedState(
            scopeMuted: false,
            manualGlobalMute: false
        ))
        XCTAssertTrue(NotificationMutePresentation.showsMutedState(
            scopeMuted: true,
            manualGlobalMute: false
        ))
        XCTAssertTrue(NotificationMutePresentation.showsMutedState(
            scopeMuted: false,
            manualGlobalMute: true
        ))
        XCTAssertTrue(NotificationMutePresentation.showsMutedState(
            scopeMuted: true,
            manualGlobalMute: true
        ))
    }
}
