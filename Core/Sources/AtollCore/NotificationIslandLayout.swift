/// Size rules for the expanded notification island.
///
/// The expanded island shows the session events as a vertical stack of cards.
/// AppKit owns the panel frame, so the panel height must come from a pure
/// rule and not from a SwiftUI measurement. This type supplies that rule.
///
/// A list longer than the visible row limit keeps the same panel height. The
/// cards after the visible rows collect on one pile at the bottom edge. The
/// card nearest the fold line is in front. Each deeper card is a little lower,
/// a little smaller, and fades out after two levels.
///
/// The values use `Double` so this rule stays independent of SwiftUI and
/// AppKit. The app target converts the result to `CGFloat` at the view edge.
public enum NotificationIslandLayout: Sendable {
    /// Height of one recent event card.
    public static let rowHeight = 68.0

    /// Vertical space between two cards.
    public static let rowSpacing = 8.0

    /// Distance from one card top edge to the next card top edge.
    public static let rowPitch = rowHeight + rowSpacing

    /// Space between the toolbar and the first card.
    public static let topInset = 4.0

    /// Space below the last visible card.
    ///
    /// The value keeps the complete pile inside the rounded island bottom.
    public static let bottomInset = 8.0

    /// Space between the island edge and each toolbar control.
    public static let horizontalInset = 14.0

    /// Space between the island edge and each card.
    ///
    /// A card is a little wider than the toolbar controls, so the pile stays
    /// visible below them.
    public static let cardHorizontalInset = 10.0

    /// Largest number of cards that the panel shows at full height.
    public static let visibleRowLimit = 3

    /// Extra panel height that shows the held card and the pile behind it.
    ///
    /// The value keeps the peek of the held card, the second card strip, and
    /// one margin.
    public static let stackPeekHeight = 38.0

    /// Space between the stop line and the scroll view bottom edge.
    public static let stopLineInset = 10.0

    /// Vertical distance between two cards of the pile.
    public static let pileStagger = 8.0

    /// Space between the card edge and the card content.
    public static let cardVerticalPadding = 7.0

    /// Corner radius of one card.
    public static let cardCornerRadius = 12.0

    /// Extra content height that lets the last card reach the stop line.
    ///
    /// The scroll view must not stop before that point and must not scroll
    /// past it. The clearance follows the last card with no space between
    /// them, so it is the stop line inset.
    public static let bottomScrollClearance = stopLineInset

    /// Width of the peek and expanded panel.
    public static let expandedWidth = 420.0

    /// Width of one concave ear of the notch silhouette.
    ///
    /// The island shape starts at the top screen edge and curves inward, so
    /// the visible island body starts one ear width inside each panel edge.
    public static let notchEarWidth = 6.0

    /// Gives the panel width that shows a body of this width.
    ///
    /// The two ears merge into the top screen edge and show no island
    /// surface. The panel therefore carries one ear width on each side.
    ///
    /// - Parameter bodyWidth: Width of the visible island body.
    /// - Returns: The complete panel width in points.
    public static func panelWidth(bodyWidth: Double) -> Double {
        max(0, bodyWidth) + (notchEarWidth * 2)
    }

    /// Deepest pile level. A card at this level is invisible.
    public static let maximumFoldDepth = 3.0

    /// Deepest pile level that keeps the complete card opacity.
    private static let opaqueFoldDepth = 2.0

    private static let foldScalePerLevel = 0.06

    /// Smallest pile level change that the view must draw.
    private static let depthStep = 0.01

    /// Smallest position change that the view must draw.
    private static let pointStep = 0.5

    /// Gives the panel height for a number of session events.
    ///
    /// The height grows with each new event until the visible row limit.
    /// A longer list keeps the same height and adds one small stack peek.
    ///
    /// - Parameters:
    ///   - eventCount: Number of events in the recent list.
    ///   - cameraHousingHeight: Height of the camera housing toolbar.
    /// - Returns: The complete panel height in points.
    public static func expandedHeight(
        eventCount: Int,
        cameraHousingHeight: Double
    ) -> Double {
        let visibleRows = min(max(eventCount, 1), visibleRowLimit)
        let rowsHeight = Double(visibleRows) * rowHeight
        let spacingHeight = Double(max(0, visibleRows - 1)) * rowSpacing
        let peekHeight = foldsRows(eventCount: eventCount) ? stackPeekHeight : 0
        return max(0, cameraHousingHeight)
            + topInset
            + rowsHeight
            + spacingHeight
            + bottomInset
            + peekHeight
    }

