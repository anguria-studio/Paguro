import AtollCore
import Testing

@Suite("Notification island layout")
struct NotificationIslandLayoutTests {
    private let housingHeight = 38.0

    @Test("The panel width adds one notch ear on each side")
    func panelWidthAddsOneNotchEarOnEachSide() {
        let layout = NotificationIslandLayout.self

        #expect(layout.notchEarWidth == 6)
        #expect(layout.panelWidth(bodyWidth: layout.expandedWidth) == 432)
        #expect(layout.panelWidth(bodyWidth: 360) == 372)
        #expect(layout.panelWidth(bodyWidth: 164 + 76) == 252)
        #expect(layout.panelWidth(bodyWidth: 0) == 12)
    }

    @Test("The height table matches the stack rule")
    func heightTableMatchesTheStackRule() {
        let layout = NotificationIslandLayout.self
        let base = housingHeight + layout.topInset + layout.bottomInset
        let oneRow = base + layout.rowHeight
        let visibleRows = Double(layout.visibleRowLimit)
        let completeRows = base
            + (visibleRows * layout.rowHeight)
            + ((visibleRows - 1) * layout.rowSpacing)

        #expect(height(for: 0) == oneRow)
        #expect(height(for: 1) == oneRow)
        #expect(height(for: 3) == completeRows)
        #expect(height(for: 4) == completeRows + layout.stackPeekHeight)
        #expect(height(for: 50) == completeRows + layout.stackPeekHeight)
    }

    @Test("The height table keeps the values of the panel")
    func heightTableKeepsTheValuesOfThePanel() {
        #expect(height(for: 1) == 118)
        #expect(height(for: 2) == 194)
        #expect(height(for: 3) == 270)
        #expect(height(for: 4) == 308)
        #expect(containerHeight(eventCount: 4) == 300)
        #expect(stopLine(eventCount: 4) == 290)
    }

    @Test("The height never decreases when the list grows")
    func heightNeverDecreasesWhenTheListGrows() {
        var previous = height(for: 0)

        for eventCount in 1...12 {
            let current = height(for: eventCount)
            #expect(current >= previous)
            previous = current
        }
    }

    @Test("The height stays the same after the visible row limit")
    func heightStaysTheSameAfterTheVisibleRowLimit() {
        let limit = NotificationIslandLayout.visibleRowLimit
        let limitHeight = height(for: limit + 1)

        #expect(height(for: limit + 2) == limitHeight)
        #expect(height(for: 99) == limitHeight)
    }

