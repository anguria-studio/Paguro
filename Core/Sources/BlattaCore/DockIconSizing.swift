import Foundation

/// Size rules for the collapsed service rail.
///
/// The values use `Double` so this rule stays independent of SwiftUI and
/// AppKit. The app target converts the result to `CGFloat` at the view edge.
public enum DockIconSizing {
    public static let minimumBaseSize = 14.0
    public static let maximumBaseSize = 44.0
    public static let defaultBaseSize = 22.0

    public static let minimumMagnifiedSize = 32.0
    public static let maximumMagnifiedSize = 72.0
    public static let defaultMagnification = 0.26
    public static let defaultMagnifiedSize = 35.0
    public static let minimumMagnification = 0.0
    public static let maximumMagnification = 1.0

    private static let railHorizontalPadding = 40.0
    private static let selectionPadding = 14.0
    private static let rowPadding = 22.0
    private static let tooltipGap = 12.0

    public static func baseSize(_ value: Double) -> Double {
        min(maximumBaseSize, max(minimumBaseSize, value))
    }

    public static func magnifiedSize(_ value: Double, baseSize: Double) -> Double {
        let base = self.baseSize(baseSize)
        return max(base, min(maximumMagnifiedSize, max(minimumMagnifiedSize, value)))
    }

    public static func magnification(_ value: Double) -> Double {
        min(maximumMagnification, max(minimumMagnification, value))
    }

    /// Converts the zero-based control to the icon size at full hover.
    public static func peakSize(baseSize: Double, magnification: Double) -> Double {
        let base = self.baseSize(baseSize)
        let amount = self.magnification(magnification)
        return base + ((maximumMagnifiedSize - base) * amount)
    }

    /// Converts a stored peak size to the zero-based control.
    public static func magnification(baseSize: Double, peakSize: Double) -> Double {
        let base = self.baseSize(baseSize)
        let availableGrowth = maximumMagnifiedSize - base
        guard availableGrowth > 0 else { return 0 }
        return magnification((peakSize - base) / availableGrowth)
    }

    public static func railWidth(baseSize: Double) -> Double {
        self.baseSize(baseSize) + railHorizontalPadding
    }

    public static func selectionSize(baseSize: Double) -> Double {
        self.baseSize(baseSize) + selectionPadding
    }

    /// Keeps the hover background around the complete visible icon.
    public static func selectionSize(displayedIconSize: Double) -> Double {
        min(
            maximumMagnifiedSize,
            max(minimumBaseSize, displayedIconSize)
        ) + selectionPadding
    }

    public static func rowHeight(displayedIconSize: Double) -> Double {
        max(minimumBaseSize, displayedIconSize) + rowPadding
    }

    /// Centers the base-size icon stack in its container.
    ///
    /// `topInset` is the height already consumed above the local scroll
    /// viewport. Subtracting it lets a shortened viewport align its content to
    /// the complete window's centerline.
    public static func centeredTopPadding(
        containerHeight: Double,
        itemCount: Int,
        baseSize: Double,
        topInset: Double = 0,
        bottomInset: Double,
        additionalContentHeight: Double = 0
    ) -> Double {
        guard itemCount > 0 else { return 0 }
        let availableHeight = max(0, containerHeight - bottomInset)
        let stackHeight = Double(itemCount) * rowHeight(
            displayedIconSize: self.baseSize(baseSize)
        ) + max(0, additionalContentHeight)
        return max(0, ((availableHeight - stackHeight) / 2) - max(0, topInset))
    }

    /// A vertical Dock on the left grows toward the content, not equally in
    /// both horizontal directions. This offset keeps the icon's left edge in
    /// place while its right edge moves out of the rail.
    public static func horizontalOffset(
        baseSize: Double,
        displayedIconSize: Double
    ) -> Double {
        max(0, displayedIconSize - self.baseSize(baseSize)) / 2
    }

