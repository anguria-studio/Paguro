import XCTest
@testable import AtollCore

final class DockIconSizingTests: XCTestCase {
    func testDefaultMagnificationMatchesDefaultPeakSize() {
        XCTAssertEqual(
            DockIconSizing.peakSize(
                baseSize: DockIconSizing.defaultBaseSize,
                magnification: DockIconSizing.defaultMagnification
            ),
            DockIconSizing.defaultMagnifiedSize,
            accuracy: 0.000_001
        )
    }

    func testBaseSizeClampsToTheRailRange() {
        XCTAssertEqual(DockIconSizing.baseSize(10), 14)
        XCTAssertEqual(DockIconSizing.baseSize(25), 25)
        XCTAssertEqual(DockIconSizing.baseSize(60), 44)
    }

    func testMagnifiedSizeNeverFallsBelowTheBaseSize() {
        XCTAssertEqual(DockIconSizing.magnifiedSize(10, baseSize: 24), 32)
        XCTAssertEqual(DockIconSizing.magnifiedSize(32, baseSize: 44), 44)
        XCTAssertEqual(DockIconSizing.magnifiedSize(80, baseSize: 24), 72)
    }

    func testZeroBasedMagnificationMapsToThePeakSize() {
        XCTAssertEqual(DockIconSizing.peakSize(baseSize: 24, magnification: 0), 24)
        XCTAssertEqual(DockIconSizing.peakSize(baseSize: 24, magnification: 0.5), 48)
        XCTAssertEqual(DockIconSizing.peakSize(baseSize: 24, magnification: 1), 72)
        XCTAssertEqual(DockIconSizing.magnification(baseSize: 24, peakSize: 48), 0.5)
    }

    func testBaseSizeChangesTheCompleteRailGeometry() {
        XCTAssertEqual(DockIconSizing.railWidth(baseSize: 14), 54)
        XCTAssertEqual(DockIconSizing.railWidth(baseSize: 24), 64)
        XCTAssertEqual(DockIconSizing.railWidth(baseSize: 44), 84)
        XCTAssertEqual(DockIconSizing.selectionSize(baseSize: 24), 38)
        XCTAssertEqual(DockIconSizing.selectionSize(displayedIconSize: 64), 78)
        XCTAssertEqual(DockIconSizing.rowHeight(displayedIconSize: 24), 46)
    }

    func testMagnificationFallsOffAcrossNeighboringIcons() {
        let sizes = (0...4).map { index in
            DockIconSizing.displayedSize(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: index,
                hoveredIndex: 2
            )
        }

        XCTAssertEqual(sizes[2], 64)
        XCTAssertEqual(sizes[1], 46, accuracy: 0.000_001)
        XCTAssertEqual(sizes[3], 46, accuracy: 0.000_001)
        XCTAssertEqual(sizes[0], 32, accuracy: 0.000_001)
        XCTAssertEqual(sizes[4], 32, accuracy: 0.000_001)
    }

    func testMagnifiedIconKeepsItsLeftEdgeAndMovesRight() {
        XCTAssertEqual(
            DockIconSizing.horizontalOffset(baseSize: 24, displayedIconSize: 64),
            20
        )
        XCTAssertEqual(
            DockIconSizing.horizontalOffset(baseSize: 24, displayedIconSize: 24),
            0
        )
    }

    func testTooltipClearsTheRailAndTheMagnifiedIcon() {
        XCTAssertEqual(
            DockIconSizing.tooltipLeadingOffset(baseSize: 24, displayedIconSize: 24),
            63
        )
        XCTAssertEqual(
            DockIconSizing.tooltipLeadingOffset(baseSize: 24, displayedIconSize: 64),
            83
        )
    }

    func testCenteredRailUsesTheBaseStackHeight() {
        XCTAssertEqual(
            DockIconSizing.centeredTopPadding(
                containerHeight: 600,
                itemCount: 5,
                baseSize: 24,
                bottomInset: 8
            ),
            181
        )
        XCTAssertEqual(
            DockIconSizing.centeredTopPadding(
                containerHeight: 200,
                itemCount: 5,
                baseSize: 44,
                bottomInset: 8
            ),
            0
        )
        XCTAssertEqual(
            DockIconSizing.centeredTopPadding(
                containerHeight: 600,
                itemCount: 5,
                baseSize: 24,
                bottomInset: 8,
                additionalContentHeight: 20
            ),
            171
        )
    }

    func testCenteredRailCanUseTheCompleteWindowCenterline() {
        let topInset = 60.0
        let padding = DockIconSizing.centeredTopPadding(
            containerHeight: 600,
            itemCount: 5,
            baseSize: 24,
            topInset: topInset,
            bottomInset: 0
        )
        let stackHeight = 5 * DockIconSizing.rowHeight(displayedIconSize: 24)

        XCTAssertEqual(topInset + padding + (stackHeight / 2), 300)
    }

    func testStackMovesUpToKeepTheHoveredIconCentered() {
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                hoveredIndex: 0
            ),
            -20
        )
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                hoveredIndex: 2
            ),
            -50
        )
    }

    func testStackDoesNotMoveWithoutMagnificationOrAValidHover() {
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: false,
                itemCount: 5,
                hoveredIndex: 2
            ),
            0
        )
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                hoveredIndex: nil
            ),
            0
        )
    }

    func testDisabledMagnificationKeepsEveryIconAtTheBaseSize() {
        XCTAssertEqual(
            DockIconSizing.displayedSize(
                baseSize: 26,
                magnifiedSize: 42,
                magnificationEnabled: false,
                itemIndex: 0,
                hoveredIndex: 0
            ),
            26
        )
    }
}
