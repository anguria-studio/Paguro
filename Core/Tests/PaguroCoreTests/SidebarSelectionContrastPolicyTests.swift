import XCTest
@testable import PaguroCore

final class SidebarSelectionContrastPolicyTests: XCTestCase {
    func testStandardTextRemainsBelowTheAdaptiveHighlight() {
        XCTAssertFalse(
            SidebarSelectionContrastPolicy.usesHighContrastText(
                shellTransparency: 0.59
            )
        )
    }

    func testHighContrastTextStartsWithTheAdaptiveHighlight() {
        XCTAssertTrue(
            SidebarSelectionContrastPolicy.usesHighContrastText(
                shellTransparency: 0.6
            )
        )
        XCTAssertTrue(
            SidebarSelectionContrastPolicy.usesHighContrastText(
                shellTransparency: 1
            )
        )
    }

    func testOutOfRangeValuesAreClamped() {
        XCTAssertFalse(
            SidebarSelectionContrastPolicy.usesHighContrastText(
                shellTransparency: -1
            )
        )
        XCTAssertTrue(
            SidebarSelectionContrastPolicy.usesHighContrastText(
                shellTransparency: 2
            )
        )
    }
}
