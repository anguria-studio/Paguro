import SwiftUI
import PaguroCore

enum DockHitAreaDebugConfiguration {
    /// Read once. The overlay asks for this value on every pointer move, and
    /// the launch arguments cannot change while the application runs.
    #if DEBUG
    static let isEnabled = ProcessInfo.processInfo.arguments
        .contains("--paguro-show-hit-areas")
    #else
    static let isEnabled = false
    #endif
}

/// Shows the regions involved in Dock pointer resolution.
///
/// Green is the rail viewport that receives the event. Red is the maximum
/// vertical envelope in which the resolver can return a drawn item. Both are
/// independent of pointer movement and icon animation.
///
/// Yellow is the drawn row of the item that the resolver returns now. Unlike
/// the other two, it follows the pointer, so this view re-renders on every
/// pointer move. That cost is acceptable only because the overlay is behind
/// the DEBUG launch argument and takes no hit test. It draws a report of the
/// resolution; it never takes part in one.
struct DockPointerDebugOverlay: View {
    let targetTop: CGFloat
    let targetHeight: CGFloat
    /// Top of the resolved item's drawn row, in viewport coordinates. Nil when
    /// the resolver returns no item.
    var resolvedTop: CGFloat?
    var resolvedHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .stroke(.green.opacity(0.9), lineWidth: 1)

            Rectangle()
                .stroke(.red.opacity(0.9), lineWidth: 1)
                .frame(height: max(0, targetHeight))
                .offset(y: targetTop)

            if let resolvedTop {
                Rectangle()
                    .stroke(.yellow.opacity(0.9), lineWidth: 1)
                    .frame(height: max(0, resolvedHeight))
                    .offset(y: resolvedTop)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The drawn row of one Dock item, measured from the resting top of the stack.
///
/// It uses the transform that sizes the cell itself, so the outline follows the
/// same Core math as the drawing: the resting top of the row, the vertical
/// offset of the icon, and the row height of the displayed size.
///
/// This helper serves the debug overlay alone. Nothing here reaches a hit shape
/// or a release build.
func dockDrawnRow(
    atIndex index: Int,
    sizing: DockSizing,
    transform: DockIconTransform,
    separatorAfterIndices: [Int] = [],
    separatorHeight: CGFloat = 0
) -> (top: CGFloat, height: CGFloat) {
    let baseIconSize = DockIconSizing.baseSize(sizing.baseSize)
    let baseHeight = CGFloat(DockIconSizing.rowHeight(displayedIconSize: baseIconSize))
    let drawnHeight = CGFloat(DockIconSizing.rowHeight(
        displayedIconSize: baseIconSize * Double(transform.scale)
    ))

    let dividersAbove = separatorAfterIndices.filter { $0 >= 0 && $0 < index }.count
    let restingTop = (CGFloat(index) * baseHeight)
        + (CGFloat(dividersAbove) * max(0, separatorHeight))
    let center = restingTop + (baseHeight / 2) + transform.verticalOffset

    return (center - (drawnHeight / 2), drawnHeight)
}
