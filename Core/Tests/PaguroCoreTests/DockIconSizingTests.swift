import XCTest
@testable import PaguroCore

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

    func testPointerPositionUsesContentRatherThanViewportCoordinates() {
        XCTAssertEqual(
            DockIconSizing.stackPointerPosition(
                viewportPosition: 40,
                scrollOffset: 30,
                topPadding: 10
            ),
            60
        )
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

    // MARK: - Pointer targets

    func testTargetResolverUsesRestingRowsWithoutMagnification() {
        let baseSize = 24.0
        let rowHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)

        for index in 0..<4 {
            XCTAssertEqual(
                DockIconSizing.targetIndex(
                    pointerPosition: (Double(index) + 0.5) * rowHeight,
                    baseSize: baseSize,
                    magnifiedSize: 64,
                    magnificationEnabled: false,
                    itemCount: 4,
                    pointerRows: nil,
                    spaceAbove: 0
                ),
                index
            )
        }

        XCTAssertNil(DockIconSizing.targetIndex(
            pointerPosition: -1,
            baseSize: baseSize,
            magnifiedSize: 64,
            magnificationEnabled: false,
            itemCount: 4,
            pointerRows: nil,
            spaceAbove: 0
        ))
        XCTAssertNil(DockIconSizing.targetIndex(
            pointerPosition: (4 * rowHeight) + 1,
            baseSize: baseSize,
            magnifiedSize: 64,
            magnificationEnabled: false,
            itemCount: 4,
            pointerRows: nil,
            spaceAbove: 0
        ))
    }

    /// The resolver uses the same extents that the drawing functions produce.
    /// This is the contract that a resting-row target alone could not keep.
    func testTargetResolverFindsEveryDrawnIcon() {
        let baseSize = 24.0
        let magnifiedSize = 64.0
        let itemCount = 6
        let baseHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)

        for spaceAbove in [0.0, 1_000.0] {
            for progress in [0.25, 0.5, 1.0] {
                var pointerRows = -0.5
                while pointerRows <= Double(itemCount) - 0.5 {
                    for index in 0..<itemCount {
                        let offset = DockIconSizing.iconVerticalOffset(
                            baseSize: baseSize,
                            magnifiedSize: magnifiedSize,
                            magnificationEnabled: true,
                            itemIndex: index,
                            itemCount: itemCount,
                            pointerRows: pointerRows,
                            magnificationProgress: progress,
                            spaceAbove: spaceAbove
                        )
                        let displayedHeight = DockIconSizing.rowHeight(
                            displayedIconSize: DockIconSizing.displayedSize(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: index,
                                pointerRows: pointerRows,
                                magnificationProgress: progress
                            )
                        )
                        let drawnCenter = (Double(index) + 0.5) * baseHeight + offset
                        let drawnTop = drawnCenter - (displayedHeight / 2)

                        for fraction in stride(from: 0.05, through: 0.95, by: 0.1) {
                            let position = drawnTop + (displayedHeight * fraction)
                            XCTAssertEqual(
                                DockIconSizing.targetIndex(
                                    pointerPosition: position,
                                    baseSize: baseSize,
                                    magnifiedSize: magnifiedSize,
                                    magnificationEnabled: true,
                                    itemCount: itemCount,
                                    pointerRows: pointerRows,
                                    magnificationProgress: progress,
                                    spaceAbove: spaceAbove
                                ),
                                index,
                                "pointer \(pointerRows), item \(index), position \(position), space \(spaceAbove), progress \(progress)"
                            )
                        }
                    }
                    pointerRows += 0.1
                }
            }
        }
    }

    /// A top-aligned stack grows below its resting end. Its final icon must
    /// still answer at the bottom of the icon that is visible there.
    func testTargetResolverIncludesThePushedDownTail() {
        let baseSize = 24.0
        let magnifiedSize = 64.0
        let itemCount = 5
        let lastIndex = itemCount - 1
        let baseHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)
        let pointerPosition = (Double(itemCount) * baseHeight) + 5
        let pointerRows = DockIconSizing.pointerRows(
            pointerPosition: pointerPosition,
            topPadding: 0,
            baseSize: baseSize
        )
        let displayed = DockIconSizing.displayedSize(
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemIndex: lastIndex,
            pointerRows: pointerRows
        )
        let offset = DockIconSizing.iconVerticalOffset(
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemIndex: lastIndex,
            itemCount: itemCount,
            pointerRows: pointerRows,
            spaceAbove: 0
        )
        let iconBottom = (Double(lastIndex) + 0.5) * baseHeight
            + offset
            + (displayed / 2)

        XCTAssertEqual(
            DockIconSizing.targetIndex(
                pointerPosition: pointerPosition,
                baseSize: baseSize,
                magnifiedSize: magnifiedSize,
                magnificationEnabled: true,
                itemCount: itemCount,
                pointerRows: pointerRows,
                spaceAbove: 0
            ),
            lastIndex
        )
        XCTAssertGreaterThan(iconBottom, Double(itemCount) * baseHeight)
        XCTAssertLessThan(pointerPosition, iconBottom)
    }

    func testTargetResolverLeavesABareWorkspaceDividerEmpty() {
        let baseSize = 24.0
        let rowHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)
        let dividerHeight = 13.0

        XCTAssertNil(DockIconSizing.targetIndex(
            pointerPosition: rowHeight + (dividerHeight / 2),
            baseSize: baseSize,
            magnifiedSize: 64,
            magnificationEnabled: false,
            itemCount: 3,
            pointerRows: nil,
            spaceAbove: 0,
            separatorAfterIndices: [0],
            separatorHeight: dividerHeight
        ))
        XCTAssertEqual(
            DockIconSizing.targetIndex(
                pointerPosition: rowHeight + dividerHeight + (rowHeight / 2),
                baseSize: baseSize,
                magnifiedSize: 64,
                magnificationEnabled: false,
                itemCount: 3,
                pointerRows: nil,
                spaceAbove: 0,
                separatorAfterIndices: [0],
                separatorHeight: dividerHeight
            ),
            1
        )
    }

    func testTargetResolverGivesAVisibleIconPriorityOverADivider() {
        let baseSize = 24.0
        let rowHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)

        XCTAssertEqual(
            DockIconSizing.targetIndex(
                pointerPosition: rowHeight + 2,
                baseSize: baseSize,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 3,
                pointerRows: 0,
                spaceAbove: 0,
                separatorAfterIndices: [0],
                separatorHeight: 13
            ),
            0
        )
    }

    func testMaximumTargetSpillIsFixedByTheSizeSettings() {
        XCTAssertEqual(
            DockIconSizing.maximumTargetSpill(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true
            ),
            100
        )
        XCTAssertEqual(
            DockIconSizing.maximumTargetSpill(
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: false
            ),
            0
        )
    }

    func testMaximumTargetSpillContainsBothEndsOfEveryDrawnStack() {
        let itemCount = 7

        for baseSize in [14.0, 24.0, 44.0] {
            for magnifiedSize in [32.0, 52.0, 72.0] {
                let baseHeight = DockIconSizing.rowHeight(
                    displayedIconSize: baseSize
                )
                let restingBottom = Double(itemCount) * baseHeight
                let spill = DockIconSizing.maximumTargetSpill(
                    baseSize: baseSize,
                    magnifiedSize: magnifiedSize,
                    magnificationEnabled: true
                )

                for spaceAbove in [0.0, 1_000.0] {
                    for pointerRows in stride(
                        from: -0.5,
                        through: Double(itemCount) - 0.5,
                        by: 0.1
                    ) {
                        let firstHeight = DockIconSizing.rowHeight(
                            displayedIconSize: DockIconSizing.displayedSize(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: 0,
                                pointerRows: pointerRows
                            )
                        )
                        let firstCenter = (baseHeight / 2)
                            + DockIconSizing.iconVerticalOffset(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: 0,
                                itemCount: itemCount,
                                pointerRows: pointerRows,
                                spaceAbove: spaceAbove
                            )
                        let lastIndex = itemCount - 1
                        let lastHeight = DockIconSizing.rowHeight(
                            displayedIconSize: DockIconSizing.displayedSize(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: lastIndex,
                                pointerRows: pointerRows
                            )
                        )
                        let lastCenter = (Double(lastIndex) + 0.5) * baseHeight
                            + DockIconSizing.iconVerticalOffset(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: lastIndex,
                                itemCount: itemCount,
                                pointerRows: pointerRows,
                                spaceAbove: spaceAbove
                            )

                        XCTAssertGreaterThanOrEqual(
                            spill + 0.000_001,
                            -(firstCenter - (firstHeight / 2))
                        )
                        XCTAssertGreaterThanOrEqual(
                            spill + 0.000_001,
                            (lastCenter + (lastHeight / 2)) - restingBottom
                        )
                    }
                }
            }
        }
    }

    // MARK: - Workspace divider

    /// The divider must stay in the middle of the gap that its two neighbors
    /// leave, at every step of the animation and at every pointer position.
    func testWorkspaceDividerStaysCenteredBetweenItsDrawnNeighbors() {
        let baseSize = 24.0
        let magnifiedSize = 64.0
        let itemCount = 6
        let separatorAfterIndex = 2
        let dividerHeight = 13.0
        let baseHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)

        func restingTop(_ index: Int) -> Double {
            (Double(index) * baseHeight)
                + (index > separatorAfterIndex ? dividerHeight : 0)
        }

        for spaceAbove in [0.0, 1_000.0] {
            for progress in [0.0, 0.25, 0.5, 0.75, 1.0] {
                for pointerRows in stride(
                    from: -0.5,
                    through: Double(itemCount) - 0.5,
                    by: 0.1
                ) {
                    func drawnCenter(_ index: Int) -> Double {
                        restingTop(index)
                            + (baseHeight / 2)
                            + DockIconSizing.iconVerticalOffset(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: index,
                                itemCount: itemCount,
                                pointerRows: pointerRows,
                                magnificationProgress: progress,
                                spaceAbove: spaceAbove
                            )
                    }
                    func drawnHeight(_ index: Int) -> Double {
                        DockIconSizing.rowHeight(
                            displayedIconSize: DockIconSizing.displayedSize(
                                baseSize: baseSize,
                                magnifiedSize: magnifiedSize,
                                magnificationEnabled: true,
                                itemIndex: index,
                                pointerRows: pointerRows,
                                magnificationProgress: progress
                            )
                        )
                    }

                    let above = drawnCenter(separatorAfterIndex)
                        + (drawnHeight(separatorAfterIndex) / 2)
                    let below = drawnCenter(separatorAfterIndex + 1)
                        - (drawnHeight(separatorAfterIndex + 1) / 2)
                    let restingCenter = restingTop(separatorAfterIndex)
                        + baseHeight
                        + (dividerHeight / 2)
                    let drawnDividerCenter = restingCenter
                        + DockIconSizing.separatorVerticalOffset(
                            afterIndex: separatorAfterIndex,
                            baseSize: baseSize,
                            magnifiedSize: magnifiedSize,
                            magnificationEnabled: true,
                            itemCount: itemCount,
                            pointerRows: pointerRows,
                            magnificationProgress: progress,
                            spaceAbove: spaceAbove
                        )

                    XCTAssertEqual(
                        drawnDividerCenter,
                        (above + below) / 2,
                        accuracy: 0.000_000_001,
                        "pointer \(pointerRows), progress \(progress), space \(spaceAbove)"
                    )
                }
            }
        }
    }

    func testWorkspaceDividerHoldsStillWhileTheRailRests() {
        XCTAssertEqual(
            DockIconSizing.separatorVerticalOffset(
                afterIndex: 1,
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: true,
                itemCount: 4,
                pointerRows: nil,
                spaceAbove: 0
            ),
            0
        )
        XCTAssertEqual(
            DockIconSizing.separatorVerticalOffset(
                afterIndex: 1,
                baseSize: 24,
                magnifiedSize: 64,
                magnificationEnabled: false,
                itemCount: 4,
                pointerRows: 1,
                spaceAbove: 0
            ),
            0
        )
    }

    /// The empty band belongs to the drawn divider. A point that the drawn
    /// stack has moved into must answer with the icon that a person sees
    /// there, not with the divider that has left.
    func testTargetResolverMovesTheEmptyBandWithTheDivider() {
        let baseSize = 24.0
        let magnifiedSize = 64.0
        let itemCount = 4
        let separatorAfterIndex = 1
        let dividerHeight = 13.0
        let baseHeight = DockIconSizing.rowHeight(displayedIconSize: baseSize)
        // The pointer sits on the first icon, which pushes the divider down.
        let pointerRows = 0.0
        let restingBandCenter = (Double(separatorAfterIndex + 1) * baseHeight)
            + (dividerHeight / 2)
        let separatorOffset = DockIconSizing.separatorVerticalOffset(
            afterIndex: separatorAfterIndex,
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemCount: itemCount,
            pointerRows: pointerRows,
            spaceAbove: 0
        )

        XCTAssertGreaterThan(separatorOffset, dividerHeight)
        XCTAssertNotNil(DockIconSizing.targetIndex(
            pointerPosition: restingBandCenter,
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemCount: itemCount,
            pointerRows: pointerRows,
            spaceAbove: 0,
            separatorAfterIndices: [separatorAfterIndex],
            separatorHeight: dividerHeight
        ))
        XCTAssertNil(DockIconSizing.targetIndex(
            pointerPosition: restingBandCenter + separatorOffset,
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemCount: itemCount,
            pointerRows: pointerRows,
            spaceAbove: 0,
            separatorAfterIndices: [separatorAfterIndex],
            separatorHeight: dividerHeight
        ))
    }
}