    @Test("A negative housing height cannot shrink the panel")
    func negativeHousingHeightCannotShrinkThePanel() {
        let layout = NotificationIslandLayout.self
        let expected = layout.topInset + layout.rowHeight + layout.bottomInset

        #expect(
            layout.expandedHeight(eventCount: 1, cameraHousingHeight: -20)
                == expected
        )
    }

    @Test("The scroll container height matches the panel height")
    func scrollContainerHeightMatchesThePanelHeight() {
        for eventCount in [1, 3, 4, 10] {
            #expect(
                NotificationIslandLayout.scrollContainerHeight(
                    eventCount: eventCount,
                    cameraHousingHeight: housingHeight
                ) == containerHeight(eventCount: eventCount)
            )
        }
    }

    @Test("The card positions follow the row pitch")
    func cardPositionsFollowTheRowPitch() {
        let layout = NotificationIslandLayout.self

        #expect(
            layout.rowMaxY(index: 0, cameraHousingHeight: housingHeight)
                == housingHeight + layout.topInset + layout.rowHeight
        )
        #expect(
            layout.topSpacerHeight(cameraHousingHeight: housingHeight)
                == housingHeight + layout.topInset
        )
        #expect(rowMaxY(rowIndex: -3) == rowMaxY(rowIndex: 0))

        for index in 1...6 {
            #expect(
                abs(
                    rowMaxY(rowIndex: index)
                        - rowMaxY(rowIndex: index - 1)
                        - layout.rowPitch
                ) < 0.0001
            )
        }
    }

    @Test("A card is wider than the toolbar controls")
    func cardIsWiderThanTheToolbarControls() {
        let layout = NotificationIslandLayout.self

        #expect(layout.cardHorizontalInset < layout.horizontalInset)
        #expect(layout.horizontalInset - layout.cardHorizontalInset == 4)
    }

    @Test("The complete pile stays above the island bottom edge")
    func completePileStaysAboveTheIslandBottomEdge() {
        let layout = NotificationIslandLayout.self
        let eventCount = 13
        let deepestBottom = layout.pileCardBottom(
            containerHeight: containerHeight(eventCount: eventCount),
            depth: layout.maximumFoldDepth
        )

        #expect(deepestBottom == stopLine(eventCount: eventCount) + 8)
        #expect(height(for: eventCount) - deepestBottom >= 8)
        #expect(deepestBottom < containerHeight(eventCount: eventCount))
    }

    @Test("A short list collects no card on the pile")
    func shortListCollectsNoCardOnThePile() {
        #expect(!NotificationIslandLayout.foldsRows(eventCount: 0))
        #expect(!NotificationIslandLayout.foldsRows(eventCount: 3))
        #expect(NotificationIslandLayout.foldsRows(eventCount: 4))
    }

    @Test("One event keeps its complete card")
    func oneEventKeepsItsCompleteCard() {
        #expect(depth(rowIndex: 0, eventCount: 1) == 0)
        #expect(offset(rowIndex: 0, eventCount: 1) == 0)
    }

    @Test("Each card of a complete list keeps its complete form")
    func eachCardOfACompleteListKeepsItsCompleteForm() {
        let limit = NotificationIslandLayout.visibleRowLimit

        for rowIndex in 0..<limit {
            let level = depth(rowIndex: rowIndex, eventCount: limit)
            #expect(level == 0)
            #expect(offset(rowIndex: rowIndex, eventCount: limit) == 0)
            #expect(NotificationIslandLayout.foldScale(depth: level) == 1)
            #expect(NotificationIslandLayout.foldOpacity(depth: level) == 1)
        }
    }

    @Test("The rest state of a long list follows the pile table")
    func restStateOfALongListFollowsThePileTable() {
        let layout = NotificationIslandLayout.self
        let eventCount = 13
        let line = stopLine(eventCount: eventCount)

        // The third card is the last complete card above the stop line.
        #expect(rowMaxY(rowIndex: 2) == 262)
        #expect(placement(rowIndex: 2, eventCount: eventCount) == .flat)

        // The fourth card waits at the stop line and shows its peek.
        let held = placement(rowIndex: 3, eventCount: eventCount)
        #expect(abs(held.depth - 0.63) < 0.005)
        #expect(abs(drawnBottom(rowIndex: 3, eventCount: eventCount) - line)
            <= 0.25)
        #expect(
            abs(
                drawnBottom(rowIndex: 3, eventCount: eventCount)
                    - rowMaxY(rowIndex: 2)
                    - 28
            ) <= 0.25
        )
        #expect(held.opacity == 1)

        // The fifth card is the second card of the pile.
        let second = placement(rowIndex: 4, eventCount: eventCount)
        #expect(abs(second.depth - 1.63) < 0.005)
        #expect(
            abs(drawnBottom(rowIndex: 4, eventCount: eventCount) - 295) <= 0.3
        )
        #expect(abs(second.scale - 0.902) < 0.002)
        #expect(second.opacity == 1)

        // The sixth card fades out and the seventh card is invisible.
        let sixth = placement(rowIndex: 5, eventCount: eventCount)
        #expect(abs(sixth.depth - 2.63) < 0.005)
        #expect(sixth.opacity > 0)
        #expect(sixth.opacity < 1)
        #expect(
            abs(drawnBottom(rowIndex: 5, eventCount: eventCount) - (line + 8))
                <= 0.25
        )
        #expect(placement(rowIndex: 6, eventCount: eventCount) == .hidden)
        #expect(layout.maximumFoldDepth == 3)
    }

    @Test("The visible cards of a longer list stay above the stop line")
    func visibleCardsOfALongerListStayAboveTheStopLine() {
        for rowIndex in 0..<NotificationIslandLayout.visibleRowLimit {
            #expect(depth(rowIndex: rowIndex, eventCount: 8) == 0)
            #expect(offset(rowIndex: rowIndex, eventCount: 8) == 0)
        }
    }

    @Test("A card holds the stop line until the pile takes it")
    func cardHoldsTheStopLineUntilThePileTakesIt() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let line = stopLine(eventCount: 13)

        for step in [0.05, 0.25, 0.5, 0.75, 1.0] {
            let placement = layout.pilePlacement(
                rowMaxY: line + (layout.rowPitch * step),
                containerHeight: container,
                eventCount: 13
            )
            let bottom = line + (layout.rowPitch * step) + placement.offset
            #expect(abs(bottom - line) <= 0.25)
            #expect(placement.opacity == 1)
        }
    }

    @Test("A card moves one stagger down for the second pile level")
    func cardMovesOneStaggerDownForTheSecondPileLevel() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let line = stopLine(eventCount: 13)
        var previous = line

        for step in [1.0, 1.25, 1.5, 1.75, 2.0, 2.5, 3.0] {
            let bottom = layout.pileCardBottom(
                containerHeight: container,
                depth: step
            )
            #expect(bottom >= previous)
            previous = bottom
        }

        #expect(previous == line + layout.pileStagger)
    }

    @Test("A card keeps a continuous form at the stop line")
    func cardKeepsAContinuousFormAtTheStopLine() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let line = stopLine(eventCount: 13)

        #expect(
            layout.pilePlacement(
                rowMaxY: line,
                containerHeight: container,
                eventCount: 13
            ) == .flat
        )

        for step in 1...4 {
            let distance = Double(step) * 0.25
            let placement = layout.pilePlacement(
                rowMaxY: line + distance,
                containerHeight: container,
                eventCount: 13
            )
            #expect(abs(placement.offset) <= distance + 0.25)
            #expect(placement.scale > 0.998)
            #expect(placement.opacity == 1)
        }
    }

    @Test("The pile level grows with the card position")
    func pileLevelGrowsWithTheCardPosition() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let line = stopLine(eventCount: 13)
        var previous = 0.0

        for step in -4...20 {
            let rowMaxY = line + (layout.rowPitch * Double(step) / 5)
            let level = layout.foldDepth(
                rowMaxY: rowMaxY,
                containerHeight: container,
                eventCount: 13
            )
            #expect(level >= previous)
            #expect(level >= 0)
            #expect(level <= layout.maximumFoldDepth)
            #expect(layout.foldScale(depth: level) <= 1)
            previous = level
        }

        #expect(previous == layout.maximumFoldDepth)
    }

    @Test("The last card reaches the stop line at the end of the scroll")
    func lastCardReachesTheStopLineAtTheEndOfTheScroll() {
        let layout = NotificationIslandLayout.self
        let eventCount = 8
        let container = containerHeight(eventCount: eventCount)
        // The clearance follows the last card with no space between them.
        let contentHeight = rowMaxY(rowIndex: eventCount - 1)
            + layout.bottomScrollClearance
        let maximumScroll = contentHeight - container
        let lastCardMaxY = rowMaxY(rowIndex: eventCount - 1) - maximumScroll

        #expect(maximumScroll > 0)
        #expect(abs(lastCardMaxY - stopLine(eventCount: eventCount)) < 0.0001)
        #expect(
            layout.pilePlacement(
                rowMaxY: lastCardMaxY,
                containerHeight: container,
                eventCount: eventCount
            ) == .flat
        )
    }

    @Test("A card outside the pile keeps its complete height")
    func cardOutsideThePileKeepsItsCompleteHeight() {
        let limit = NotificationIslandLayout.visibleRowLimit

        for rowIndex in 0..<limit {
            #expect(placement(rowIndex: rowIndex, eventCount: 6) == .flat)
        }
        #expect(placement(rowIndex: 0, eventCount: 1) == .flat)
    }

    @Test("A movement inside one drawing step gives the same result")
    func movementInsideOneDrawingStepGivesTheSameResult() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let position = rowMaxY(rowIndex: 4)
        let placement = layout.pilePlacement(
            rowMaxY: position,
            containerHeight: container,
            eventCount: 13
        )

        for delta in [-0.05, -0.01, 0.01, 0.05] {
            #expect(
                layout.pilePlacement(
                    rowMaxY: position + delta,
                    containerHeight: container,
                    eventCount: 13
                ) == placement
            )
        }
    }

    @Test("The placement keeps each card rule of the pile")
    func placementKeepsEachCardRuleOfThePile() {
        let layout = NotificationIslandLayout.self
        let placement = self.placement(rowIndex: 4, eventCount: 13)

        #expect(placement.scale == layout.foldScale(depth: placement.depth))
        #expect(placement.opacity == layout.foldOpacity(depth: placement.depth))
        #expect(
            abs(placement.offset - offset(rowIndex: 4, eventCount: 13)) <= 0.25
        )
    }

    @Test("A card above the stop line writes the same result each time")
    func cardAboveTheStopLineWritesTheSameResultEachTime() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 13)
        let line = stopLine(eventCount: 13)

        for step in 0...20 {
            let rowMaxY = line - (layout.rowPitch * Double(step) / 4)
            #expect(
                layout.pilePlacement(
                    rowMaxY: rowMaxY,
                    containerHeight: container,
                    eventCount: 13
                ) == .flat
            )
        }
    }

    @Test("Each card behind the pile gives the same result")
    func eachCardBehindThePileGivesTheSameResult() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 40)
        let line = stopLine(eventCount: 40)

        for step in 0...20 {
            let rowMaxY = line
                + (layout.rowPitch * layout.maximumFoldDepth)
                + (layout.rowPitch * Double(step))
            #expect(
                layout.pilePlacement(
                    rowMaxY: rowMaxY,
                    containerHeight: container,
                    eventCount: 40
                ) == .hidden
            )
        }
        #expect(NotificationIslandLayout.PilePlacement.hidden.opacity == 0)
        #expect(NotificationIslandLayout.PilePlacement.hidden.offset == 0)
    }

    @Test("A card is invisible on each side of the deepest level")
    func cardIsInvisibleOnEachSideOfTheDeepestLevel() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 40)
        let line = stopLine(eventCount: 40)
        let beforeHidden = layout.pilePlacement(
            rowMaxY: line + (layout.rowPitch * 2.99),
            containerHeight: container,
            eventCount: 40
        )

        #expect(beforeHidden != .hidden)
        #expect(beforeHidden.opacity < 0.02)
    }

    @Test("A card that returns from the pile becomes visible again")
    func cardThatReturnsFromThePileBecomesVisibleAgain() {
        let layout = NotificationIslandLayout.self
        let container = containerHeight(eventCount: 40)
        let line = stopLine(eventCount: 40)
        var previousOpacity = 0.0

        for step in stride(from: 30, through: 0, by: -1) {
            let placement = layout.pilePlacement(
                rowMaxY: line + (layout.rowPitch * Double(step) / 10),
                containerHeight: container,
                eventCount: 40
            )
            #expect(placement.opacity >= previousOpacity)
            previousOpacity = placement.opacity
        }

        #expect(previousOpacity == 1)
    }

    @Test("An empty container gives no pile")
    func emptyContainerGivesNoPile() {
        #expect(
            NotificationIslandLayout.foldDepth(
                rowMaxY: 40,
                containerHeight: 0,
                eventCount: 8
            ) == 0
        )
    }

    private func height(for eventCount: Int) -> Double {
        NotificationIslandLayout.expandedHeight(
            eventCount: eventCount,
            cameraHousingHeight: housingHeight
        )
    }

    /// Gives the visible scroll view height inside the panel.
    private func containerHeight(eventCount: Int) -> Double {
        height(for: eventCount) - NotificationIslandLayout.bottomInset
    }

    /// Gives the position where a card stops and waits for the pile.
    private func stopLine(eventCount: Int) -> Double {
        containerHeight(eventCount: eventCount)
            - NotificationIslandLayout.stopLineInset
    }

    /// Gives the bottom edge of one card in an unscrolled list.
    private func rowMaxY(rowIndex: Int) -> Double {
        NotificationIslandLayout.rowMaxY(
            index: rowIndex,
            cameraHousingHeight: housingHeight
        )
    }

    /// Gives the drawn bottom edge of one card in an unscrolled list.
    private func drawnBottom(rowIndex: Int, eventCount: Int) -> Double {
        rowMaxY(rowIndex: rowIndex)
            + placement(rowIndex: rowIndex, eventCount: eventCount).offset
    }

    private func placement(
        rowIndex: Int,
        eventCount: Int
    ) -> NotificationIslandLayout.PilePlacement {
        NotificationIslandLayout.pilePlacement(
            rowMaxY: rowMaxY(rowIndex: rowIndex),
            containerHeight: containerHeight(eventCount: eventCount),
            eventCount: eventCount
        )
    }

    private func depth(rowIndex: Int, eventCount: Int) -> Double {
        NotificationIslandLayout.foldDepth(
            rowMaxY: rowMaxY(rowIndex: rowIndex),
            containerHeight: containerHeight(eventCount: eventCount),
            eventCount: eventCount
        )
    }

    private func offset(rowIndex: Int, eventCount: Int) -> Double {
        NotificationIslandLayout.foldOffset(
            rowMaxY: rowMaxY(rowIndex: rowIndex),
            containerHeight: containerHeight(eventCount: eventCount),
            depth: depth(rowIndex: rowIndex, eventCount: eventCount)
        )
    }
}
