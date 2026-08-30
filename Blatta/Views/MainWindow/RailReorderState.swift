import Foundation
import Observation
import SwiftUI
import BlattaCore

/// The coordinate space that a rail reorder drag measures in.
///
/// The rail names the space on its item stack, not on the window. The stack
/// scrolls, so a pointer position in this space follows the content. Automatic
/// scroll then extends the drag without a second correction.
enum RailCoordinateSpace {
    static let name = "blattaRail"
}

/// The part of the rail scroll geometry that automatic scroll needs.
struct RailScrollGeometry: Equatable {
    var offset: CGFloat = 0
    var viewportLength: CGFloat = 0
    var contentLength: CGFloat = 0

    var maximumOffset: CGFloat {
        max(0, contentLength - viewportLength)
    }

    /// The rail scrolls only when its content is longer than its viewport.
    var scrolls: Bool {
        maximumOffset > 0.5
    }
}

/// Owns the live order of one rail group while a person drags a service cell.
///
/// The cells read this order and draw themselves in it. The dragged cell keeps
/// its position under the pointer, and the other cells move to open a space at
/// the target position. This is the macOS Dock model.
///
/// The rail commits the final position one time, on release. `BlattaCore` owns
/// the index rules in `RailReorderRule`.
@MainActor
@Observable
final class RailReorderState {
    /// The result of one complete drag, ready for `AppState.reorderService`.
    struct Commit {
        let linkID: UUID
        let targetLinkID: UUID
        let placement: ServiceReorderPlacement
    }

    /// The cell that follows the pointer. Nil when no drag is active.
    private(set) var draggingLinkID: UUID?

    /// The visible order of the group. It stays after the release until the
    /// model reports the same order, so the cells never show the old order for
    /// one frame.
    private(set) var order: [UUID] = []

    /// The offset of the dragged cell along the rail axis, in points.
    private(set) var offset: CGFloat = 0

    /// The pointer position in the rail coordinate space, along the rail axis.
    private(set) var pointerPosition: CGFloat = 0

    /// The workspace that owns the live order. Reorder stays inside one
    /// workspace, so a group is always one workspace.
    private(set) var groupID: UUID?

    /// The workspace that waits for its committed order. Nil when nothing waits.
    private(set) var settlingGroupID: UUID?

    @ObservationIgnored private var baseOrder: [UUID] = []
    @ObservationIgnored private var startIndex = 0
    @ObservationIgnored private var targetIndex = 0
    @ObservationIgnored private var suppressedClickID: UUID?
    @ObservationIgnored private var suppressedClickDeadline: Date?
    @ObservationIgnored private var lastTranslation: CGFloat = 0
    @ObservationIgnored private var lastPitch: CGFloat = 0
    @ObservationIgnored private var scrollTranslation: CGFloat = 0

    /// A click that follows a drag opens nothing. The window keeps the value
    /// for this time only, so an unused value cannot eat a later click.
    private static let suppressedClickWindow: TimeInterval = 0.25

    var isDragging: Bool { draggingLinkID != nil }

    func isDragging(_ linkID: UUID) -> Bool {
        draggingLinkID == linkID
    }

    /// Puts one group of cells in the live order.
    ///
    /// A cell that the live order does not name keeps its model position at the
    /// end. The result equals the input when no drag touches this group. The
    /// services and the workspaces both come through here, so it asks only for
    /// something with an identifier.
    func ordered<Item: Identifiable>(
        _ items: [Item],
        in groupID: UUID
    ) -> [Item] where Item.ID == UUID {
        guard self.groupID == groupID, !order.isEmpty else { return items }

        var remaining = items
        var result: [Item] = []
        result.reserveCapacity(items.count)
        for id in order {
            guard let index = remaining.firstIndex(where: { $0.id == id }) else {
                continue
            }
            result.append(remaining.remove(at: index))
        }
        result.append(contentsOf: remaining)
        return result
    }

    /// Lifts one cell out of its group.
    ///
    /// - Parameters:
    ///   - linkID: The cell that follows the pointer.
    ///   - groupID: The workspace that owns the cell.
    ///   - ids: The current order of that workspace.
    func begin(linkID: UUID, in groupID: UUID, ids: [UUID]) {
        guard !isDragging, let index = ids.firstIndex(of: linkID) else { return }

        draggingLinkID = linkID
        self.groupID = groupID
        settlingGroupID = nil
        baseOrder = ids
        order = ids
        startIndex = index
        targetIndex = index
        offset = 0
        pointerPosition = 0
        lastTranslation = 0
        lastPitch = 0
        scrollTranslation = 0
        suppressedClickID = nil
        suppressedClickDeadline = nil
    }