    /// Gives the visible height of the scroll view inside the panel.
    ///
    /// The list starts at the island top edge and goes below the toolbar, so
    /// the scroll view keeps the toolbar height. The panel keeps one inset
    /// below the list. The view uses this value until the first geometry
    /// measurement of the scroll view arrives.
    ///
    /// - Parameters:
    ///   - eventCount: Number of events in the recent list.
    ///   - cameraHousingHeight: Height of the camera housing toolbar.
    /// - Returns: The scroll view height in points.
    public static func scrollContainerHeight(
        eventCount: Int,
        cameraHousingHeight: Double
    ) -> Double {
        expandedHeight(
            eventCount: eventCount,
            cameraHousingHeight: cameraHousingHeight
        ) - bottomInset
    }

    /// Gives the empty height above the first card.
    ///
    /// The list scrolls below the toolbar, so the first card starts one top
    /// inset under the toolbar bottom edge.
    ///
    /// - Parameter cameraHousingHeight: Height of the camera housing toolbar.
    /// - Returns: The height of the space above the first card.
    public static func topSpacerHeight(cameraHousingHeight: Double) -> Double {
        max(0, cameraHousingHeight) + topInset
    }

    /// Gives the bottom edge of one card in an unscrolled list.
    ///
    /// The view uses this position until the first geometry report of that
    /// card arrives.
    ///
    /// - Parameters:
    ///   - index: Position of the card, where 0 is the newest card.
    ///   - cameraHousingHeight: Height of the camera housing toolbar.
    /// - Returns: The card bottom edge in scroll view coordinates.
    public static func rowMaxY(
        index: Int,
        cameraHousingHeight: Double
    ) -> Double {
        let row = max(0, index)
        return topSpacerHeight(cameraHousingHeight: cameraHousingHeight)
            + (Double(row + 1) * rowHeight)
            + (Double(row) * rowSpacing)
    }

    /// Tells if a list of this length collects cards on a pile.
    ///
    /// A list inside the visible row limit shows each card complete.
    public static func foldsRows(eventCount: Int) -> Bool {
        eventCount > visibleRowLimit
    }

    /// Gives the pile level of one card.
    ///
    /// The result is 0 for each card above the stop line. It grows by one
    /// level for each card pitch below that line and stops at the deepest
    /// level.
    ///
    /// - Parameters:
    ///   - rowMaxY: Bottom edge of the card in scroll view coordinates.
    ///   - containerHeight: Visible height of the scroll view.
    ///   - eventCount: Number of events in the recent list.
    /// - Returns: A value from 0 through `maximumFoldDepth`.
    public static func foldDepth(
        rowMaxY: Double,
        containerHeight: Double,
        eventCount: Int
    ) -> Double {
        guard foldsRows(eventCount: eventCount),
              rowPitch > 0,
              containerHeight > 0 else { return 0 }
        let distance = rowMaxY - stopLine(containerHeight: containerHeight)
        guard distance > 0 else { return 0 }
        return min(maximumFoldDepth, distance / rowPitch)
    }

    /// Gives the vertical offset that puts one card on the pile.
    ///
    /// The card stops at the stop line and stays there while the card above
    /// it comes down over it. The card then moves down by one pile stagger
    /// and becomes the second card of the pile.
    ///
    /// A card above the stop line and each card of a short list get the
    /// offset 0, so the movement stays continuous at that line.
    ///
    /// - Parameters:
    ///   - rowMaxY: Bottom edge of the card in scroll view coordinates.
    ///   - containerHeight: Visible height of the scroll view.
    ///   - depth: Pile level from the fold depth rule.
    /// - Returns: A vertical offset in points.
    public static func foldOffset(
        rowMaxY: Double,
        containerHeight: Double,
        depth: Double
    ) -> Double {
        guard depth > 0 else { return 0 }
        return pileCardBottom(containerHeight: containerHeight, depth: depth)
            - rowMaxY
    }

