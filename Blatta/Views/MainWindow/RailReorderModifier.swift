import SwiftUI
import BlattaCore

/// The Dock-style reorder drag, for any rail cell that has siblings.
///
/// The service cells and the workspace cells both take it, so a workspace moves
/// the way a service does: the pressed cell follows the pointer, the others
/// move away to open a space at the target position, and the order is saved
/// once, on release.
///
/// The cell keeps the parts that belong to it — what it draws, what it opens —
/// and this owns the drag: the lift, the live order, the pitch it moves by, and
/// the commit.
struct RailReorderModifier: ViewModifier {
    /// This cell, and the siblings it moves among, in their saved order.
    let itemID: UUID
    let siblingIDs: [UUID]
    /// The set the live order belongs to: a workspace for its services, and one
    /// fixed value for the workspaces themselves.
    let groupID: UUID
    let axis: Axis
    /// The gap the container puts between two cells. The cell adds it to its
    /// own measured length to get the pitch of the rail.
    let railSpacing: CGFloat
    /// The length a cell is assumed to have before the first geometry pass.
    let fallbackLength: CGFloat
    let railReorder: RailReorderState
    /// Called before the drag starts, to hold anything that would change the
    /// pitch under it.
    var onBegin: () -> Void = {}
    /// Saves the new order. `false` puts the live order back.
    let commit: (RailReorderState.Commit) -> Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var measuredSize: CGSize?

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) {
                        measuredSize = proxy.size
                    }
                }
            )
            .scaleEffect(isLifted ? CGFloat(RailReorderRule.liftScale) : 1)
            .shadow(
                color: BlattaColor.railLiftShadow.opacity(isLifted ? 1 : 0),
                radius: isLifted ? CGFloat(RailReorderRule.liftShadowRadius) : 0,
                y: isLifted ? 3 : 0
            )
            .animation(liftAnimation, value: isLifted)
            .offset(
                x: axis == .horizontal ? dragOffset : 0,
                y: axis == .vertical ? dragOffset : 0
            )
            .zIndex(isDragging ? 1 : 0)
            // The other cells move to their new positions with this spring,
            // which is the visible Dock reflow. The dragged cell opts out, so
            // its compensating offset can hold it under the pointer.
            .animation(reorderAnimation, value: reorderToken)
            .simultaneousGesture(reorderGesture)
    }

    private var isDragging: Bool {
        railReorder.isDragging(itemID)
    }

    /// Reduce Motion keeps the reorder and removes the lift.
    private var isLifted: Bool {
        isDragging && !reduceMotion
    }

    private var dragOffset: CGFloat {
        isDragging ? railReorder.offset : 0
    }

    private var reorderToken: RailReorderToken {
        RailReorderToken(
            order: railReorder.order,
            draggingLinkID: railReorder.draggingLinkID
        )
    }

    private var liftAnimation: Animation? {
        reduceMotion ? nil : .smooth(duration: BlattaMotion.railLiftSeconds)
    }

    /// Reduce Motion moves each cell directly to its new position.
    private var reorderAnimation: Animation? {
        guard !reduceMotion, !isDragging else { return nil }
        return .spring(
            response: BlattaMotion.railReorderResponse,
            dampingFraction: BlattaMotion.railReorderDamping
        )
    }

    /// The distance between two cell centers along the rail axis.
    private var pitch: CGFloat {
        let length = if axis == .vertical {
            measuredSize?.height ?? fallbackLength
        } else {
            measuredSize?.width ?? fallbackLength
        }
        return length + railSpacing
    }

    private var reorderGesture: some Gesture {
        DragGesture(
            minimumDistance: CGFloat(RailReorderRule.minimumDragDistance),
            coordinateSpace: .named(RailCoordinateSpace.name)
        )
        .onChanged { value in
            if !railReorder.isDragging(itemID) {
                beginDrag()
            }
            guard railReorder.isDragging(itemID) else { return }
            applyDrag(value)
        }
        .onEnded { value in
            guard railReorder.isDragging(itemID) else { return }
            applyDrag(value)
            commitDrag()
        }
    }

    private func beginDrag() {
        guard !railReorder.isDragging, siblingIDs.count > 1 else { return }
        onBegin()
        railReorder.begin(linkID: itemID, in: groupID, ids: siblingIDs)
    }

    private func applyDrag(_ value: DragGesture.Value) {
        railReorder.update(
            translation: axis == .vertical
                ? value.translation.height
                : value.translation.width,
            pitch: pitch,
            pointerPosition: axis == .vertical
                ? value.location.y
                : value.location.x
        )
    }

    private func commitDrag() {
        guard let commit = railReorder.end() else { return }
        if !self.commit(commit) {
            railReorder.clear()
        }
    }
}

extension View {
    func railReorder(
        itemID: UUID,
        siblingIDs: [UUID],
        groupID: UUID,
        axis: Axis,
        railSpacing: CGFloat,
        fallbackLength: CGFloat,
        railReorder: RailReorderState,
        onBegin: @escaping () -> Void = {},
        commit: @escaping (RailReorderState.Commit) -> Bool
    ) -> some View {
        modifier(RailReorderModifier(
            itemID: itemID,
            siblingIDs: siblingIDs,
            groupID: groupID,
            axis: axis,
            railSpacing: railSpacing,
            fallbackLength: fallbackLength,
            railReorder: railReorder,
            onBegin: onBegin,
            commit: commit
        ))
    }
}
