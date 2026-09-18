import XCTest
@testable import PaguroCore

final class FloatingNoticeLayoutTests: XCTestCase {
    func testAWideWindowKeepsThePreferredWidth() {
        XCTAssertEqual(
            FloatingNoticeLayout.width(availableWidth: 1200),
            FloatingNoticeLayout.preferredWidth
        )
    }

    func testANarrowWindowKeepsTheMarginOnBothSides() {
        let available = 300.0

        let width = FloatingNoticeLayout.width(availableWidth: available)

        XCTAssertEqual(width, available - (FloatingNoticeLayout.edgeInset * 2))
        XCTAssertLessThan(width, FloatingNoticeLayout.preferredWidth)
    }

    func testAVerySmallWindowKeepsThePositiveWidth() {
        XCTAssertGreaterThanOrEqual(FloatingNoticeLayout.width(availableWidth: 4), 0)
        XCTAssertGreaterThanOrEqual(FloatingNoticeLayout.width(availableWidth: 0), 0)
    }

    func testTheStackMovesBelowTheFindBar() {
        let withoutFindBar = FloatingNoticeLayout.topInset(findBarIsVisible: false)
        let withFindBar = FloatingNoticeLayout.topInset(findBarIsVisible: true)

        XCTAssertEqual(withoutFindBar, FloatingNoticeLayout.edgeInset)
        XCTAssertGreaterThan(withFindBar, withoutFindBar)
    }
}
