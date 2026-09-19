import XCTest
@testable import PaguroCore

final class FloatingNoticeLayoutTests: XCTestCase {
    /// The content header and every top bar are 52 points high in the app.
    private let chromeHeight = 52.0

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

    /// The sidebar layout draws the content header above the web content, so the
    /// stack starts one margin below that header.
    func testTheStackStartsBelowTheContentHeader() {
        XCTAssertEqual(
            FloatingNoticeLayout.topInset(
                chromeHeight: chromeHeight,
                findBarIsVisible: false
            ),
            chromeHeight + FloatingNoticeLayout.edgeInset
        )
    }

    /// The number that the four shell layouts produce. A bar along the top is as
    /// tall as the content header, so one number covers all of them.
    func testTheShellInsetIsSixtySixPoints() {
        XCTAssertEqual(
            FloatingNoticeLayout.topInset(chromeHeight: chromeHeight, findBarIsVisible: false),
            66
        )
    }

    func testTheStackMovesBelowTheFindBar() {
        let withoutFindBar = FloatingNoticeLayout.topInset(
            chromeHeight: chromeHeight,
            findBarIsVisible: false
        )
        let withFindBar = FloatingNoticeLayout.topInset(
            chromeHeight: chromeHeight,
            findBarIsVisible: true
        )

        XCTAssertEqual(withFindBar, chromeHeight + FloatingNoticeLayout.findBarClearance)
        XCTAssertGreaterThan(withFindBar, withoutFindBar)
    }

    /// The first-run screen draws no header and no bar, so its cards clear the
    /// title-bar band alone.
    func testAScreenWithoutChromeClearsTheTitleBarBand() {
        let inset = FloatingNoticeLayout.topInset(
            chromeHeight: FloatingNoticeLayout.titleBarBand,
            findBarIsVisible: false
        )

        XCTAssertEqual(inset, FloatingNoticeLayout.titleBarBand + FloatingNoticeLayout.edgeInset)
        XCTAssertEqual(inset, 42)
        XCTAssertLessThan(
            inset,
            FloatingNoticeLayout.topInset(chromeHeight: chromeHeight, findBarIsVisible: false)
        )
    }

    /// A negative height cannot pull the first card into the title bar.
    func testTheInsetNeverFallsBelowTheMargin() {
        XCTAssertEqual(
            FloatingNoticeLayout.topInset(chromeHeight: -40, findBarIsVisible: false),
            FloatingNoticeLayout.edgeInset
        )
    }
}
