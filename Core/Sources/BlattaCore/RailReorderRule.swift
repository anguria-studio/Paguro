/// Rules for the drag that rearranges services in the rail.
///
/// The rail follows the macOS Dock model. The dragged item stays under the
/// pointer. The other items move away and open a space at the target position.
///
/// The rules use `Double` values, so this type stays independent of SwiftUI
/// and AppKit. One axis is enough for both rail arrangements: the vertical
/// rail supplies its vertical values, and the top bar supplies its horizontal
/// values.
public enum RailReorderRule: Sendable {
    /// Movement in points that starts a reorder drag.
    ///
    /// A shorter movement stays a click, so a cell keeps its open action.
    public static let minimumDragDistance = 6.0

    /// Size of the lifted cell while a person moves it.
    public static let liftScale = 1.07

    /// Shadow radius of the lifted cell.
    public static let liftShadowRadius = 8.0

    /// Distance from a rail edge that starts automatic scroll.
    public static let autoscrollEdgeInset = 28.0

    /// Largest automatic scroll movement for one frame.
    public static let autoscrollMaximumStep = 12.0

    /// Gives the position where the dragged item lands.
    ///
    /// The item keeps its position until the movement passes one half of the
    /// item pitch. Each further half pitch moves the item one more position.
    /// The result stays inside the list.
    ///
    /// - Parameters:
    ///   - startIndex: Position of the item when the drag started.
    ///   - translation: Drag movement along the rail axis, in points.
    ///   - pitch: Distance between two item centers, in points.
    ///   - itemCount: Number of items in the rail group.
    /// - Returns: The target position, from 0 through `itemCount - 1`.
    public static func targetIndex(
        startIndex: Int,
        translation: Double,
        pitch: Double,
        itemCount: Int
    ) -> Int {
        guard itemCount > 0 else { return 0 }
        let lastIndex = itemCount - 1
        let start = clamped(startIndex, upperBound: lastIndex)
        guard pitch > 0, translation.isFinite else { return start }

        let travelled = (abs(translation) / pitch) - 0.5
        let rounded = travelled.rounded(.up)
        guard rounded > 0 else { return start }

        // A very long movement stays inside `Int`, and the clamp below keeps it
        // inside the list.
        let magnitude = rounded >= Double(itemCount) ? itemCount : Int(rounded)
        let steps = translation < 0 ? -magnitude : magnitude
        return clamped(start + steps, upperBound: lastIndex)
    }

    /// Gives the position of the dragged item along the rail axis.
    ///
    /// The container reorders the visible list while the drag continues. That
    /// change moves the dragged item one pitch for each position it passed. The
    /// result removes that movement, so the item stays under the pointer.
    ///
    /// - Parameters:
    ///   - translation: Drag movement along the rail axis, in points.
    ///   - startIndex: Position of the item when the drag started.
    ///   - liveIndex: Position of the item in the visible list now.
    ///   - pitch: Distance between two item centers, in points.
    /// - Returns: The item offset in points.
    public static func draggedOffset(
        translation: Double,
        startIndex: Int,
        liveIndex: Int,
        pitch: Double
    ) -> Double {
        translation - (Double(liveIndex - startIndex) * pitch)
    }

    /// Gives the list with one item at a new position.
    ///
    /// An invalid position returns the original list.
    ///
    /// - Parameters:
    ///   - ids: The current list.
    ///   - startIndex: Position of the item to move.
    ///   - targetIndex: Position that the item must take.
    /// - Returns: The list in its new order.
    public static func reordered<ID>(
        _ ids: [ID],
        movingFrom startIndex: Int,
        to targetIndex: Int
    ) -> [ID] {
        guard ids.indices.contains(startIndex),
              ids.indices.contains(targetIndex),
              startIndex != targetIndex
        else { return ids }

        var result = ids
        let moved = result.remove(at: startIndex)
        result.insert(moved, at: targetIndex)
        return result
    }

    /// Gives the automatic scroll movement for one frame.
    ///
    /// The rail scrolls when the pointer comes near an edge. A negative result
    /// moves the content toward the start of the rail. A positive result moves
    /// it toward the end. The speed increases near the edge.
    ///
    /// - Parameters:
    ///   - pointerPosition: Pointer position inside the visible rail, in points.
    ///   - viewportLength: Length of the visible rail, in points.
    ///   - edgeInset: Width of the band that starts the scroll.
    ///   - maximumStep: Largest movement for one frame.
    /// - Returns: The scroll movement in points.
    public static func autoscrollStep(
        pointerPosition: Double,
        viewportLength: Double,
        edgeInset: Double = autoscrollEdgeInset,
        maximumStep: Double = autoscrollMaximumStep
    ) -> Double {
        guard pointerPosition.isFinite,
              edgeInset > 0,
              viewportLength > edgeInset * 2
        else { return 0 }

        if pointerPosition < edgeInset {
            let depth = (edgeInset - max(pointerPosition, 0)) / edgeInset
            return -maximumStep * min(1, depth)
        }

        let farBand = viewportLength - edgeInset
        if pointerPosition > farBand {
            let depth = (min(pointerPosition, viewportLength) - farBand) / edgeInset
            return maximumStep * min(1, depth)
        }

        return 0
    }

    private static func clamped(_ index: Int, upperBound: Int) -> Int {
        min(max(index, 0), upperBound)
    }
}
