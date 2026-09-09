import XCTest
@testable import PaguroCore

final class MicrophoneMutePresentationTests: XCTestCase {
    func testMenuTitleDescribesTheActiveCount() {
        XCTAssertEqual(
            MicrophoneMutePresentation.menuTitle(activeCount: 0),
            "Mute Active Microphones"
        )
        XCTAssertEqual(
            MicrophoneMutePresentation.menuTitle(activeCount: 1),
            "Mute Active Microphone"
        )
        XCTAssertEqual(
            MicrophoneMutePresentation.menuTitle(activeCount: 3),
            "Mute 3 Active Microphones"
        )
    }

    func testConfirmationExistsOnlyWhenSomethingWasMuted() {
        XCTAssertNil(MicrophoneMutePresentation.confirmation(mutedCount: 0))
        XCTAssertEqual(
            MicrophoneMutePresentation.confirmation(mutedCount: 1),
            "Muted 1 microphone."
        )
        XCTAssertEqual(
            MicrophoneMutePresentation.confirmation(mutedCount: 2),
            "Muted 2 microphones."
        )
    }

    func testNegativeCountsUseTheSafeEmptyState() {
        XCTAssertEqual(
            MicrophoneMutePresentation.menuTitle(activeCount: -1),
            "Mute Active Microphones"
        )
        XCTAssertNil(MicrophoneMutePresentation.confirmation(mutedCount: -1))
    }
}
