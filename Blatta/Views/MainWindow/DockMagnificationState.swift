import Foundation
import Observation
import SwiftUI
import BlattaCore

/// Everything about a rail that the magnification needs and the pointer does
/// not change. It is passed down to the cells so each one can size itself.
struct DockSizing: Equatable {
    var baseSize: Double = DockIconSizing.defaultBaseSize
    var magnifiedSize: Double = DockIconSizing.defaultMagnifiedSize
    var magnificationEnabled = false
    var isCollapsed = false
    var itemCount = 0
    /// How far the stack may rise before it leaves the rail.
    var spaceAbove: Double = .infinity

    var baseIconSize: CGFloat {
        CGFloat(DockIconSizing.baseSize(baseSize))
    }
}

/// Owns the collapsed rail's pointer and hover lifecycle.
///
/// The sizes are read from here by each cell rather than handed down by the
/// rail. A pointer move then re-renders the cells alone: a rail that read the
/// pointer would rebuild its complete cell list, with the fetches behind it, on
/// every mouse event.
@MainActor
@Observable
final class DockMagnificationState {
    private(set) var hoveredLinkID: UUID?
    /// Where the pointer is along the rail, in rows of the resting stack. It is
    /// what sizes every icon: a position rather than a choice of icon, so the
    /// rail follows the pointer instead of stepping between icons.
    private(set) var pointerRows: Double?
    /// How much of the magnification is applied, 0 to 1.
    ///
    /// The pointer arrives at a position, not at the edge of the rail, so the
    /// icon under it would otherwise jump to its full size in one frame. This
    /// takes the animation instead: it rises on entry and falls on exit, while
    /// the pointer moves between them carry no animation at all.
    private(set) var magnificationProgress: Double = 0
    /// True while the rail itself reports the pointer. A magnified icon reaches
    /// past the rail, so the pointer over that part is outside the rail and
    /// inside a cell. The cell then holds the effect open, and the last known
    /// position holds still, rather than the icon shrinking away from under the
    /// pointer and growing back the moment it lands inside again.
    @ObservationIgnored private var railHasPointer = false
    @ObservationIgnored private var hoverExitTask: Task<Void, Never>?
    @ObservationIgnored private var pointerExitTask: Task<Void, Never>?

    /// Hover entry is immediate and cancels a pending exit from another row.
    func beginHover(for linkID: UUID) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        hoveredLinkID = linkID
    }

    /// A short exit delay lets the magnified row settle under a still pointer.
    func endHover(
        for linkID: UUID,
        after delay: Duration = BlattaMotion.dockHoverExitDelay,
        reduceMotion: Bool = false
    ) {
        guard hoveredLinkID == linkID else { return }

        hoverExitTask?.cancel()
        hoverExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, self.hoveredLinkID == linkID else { return }
            self.hoveredLinkID = nil
            // The pointer is off the cell as well as off the rail.
            if !self.railHasPointer {
                self.endPointerTracking(reduceMotion: reduceMotion)
            }
        }
    }

    /// The pointer moved inside the rail. Reported by the rail rather than by
    /// its cells: a cell reports where the pointer is in a cell that the
    /// pointer itself resized, which feeds the size back into its own input.
    func movePointer(toRows rows: Double, reduceMotion: Bool = false) {
        pointerExitTask?.cancel()
        pointerExitTask = nil

        railHasPointer = true
        pointerRows = rows

        // The effect is raised whenever it is not already up, rather than only
        // on the first move. A pointer that returns while the effect is fading
        // out still has a position, and asking only about the position would
        // leave the effect down with the pointer inside the rail.
        guard magnificationProgress < 1 else { return }
        guard !reduceMotion else {
            magnificationProgress = 1
            return
        }
        withAnimation(.smooth(duration: BlattaMotion.dockMagnificationSeconds)) {
            magnificationProgress = 1
        }
    }

    /// The pointer left the rail's own bounds. It may still be on a magnified
    /// icon that reaches past them, which the cell reports; the effect then
    /// stays as it is until the cell reports the pointer gone as well.
    func endRailPointer(reduceMotion: Bool = false) {
        railHasPointer = false
        guard hoveredLinkID == nil else { return }
        endPointerTracking(reduceMotion: reduceMotion)
    }

    /// The pointer left the rail. The magnification falls away first, and the
    /// position is dropped after it: dropping the position first would take
    /// every icon back to its base size in one frame.
    func endPointerTracking(reduceMotion: Bool = false) {
        railHasPointer = false
        guard pointerRows != nil, magnificationProgress > 0 else { return }

        pointerExitTask?.cancel()
        guard !reduceMotion else {
            magnificationProgress = 0
            pointerRows = nil
            return
        }

        withAnimation(.smooth(duration: BlattaMotion.dockMagnificationSeconds)) {
            magnificationProgress = 0
        }
        pointerExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(BlattaMotion.dockMagnificationSeconds))
            } catch {
                return
            }
            guard self?.magnificationProgress == 0 else { return }
            self?.pointerRows = nil
        }
    }

    func clearHover() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        pointerExitTask?.cancel()
        pointerExitTask = nil
        hoveredLinkID = nil
        railHasPointer = false
        pointerRows = nil
        magnificationProgress = 0
    }

    /// How much larger one icon draws than it lays out, and how far it moves to
    /// stay clear of its neighbors. Both are transforms: the frames stay at the
    /// base size, so the pointer moves nothing through layout.
    func iconTransform(atIndex index: Int, sizing: DockSizing) -> DockIconTransform {
        guard sizing.isCollapsed else { return DockIconTransform() }

        let base = DockIconSizing.baseSize(sizing.baseSize)
        let displayed = DockIconSizing.displayedSize(
            baseSize: sizing.baseSize,
            magnifiedSize: sizing.magnifiedSize,
            magnificationEnabled: sizing.magnificationEnabled,
            itemIndex: index,
            pointerRows: pointerRows,
            magnificationProgress: magnificationProgress
        )

        return DockIconTransform(
            scale: base > 0 ? CGFloat(displayed / base) : 1,
            verticalOffset: CGFloat(DockIconSizing.iconVerticalOffset(
                baseSize: sizing.baseSize,
                magnifiedSize: sizing.magnifiedSize,
                magnificationEnabled: sizing.magnificationEnabled,
                itemIndex: index,
                itemCount: sizing.itemCount,
                pointerRows: pointerRows,
                magnificationProgress: magnificationProgress,
                spaceAbove: sizing.spaceAbove
            ))
        )
    }
}

/// What the pointer does to one icon: how much larger it draws, and how far it
/// moves to stay clear of its neighbors. Neither changes a frame.
struct DockIconTransform: Equatable {
    var scale: CGFloat = 1
    var verticalOffset: CGFloat = 0

    var isResting: Bool {
        scale == 1 && verticalOffset == 0
    }
}