    /// Places the label after both the visible icon edge and the drawn rail
    /// surface. The result is relative to the leading edge of the selection
    /// area.
    ///
    /// The icon edge is the leading term, so the label moves out as an icon
    /// magnifies. The surface edge is only a floor, which keeps the label off
    /// the rail while the icon is small. `railInset` is the padding between the
    /// rail frame and the surface it draws; measuring the floor against the
    /// frame instead would hold the label a whole inset too far out at every
    /// size.
    public static func tooltipLeadingOffset(
        baseSize: Double,
        displayedIconSize: Double,
        railInset: Double
    ) -> Double {
        let base = self.baseSize(baseSize)
        let selection = selectionSize(baseSize: base)
        let iconEdge = (selection / 2)
            + horizontalOffset(baseSize: base, displayedIconSize: displayedIconSize)
            + (displayedIconSize / 2)
        let surfaceWidth = max(0, railWidth(baseSize: base) - (max(0, railInset) * 2))
        let surfaceEdge = (surfaceWidth + selection) / 2
        return max(iconEdge, surfaceEdge) + tooltipGap
    }

    /// Where a pointer in the rail viewport falls in the resting stack, in
    /// rows. Row 0 is the center of the first icon.
    ///
    /// `pointerPosition` is measured from the top of the resting stack: the
    /// position in the viewport plus what the rail has scrolled. The resting
    /// stack is the one measure magnification leaves alone, so a size taken
    /// from it cannot feed back into itself.
    public static func pointerRows(
        pointerPosition: Double,
        topPadding: Double,
        baseSize: Double
    ) -> Double {
        let height = rowHeight(displayedIconSize: self.baseSize(baseSize))
        guard height > 0 else { return 0 }
        return ((pointerPosition - topPadding) / height) - 0.5
    }

    /// How many rows to each side of the pointer still grow.
    public static let magnificationInfluenceRows = 2.5

    /// How much of the growth an item takes at a given distance from the
    /// pointer, measured in rows.
    ///
    /// The curve is a raised cosine: full growth under the pointer, none at the
    /// edge of its influence, and level at both ends. Level ends are what make
    /// the movement read as one motion — a curve with slope left at the edge
    /// snaps the outermost icon into and out of the set as the pointer passes.
    ///
    /// The distance is continuous, not a count of icons. The pointer at rest
    /// between two icons therefore grows both by the same amount, and a pointer
    /// moving one point moves every icon a little, rather than moving nothing
    /// until it crosses into the next icon and then moving everything at once.
    public static func magnificationInfluence(
        distanceInRows: Double,
        influenceRows: Double = magnificationInfluenceRows
    ) -> Double {
        guard distanceInRows.isFinite, influenceRows > 0 else { return 0 }
        let normalized = min(abs(distanceInRows) / influenceRows, 1)
        return (cos(normalized * .pi) + 1) / 2
    }

    /// Returns the size for one icon while the pointer is over the rail.
    ///
    /// `pointerRows` is where the pointer is along the rail, in rows, measured
    /// against the resting stack: 0 is the center of the first icon, 1.5 is the
    /// boundary between the second and the third.
    ///
    /// `magnificationProgress` is how much of the magnification applies at all.
    /// The pointer arrives at a position rather than at the edge of the rail,
    /// so this carries the animation into and out of the effect while the
    /// moves between them stay immediate.
    public static func displayedSize(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemIndex: Int,
        pointerRows: Double?,
        magnificationProgress: Double = 1
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard magnificationEnabled, let pointerRows else { return base }

        let peak = self.magnifiedSize(magnifiedSize, baseSize: base)
        let progress = min(max(magnificationProgress, 0), 1)
        let influence = magnificationInfluence(
            distanceInRows: Double(itemIndex) - pointerRows
        )
        return base + ((peak - base) * influence * progress)
    }