    /// Gives the drawn bottom edge of one card of the pile.
    ///
    /// The first level keeps the stop line. The second level adds one pile
    /// stagger, so the card behind stays visible below the card in front.
    ///
    /// - Parameters:
    ///   - containerHeight: Visible height of the scroll view.
    ///   - depth: Pile level from the fold depth rule.
    /// - Returns: The bottom edge in scroll view coordinates.
    public static func pileCardBottom(
        containerHeight: Double,
        depth: Double
    ) -> Double {
        stopLine(containerHeight: containerHeight)
            + (pileStagger * clamped(depth - 1))
    }

    /// Gives the card scale for one pile level.
    ///
    /// The view uses the bottom anchor, so the card bottom edges stay in line.
    public static func foldScale(depth: Double) -> Double {
        1 - (foldScalePerLevel * min(max(0, depth), opaqueFoldDepth))
    }

    /// Gives the card opacity for one pile level.
    ///
    /// The card and the first card of the pile stay opaque. A deeper card
    /// fades out.
    public static func foldOpacity(depth: Double) -> Double {
        let level = min(max(0, depth), maximumFoldDepth)
        guard level > opaqueFoldDepth else { return 1 }
        let fadeRange = maximumFoldDepth - opaqueFoldDepth
        guard fadeRange > 0 else { return 0 }
        return max(0, 1 - ((level - opaqueFoldDepth) / fadeRange))
    }

    /// Gives each drawing value of one card in one result.
    ///
    /// The view keeps this value in its own state. Two positions inside one
    /// step give the same result, so a small scroll movement writes no state.
    ///
    /// - Parameters:
    ///   - rowMaxY: Bottom edge of the card in scroll view coordinates.
    ///   - containerHeight: Visible height of the scroll view.
    ///   - eventCount: Number of events in the recent list.
    /// - Returns: The complete drawing rule for that card.
    public static func pilePlacement(
        rowMaxY: Double,
        containerHeight: Double,
        eventCount: Int
    ) -> PilePlacement {
        let depth = quantized(
            foldDepth(
                rowMaxY: rowMaxY,
                containerHeight: containerHeight,
                eventCount: eventCount
            ),
            step: depthStep
        )
        guard depth > 0 else { return .flat }
        // A card at the deepest level is invisible. One constant result keeps
        // each card behind the pile out of the drawing work.
        guard depth < maximumFoldDepth else { return .hidden }
        let offset = foldOffset(
            rowMaxY: rowMaxY,
            containerHeight: containerHeight,
            depth: depth
        )
        return PilePlacement(
            depth: depth,
            offset: quantized(offset, step: pointStep),
            scale: foldScale(depth: depth),
            opacity: foldOpacity(depth: depth)
        )
    }

    /// Keeps one value inside 0 through 1.
    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    /// Removes a change that is smaller than one drawing step.
    private static func quantized(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }

    /// Gives the position where a card stops and waits for the pile.
    private static func stopLine(containerHeight: Double) -> Double {
        containerHeight - stopLineInset
    }
}

/// Each drawing value of one card of the notification stack.
public extension NotificationIslandLayout {
    struct PilePlacement: Equatable, Sendable {
        /// The rule for a card behind the complete pile.
        ///
        /// The card is invisible, so the rule holds no position. Each card at
        /// this level gives the same result, and a scroll movement therefore
        /// draws none of these cards again.
        public static let hidden = PilePlacement(
            depth: NotificationIslandLayout.maximumFoldDepth,
            offset: 0,
            scale: NotificationIslandLayout.foldScale(
                depth: NotificationIslandLayout.maximumFoldDepth - 1
            ),
            opacity: 0
        )

        /// The rule for a card that is not part of the pile.
        public static let flat = PilePlacement(
            depth: 0,
            offset: 0,
            scale: 1,
            opacity: 1
        )

        /// Pile level of the card.
        public let depth: Double

        /// Vertical movement that puts the card on the pile.
        public let offset: Double

        /// Size of the card, from its bottom edge.
        public let scale: Double

        /// Opacity of the complete card.
        ///
        /// The card in front covers this card, so the card keeps its
        /// complete content until the deepest level takes it away.
        public let opacity: Double

        public init(
            depth: Double,
            offset: Double,
            scale: Double,
            opacity: Double
        ) {
            self.depth = depth
            self.offset = offset
            self.scale = scale
            self.opacity = opacity
        }
    }
}
