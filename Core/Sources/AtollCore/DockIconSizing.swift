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

    /// Places the label after both the rail edge and the visible icon edge.
    /// The result is relative to the leading edge of the selection area.
    public static func tooltipLeadingOffset(
        baseSize: Double,
        displayedIconSize: Double
    ) -> Double {
        let base = self.baseSize(baseSize)
        let selection = selectionSize(baseSize: base)
        let iconEdge = (selection / 2)
            + horizontalOffset(baseSize: base, displayedIconSize: displayedIconSize)
            + (displayedIconSize / 2)
        let railEdge = (railWidth(baseSize: base) + selection) / 2
        return max(iconEdge, railEdge) + tooltipGap
    }

    /// Returns the size for one icon while another icon is under the pointer.
    /// The nearest neighbors grow less, like the macOS Dock.
    public static func displayedSize(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemIndex: Int,
        hoveredIndex: Int?
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard magnificationEnabled, let hoveredIndex else { return base }

        let peak = self.magnifiedSize(magnifiedSize, baseSize: base)
        let distance = abs(itemIndex - hoveredIndex)
        let influence = switch distance {
        case 0: 1.0
        case 1: 0.55
        case 2: 0.2
        default: 0.0
        }
        return base + ((peak - base) * influence)
    }

    /// Keeps the hovered icon on its original vertical center.
    ///
    /// Rows above the hovered item grow upward. Rows below it grow downward.
    /// The complete stack moves by the growth before the hovered row plus half
    /// of that row's growth.
    public static func stackVerticalOffset(
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        itemCount: Int,
        hoveredIndex: Int?
    ) -> Double {
        let base = self.baseSize(baseSize)
        guard magnificationEnabled,
              let hoveredIndex,
              itemCount > 0,
              (0..<itemCount).contains(hoveredIndex)
        else { return 0 }

        let baseHeight = rowHeight(displayedIconSize: base)
        var growthBeforeHoveredItem = 0.0

        if hoveredIndex > 0 {
            for itemIndex in 0..<hoveredIndex {
                let size = displayedSize(
                    baseSize: base,
                    magnifiedSize: magnifiedSize,
                    magnificationEnabled: true,
                    itemIndex: itemIndex,
                    hoveredIndex: hoveredIndex
                )
                growthBeforeHoveredItem += rowHeight(displayedIconSize: size) - baseHeight
            }
        }

        let hoveredSize = displayedSize(
            baseSize: base,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: true,
            itemIndex: hoveredIndex,
            hoveredIndex: hoveredIndex
        )
        let hoveredGrowth = rowHeight(displayedIconSize: hoveredSize) - baseHeight
        return -(growthBeforeHoveredItem + (hoveredGrowth / 2))
    }
}