    /// How much larger one icon draws than it lays out.
    ///
    /// The rail lays every cell out at the base size and scales it from there.
    /// A scale is a transform: it changes no frame, so the stack does not
    /// measure itself again for each step of the pointer. Sizing the frames
    /// instead re-measures every row, the stack, and the scroll view around it
    /// on every mouse event, which is what a rail cannot afford at pointer
    /// rate.
    public static func iconScale(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemIndex: Int,
        pointerRows: Double?,
        magnificationProgress: Double = 1
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard base > 0 else { return 1 }
        let displayed = displayedSize(
            baseSize: base,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: magnificationEnabled,
            itemIndex: itemIndex,
            pointerRows: pointerRows,
            magnificationProgress: magnificationProgress
        )
        return displayed / base
    }

    /// How far one icon moves from where it lays out.
    ///
    /// The frames stay at the base pitch, so a scaled icon would sit on its
    /// neighbors. This moves each one clear: every icon before it takes half
    /// of its own growth plus all of the growth above it, and the stack's own
    /// move keeps the point under the pointer in place.
    public static func iconVerticalOffset(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemIndex: Int,
        itemCount: Int,
        pointerRows: Double?,
        magnificationProgress: Double = 1,
        spaceAbove: Double
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard magnificationEnabled, pointerRows != nil else { return 0 }

        let baseHeight = rowHeight(displayedIconSize: base)
        func growth(_ index: Int) -> Double {
            let size = displayedSize(
                baseSize: base,
                magnifiedSize: magnifiedSize,
                magnificationEnabled: true,
                itemIndex: index,
                pointerRows: pointerRows,
                magnificationProgress: magnificationProgress
            )
            return rowHeight(displayedIconSize: size) - baseHeight
        }

        var spread = 0.0
        if itemIndex > 0 {
            for index in 0..<itemIndex {
                spread += growth(index)
            }
        }
        spread += growth(itemIndex) / 2

        return spread + stackVerticalOffset(
            baseSize: base,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: magnificationEnabled,
            itemCount: itemCount,
            pointerRows: pointerRows,
            magnificationProgress: magnificationProgress,
            spaceAbove: spaceAbove
        )
    }

    /// Keeps the rail under the pointer where it was, as far as the rail can
    /// move.
    ///
    /// Every icon before the pointer grows, which pushes the point under the
    /// pointer down by that growth. The stack moves up by the same amount, so
    /// what was under the pointer stays under it. The move is continuous in
    /// `pointerRows`: the part of an icon that lies before the pointer counts
    /// for that part of its growth.
    ///
    /// `spaceAbove` is how far the stack can rise before it leaves the rail:
    /// the padding that centers it, plus whatever it has already scrolled. A
    /// rise past that would take the top icon out of the rail, where the rail
    /// clips it. The stack rises that far and no further, so the top icon grows
    /// downward from a fixed top edge instead — which is what the icon at the
    /// end of the macOS Dock does.
    public static func stackVerticalOffset(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemCount: Int,
        pointerRows: Double?,
        magnificationProgress: Double = 1,
        spaceAbove: Double
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard magnificationEnabled,
              let pointerRows,
              pointerRows.isFinite,
              itemCount > 0
        else { return 0 }

        let baseHeight = rowHeight(displayedIconSize: base)
        // The pointer measured from the top edge of the first icon rather than
        // from its center, so a whole icon before the pointer counts as one.
        let pointerFromStackTop = pointerRows + 0.5
        var rise = 0.0

        for itemIndex in 0..<itemCount {
            let share = min(max(pointerFromStackTop - Double(itemIndex), 0), 1)
            guard share > 0 else { break }

            let size = displayedSize(
                baseSize: base,
                magnifiedSize: magnifiedSize,
                magnificationEnabled: true,
                itemIndex: itemIndex,
                pointerRows: pointerRows,
                magnificationProgress: magnificationProgress
            )
            rise += (rowHeight(displayedIconSize: size) - baseHeight) * share
        }

        return -min(rise, max(0, spaceAbove))
    }
}
