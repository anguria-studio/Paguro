import XCTest
@testable import BlattaCore

final class DockBadgePolicyTests: XCTestCase {
    func testVisibleTotalMakesTheLabel() {
        XCTAssertEqual(
            DockBadgePolicy.badgeLabel(unreadTotal: 7, showsBadgeCount: true),
            "7"
        )
        XCTAssertEqual(
            DockBadgePolicy.badgeLabel(unreadTotal: 999, showsBadgeCount: true),
            "999"
        )
    }

    func testPreferenceOffRemovesTheLabel() {
        XCTAssertNil(DockBadgePolicy.badgeLabel(unreadTotal: 7, showsBadgeCount: false))
    }

    func testZeroAndNegativeTotalsRemoveTheLabel() {
        XCTAssertNil(DockBadgePolicy.badgeLabel(unreadTotal: 0, showsBadgeCount: true))
        XCTAssertNil(DockBadgePolicy.badgeLabel(unreadTotal: -3, showsBadgeCount: true))
    }
}