    /// Moves the dragged cell and opens a space at its target position.
    ///
    /// - Parameters:
    ///   - translation: Drag movement along the rail axis, in points.
    ///   - pitch: Distance between two cell centers, in points.
    ///   - pointerPosition: Pointer position in the rail coordinate space.
    func update(translation: CGFloat, pitch: CGFloat, pointerPosition: CGFloat) {
        lastTranslation = translation
        lastPitch = pitch
        // The gesture measures inside the scrolling stack, so a new value
        // already holds any movement that automatic scroll added.
        scrollTranslation = 0
        apply(
            translation: translation,
            pitch: pitch,
            pointerPosition: pointerPosition
        )
    }

    /// Adds one frame of automatic scroll to the drag.
    ///
    /// The pointer can stay still while the rail scrolls under it. The cell
    /// must follow the content, so the scroll movement extends the drag until
    /// the next pointer movement replaces it.
    ///
    /// - Parameter delta: The scroll movement in points.
    func extend(byScroll delta: CGFloat) {
        guard isDragging else { return }

        scrollTranslation += delta
        apply(
            translation: lastTranslation + scrollTranslation,
            pitch: lastPitch,
            pointerPosition: pointerPosition + delta
        )
    }

    private func apply(
        translation: CGFloat,
        pitch: CGFloat,
        pointerPosition: CGFloat
    ) {
        guard let draggingLinkID else { return }

        self.pointerPosition = pointerPosition
        targetIndex = RailReorderRule.targetIndex(
            startIndex: startIndex,
            translation: Double(translation),
            pitch: Double(pitch),
            itemCount: baseOrder.count
        )

        let liveOrder = RailReorderRule.reordered(
            baseOrder,
            movingFrom: startIndex,
            to: targetIndex
        )
        if liveOrder != order {
            order = liveOrder
        }

        let liveIndex = liveOrder.firstIndex(of: draggingLinkID) ?? startIndex
        offset = CGFloat(RailReorderRule.draggedOffset(
            translation: Double(translation),
            startIndex: startIndex,
            liveIndex: liveIndex,
            pitch: Double(pitch)
        ))
    }

    /// Puts the cell down and reports the position to commit.
    ///
    /// - Returns: The commit values, or nil when the cell keeps its position.
    func end() -> Commit? {
        guard let linkID = draggingLinkID else { return nil }

        draggingLinkID = nil
        offset = 0
        suppressedClickID = linkID
        suppressedClickDeadline = Date().addingTimeInterval(Self.suppressedClickWindow)

        guard targetIndex != startIndex,
              baseOrder.indices.contains(targetIndex),
              let groupID
        else {
            clear()
            return nil
        }

        settlingGroupID = groupID
        return Commit(
            linkID: linkID,
            targetLinkID: baseOrder[targetIndex],
            placement: targetIndex > startIndex ? .after : .before
        )
    }

    /// Removes the live order when the model reports the committed order.
    ///
    /// The rail calls this with the model order of the group that waits.
    func settle(modelOrder: [UUID]) {
        guard settlingGroupID != nil else { return }
        guard modelOrder == order else { return }
        clear()
    }

    /// Removes the live order after a failed commit or when the rail goes away.
    func clear() {
        draggingLinkID = nil
        groupID = nil
        settlingGroupID = nil
        order = []
        baseOrder = []
        offset = 0
        pointerPosition = 0
        startIndex = 0
        targetIndex = 0
        lastTranslation = 0
        lastPitch = 0
        scrollTranslation = 0
    }

    /// Tells if the release of a drag must not open the service.
    ///
    /// The cell button and the drag gesture both see the same mouse events. A
    /// drag that ends over its own cell would otherwise open that service.
    func consumesClick(for linkID: UUID) -> Bool {
        guard suppressedClickID == linkID,
              let deadline = suppressedClickDeadline,
              Date() < deadline
        else { return false }

        suppressedClickID = nil
        suppressedClickDeadline = nil
        return true
    }
}
