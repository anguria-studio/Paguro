import XCTest
@testable import BlattaCore

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

    private func sizes(pointerRows: Double) -> [Double] {
        (0...4).map { index in
            DockIconSizing.displayedSize(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: index,
                pointerRows: pointerRows
            )
        }
    }

    func testMagnificationFallsOffAcrossNeighboringIcons() {
        let sizes = sizes(pointerRows: 2)

        XCTAssertEqual(sizes[2], 64)
        XCTAssertEqual(sizes[1], sizes[3], accuracy: 0.000_001)
        XCTAssertEqual(sizes[0], sizes[4], accuracy: 0.000_001)
        // Each ring out takes less of the growth than the one inside it.
        XCTAssertGreaterThan(sizes[1], sizes[0])
        XCTAssertGreaterThan(sizes[0], 24)
    }

    /// The pointer is a position, not a choice of icon. Between two icons it
    /// grows both by the same amount, which is what a step from one icon to the
    /// next has to pass through to read as one movement.
    func testMagnificationFollowsThePointerBetweenIcons() {
        let between = sizes(pointerRows: 1.5)

        XCTAssertEqual(between[1], between[2], accuracy: 0.000_001)
        XCTAssertLessThan(between[1], 64)
        XCTAssertGreaterThan(between[1], sizes(pointerRows: 1)[2])

        // A small move of the pointer is a small move of every icon.
        let nudged = sizes(pointerRows: 1.55)
        for index in 0...4 {
            XCTAssertEqual(nudged[index], between[index], accuracy: 3)
        }
    }

    /// The curve is level where it meets the base size. A curve with slope left
    /// at that edge snaps the outermost icon in and out as the pointer passes.
    func testMagnificationCurveIsLevelAtBothEnds() {
        let influence = DockIconSizing.magnificationInfluence

        XCTAssertEqual(influence(0, DockIconSizing.magnificationInfluenceRows), 1)
        XCTAssertEqual(influence(2.5, DockIconSizing.magnificationInfluenceRows), 0)
        XCTAssertEqual(influence(4, DockIconSizing.magnificationInfluenceRows), 0)
        XCTAssertEqual(influence(-1, 2.5), influence(1, 2.5), accuracy: 0.000_001)
        // Near the edge the curve has all but stopped moving.
        XCTAssertLessThan(influence(2.4, 2.5), 0.005)
        // Near the peak too, so the icon under the pointer does not shimmer.
        XCTAssertGreaterThan(influence(0.1, 2.5), 0.995)
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

    func testTooltipClearsTheRailSurfaceAndTheMagnifiedIcon() {
        // A 24 point icon sits inside a 64 point rail that draws a 48 point
        // surface, so the surface edge places the label.
        XCTAssertEqual(
            DockIconSizing.tooltipLeadingOffset(
                baseSize: 24,
                displayedIconSize: 24,
                railInset: 8
            ),
            55
        )
        // A magnified icon reaches past that surface and takes the label with
        // it, one gap beyond its own edge.
        XCTAssertEqual(
            DockIconSizing.tooltipLeadingOffset(
                baseSize: 24,
                displayedIconSize: 64,
                railInset: 8
            ),
            83
        )
    }

    func testTooltipFollowsEveryStepOfMagnificationPastTheSurface() {
        let offsets = [40.0, 48.0, 56.0].map {
            DockIconSizing.tooltipLeadingOffset(
                baseSize: 24,
                displayedIconSize: $0,
                railInset: 8
            )
        }
        XCTAssertEqual(offsets, [59, 67, 75])
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
                pointerRows: 0,
                spaceAbove: .infinity
            ),
            -20
        )
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                pointerRows: 2,
                spaceAbove: .infinity
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
                pointerRows: 2,
                spaceAbove: .infinity
            ),
            0
        )
        XCTAssertEqual(
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                pointerRows: nil,
                spaceAbove: .infinity
            ),
            0
        )
    }

    /// The rail rises only as far as it has room to. Without room, the hovered
    /// icon keeps its top edge and grows downward, so the rail never hands the
    /// top icon to its own clip.
    func testStackRisesOnlyAsFarAsTheRailCanMove() {
        func offset(pointerRows: Double, spaceAbove: Double) -> Double {
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                pointerRows: pointerRows,
                spaceAbove: spaceAbove
            )
        }

        XCTAssertEqual(offset(pointerRows: 0, spaceAbove: 0), 0)
        XCTAssertEqual(offset(pointerRows: 2, spaceAbove: 0), 0)
        // Part of the rise fits, so the stack takes that part.
        XCTAssertEqual(offset(pointerRows: 0, spaceAbove: 8), -8)
        XCTAssertEqual(offset(pointerRows: 2, spaceAbove: 30), -30)
        // Room to spare leaves the rise as it was.
        XCTAssertEqual(offset(pointerRows: 0, spaceAbove: 200), -20)
        XCTAssertEqual(offset(pointerRows: 2, spaceAbove: 200), -50)
        // A negative measurement is no room, not a push downward.
        XCTAssertEqual(offset(pointerRows: 0, spaceAbove: -40), 0)
    }

    /// The progress carries the animation into and out of the effect, so the
    /// icon under an arriving pointer grows into its size instead of appearing
    /// at it.
    func testMagnificationProgressScalesTheWholeEffect() {
        func size(progress: Double) -> Double {
            DockIconSizing.displayedSize(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: 0,
                pointerRows: 0,
                magnificationProgress: progress
            )
        }

        XCTAssertEqual(size(progress: 0), 24)
        XCTAssertEqual(size(progress: 0.5), 44)
        XCTAssertEqual(size(progress: 1), 64)
        // A value outside the range is held at its end, not extrapolated.
        XCTAssertEqual(size(progress: -1), 24)
        XCTAssertEqual(size(progress: 2), 64)

        // The stack holds still until the effect starts, and moves with it.
        func offset(progress: Double) -> Double {
            DockIconSizing.stackVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 5,
                pointerRows: 0,
                magnificationProgress: progress,
                spaceAbove: .infinity
            )
        }

        XCTAssertEqual(offset(progress: 0), 0)
        XCTAssertEqual(offset(progress: 0.5), -10)
        XCTAssertEqual(offset(progress: 1), -20)
    }

    /// The rail draws the effect with transforms and lays out at the base size,
    /// so the scale is the size the icon would have had over the size it has.
    func testIconScaleMatchesTheSizeItReplaces() {
        for index in 0...4 {
            let scale = DockIconSizing.iconScale(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: index,
                pointerRows: 2
            )
            let size = DockIconSizing.displayedSize(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: index,
                pointerRows: 2
            )
            XCTAssertEqual(scale * 24, size, accuracy: 0.000_001)
        }

        XCTAssertEqual(
            DockIconSizing.iconScale(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: false,
                itemIndex: 0,
                pointerRows: 2
            ),
            1
        )
    }

    /// The frames stay at the base pitch, so each icon moves clear of the ones
    /// before it. The gaps that result are the ones the resting layout would
    /// have had if the icons had really grown.
    func testIconOffsetsOpenTheSameGapsThatGrowthWould() {
        func offset(_ index: Int) -> Double {
            DockIconSizing.iconVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: index,
                itemCount: 5,
                pointerRows: 2,
                spaceAbove: .infinity
            )
        }
        func height(_ index: Int) -> Double {
            DockIconSizing.rowHeight(
                displayedIconSize: DockIconSizing.displayedSize(
                    baseSize: 24,
                    magnifiedSize: 64,
                    magnificationEnabled: true,
                    itemIndex: index,
                    pointerRows: 2
                )
            )
        }

        let baseHeight = DockIconSizing.rowHeight(displayedIconSize: 24)
        for index in 0..<4 {
            let drawnGap = (offset(index + 1) + baseHeight) - offset(index)
            let grownGap = (height(index) + height(index + 1)) / 2
            XCTAssertEqual(drawnGap, grownGap, accuracy: 0.000_001)
        }

        // The icon under the pointer keeps its place, which is what the stack
        // moves for.
        XCTAssertEqual(offset(2), 0, accuracy: 0.000_001)
    }

    func testIconsRestWhereTheyLayOutWithoutAPointer() {
        XCTAssertEqual(
            DockIconSizing.iconVerticalOffset(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemIndex: 3,
                itemCount: 5,
                pointerRows: nil,
                spaceAbove: .infinity
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
                pointerRows: 0
            ),
            26
        )
    }
}
