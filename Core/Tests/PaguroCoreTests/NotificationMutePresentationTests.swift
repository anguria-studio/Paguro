import XCTest
@testable import PaguroCore

final class NotificationMutePresentationTests: XCTestCase {
    func testAllServicesMuteIncludesGlobalAndRequiresNonemptyServices() {
        for (states, global, expected) in [
            ([], false, false), ([], true, true),
            ([true, true], false, true), ([true, false], false, false),
            ([false, false], true, true), ([false], false, false)
        ] {
            XCTAssertEqual(NotificationMutePresentation.allServicesMuted(
                serviceMuteStates: states, globalMute: global
            ), expected)
        }
    }

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
