import XCTest
@testable import PaguroCore

final class SpaceSwitcherVisibilityTests: XCTestCase {
    func testOneSpaceHidesTheSwitcher() {
        XCTAssertFalse(SpaceSwitcherVisibility.showsSwitcher(spaceCount: 1))
    }

    func testZeroOrMultipleSpacesKeepTheSwitcher() {
        XCTAssertTrue(SpaceSwitcherVisibility.showsSwitcher(spaceCount: 0))
        XCTAssertTrue(SpaceSwitcherVisibility.showsSwitcher(spaceCount: 2))
    }
}
