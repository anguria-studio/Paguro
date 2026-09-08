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
    /// Pointer position from the resting top of the first row. Unlike
    /// `pointerRows`, this value keeps workspace-divider heights. Event-time
    /// target resolution uses it without changing any view geometry.
    private(set) var pointerPosition: Double?
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
    /// Cells report only whether a pointer is on horizontal overflow. They do
    /// not choose the hovered item. The rail owns that choice.
    @ObservationIgnored private var cellPointerIDs: Set<UUID> = []
    @ObservationIgnored private var hoverExitTask: Task<Void, Never>?
    @ObservationIgnored private var pointerExitTask: Task<Void, Never>?
    /// When the animated rise of `magnificationProgress` started, and when its
    /// animated fall started. Only one of them is set at a time.
    ///
    /// `withAnimation` writes the model value at once and interpolates the
    /// drawing alone. The model therefore leads the pixels for the length of
    /// the animation. These instants let the resolver answer for the drawing
    /// instead of for the model. See `resolverProgress`.
    @ObservationIgnored private var riseStart: ContinuousClock.Instant?
    @ObservationIgnored private var fallStart: ContinuousClock.Instant?
    /// How long the magnification takes to rise and to fall. A test can shorten
    /// it. The drawing and the resolver both read this one value, so they
    /// cannot part.
    @ObservationIgnored private let magnificationSeconds: Double

    init(magnificationSeconds: Double = BlattaMotion.dockMagnificationSeconds) {
        self.magnificationSeconds = magnificationSeconds
    }

    /// True only while pointer events come from the rail itself. A semantic
    /// activation with no rail pointer must keep the cell's own identity.
    var hasRailPointer: Bool { railHasPointer }

    /// Hover entry is immediate and cancels a pending exit from another row.
    func beginHover(for linkID: UUID) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        hoveredLinkID = linkID
    }

    /// Routes the rail's current pointer to one item. A nil item starts the
    /// existing delayed exit but keeps magnification while the rail has the
    /// pointer.
    func routeHover(to linkID: UUID?, reduceMotion: Bool = false) {
        if let linkID {
            // The pointer stays on one item for many events. Write the
            // observable identity only when it changes, because every cell
            // reads it. A repeated route still cancels a pending exit: the
            // pointer is on that item now.
            guard linkID != hoveredLinkID else {
                hoverExitTask?.cancel()
                hoverExitTask = nil
                return
            }
            beginHover(for: linkID)
        } else if let hoveredLinkID {
            endHover(for: hoveredLinkID, reduceMotion: reduceMotion)
        }
    }

    /// Keeps magnification open when an icon extends past the rail. Cell hover
    /// does not change `hoveredLinkID`; the rail resolved that identity before
    /// the pointer left its bounds.
    func setCellPointer(
        _ hasPointer: Bool,
        for linkID: UUID,
        reduceMotion: Bool = false
    ) {
        if hasPointer {
            cellPointerIDs.insert(linkID)
            // Inside the rail, its resolver owns hover identity. A resting
            // cell can also report hover there, but it must not preserve an
            // identity that the rail has just resolved to nil. Cells keep the
            // effect open only after the pointer leaves the rail horizontally.
            if !railHasPointer {
                hoverExitTask?.cancel()
                hoverExitTask = nil
            }
            pointerExitTask?.cancel()
            pointerExitTask = nil
            return
        }

        cellPointerIDs.remove(linkID)
        guard !railHasPointer,
              cellPointerIDs.isEmpty,
              let hoveredLinkID
        else { return }
        endHover(for: hoveredLinkID, reduceMotion: reduceMotion)
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
            if !self.railHasPointer, self.cellPointerIDs.isEmpty {
                self.endPointerTracking(reduceMotion: reduceMotion)
            }
        }
    }

    /// The pointer moved inside the rail. Reported by the rail rather than by
    /// its cells: a cell reports where the pointer is in a cell that the
    /// pointer itself resized, which feeds the size back into its own input.
    func movePointer(
        toRows rows: Double,
        position: Double? = nil,
        reduceMotion: Bool = false
    ) {
        pointerExitTask?.cancel()
        pointerExitTask = nil

        railHasPointer = true
        pointerRows = rows
        pointerPosition = position

        // The effect is raised whenever it is not already up, rather than only
        // on the first move. A pointer that returns while the effect is fading
        // out still has a position, and asking only about the position would
        // leave the effect down with the pointer inside the rail.
        guard magnificationProgress < 1 else { return }
        guard !reduceMotion else {
            // Reduce motion applies the progress at once, so the model and the
            // drawing agree and the resolver needs no ramp.
            riseStart = nil
            fallStart = nil
            magnificationProgress = 1
            return
        }
        riseStart = ContinuousClock.now
        fallStart = nil
        withAnimation(.smooth(duration: magnificationSeconds)) {
            magnificationProgress = 1
        }
    }

    /// The pointer left the rail's own bounds. It may still be on a magnified
    /// icon that reaches past them, which the cell reports; the effect then
    /// stays as it is until the cell reports the pointer gone as well.
    func endRailPointer(reduceMotion: Bool = false) {
        railHasPointer = false
        if cellPointerIDs.isEmpty, let hoveredLinkID {
            endHover(for: hoveredLinkID, reduceMotion: reduceMotion)
        } else if hoveredLinkID == nil {
            endPointerTracking(reduceMotion: reduceMotion)
        }
    }

    /// The pointer left the rail. The magnification falls away first, and the
    /// position is dropped after it: dropping the position first would take
    /// every icon back to its base size in one frame.
    func endPointerTracking(reduceMotion: Bool = false) {
        railHasPointer = false
        guard pointerRows != nil, magnificationProgress > 0 else { return }

        pointerExitTask?.cancel()
        guard !reduceMotion else {
            riseStart = nil
            fallStart = nil
            magnificationProgress = 0
            pointerRows = nil
            pointerPosition = nil
            return
        }

        riseStart = nil
        fallStart = ContinuousClock.now
        withAnimation(.smooth(duration: magnificationSeconds)) {
            magnificationProgress = 0
        }
        let fallSeconds = magnificationSeconds
        pointerExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(fallSeconds))
            } catch {
                return
            }
            guard self?.magnificationProgress == 0 else { return }
            self?.pointerRows = nil
            self?.pointerPosition = nil
        }
    }

    func clearHover() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        pointerExitTask?.cancel()
        pointerExitTask = nil
        hoveredLinkID = nil
        railHasPointer = false
        cellPointerIDs = []
        pointerRows = nil
        pointerPosition = nil
        riseStart = nil
        fallStart = nil
        magnificationProgress = 0
    }

    /// How much of the magnification is drawn now, rather than how much the
    /// model already holds.
    ///
    /// `withAnimation` writes 1 on entry and 0 on exit at once. Only the
    /// drawing takes the animation. The model therefore leads the pixels by
    /// the animation length, and a click in that window would resolve against
    /// a stack that the screen has not reached. The resolver must answer for
    /// what is drawn, so it rebuilds the progress from the time since the
    /// animation started.
    ///
    /// The ramp is linear where the drawing uses a `.smooth` curve. This
    /// approximation is enough: the two agree at both ends, they part by a
    /// fraction of one icon in between, and the value is read at event time
    /// alone. It never feeds a drawing, so it cannot make an animation loop.
    private var resolverProgress: Double {
        if let riseStart {
            return elapsedFraction(since: riseStart)
        }
        if let fallStart {
            return max(0, 1 - elapsedFraction(since: fallStart))
        }
        return magnificationProgress
    }

    /// How much of the animation has run, 0 to 1.
    private func elapsedFraction(since start: ContinuousClock.Instant) -> Double {
        guard magnificationSeconds > 0 else { return 1 }

        let elapsed = start.duration(to: ContinuousClock.now)
        let seconds = Double(elapsed.components.seconds)
            + (Double(elapsed.components.attoseconds) / 1e18)
        return min(max(seconds / magnificationSeconds, 0), 1)
    }

    /// Resolves one event against the stack that the rail currently draws.
    /// The call performs pure arithmetic and does not update a hit shape.
    func targetIndex(
        sizing: DockSizing,
        separatorAfterIndices: [Int] = [],
        separatorHeight: Double = 0
    ) -> Int? {
        guard sizing.isCollapsed, let pointerPosition else { return nil }
        return DockIconSizing.targetIndex(
            pointerPosition: pointerPosition,
            baseSize: sizing.baseSize,
            magnifiedSize: sizing.magnifiedSize,
            magnificationEnabled: sizing.magnificationEnabled,
            itemCount: sizing.itemCount,
            pointerRows: pointerRows,
            magnificationProgress: resolverProgress,
            spaceAbove: sizing.spaceAbove,
            separatorAfterIndices: separatorAfterIndices,
            separatorHeight: separatorHeight
        )
    }

    /// How far the workspace divider moves. It keeps its size and stays
    /// centered between the two icons that it parts, so the break follows the
    /// stack instead of standing still while the icons slide past it.
    func separatorTransform(afterIndex: Int, sizing: DockSizing) -> DockIconTransform {
        guard sizing.isCollapsed else { return DockIconTransform() }

        return DockIconTransform(
            scale: 1,
            verticalOffset: CGFloat(DockIconSizing.separatorVerticalOffset(
                afterIndex: afterIndex,
                baseSize: sizing.baseSize,
                magnifiedSize: sizing.magnifiedSize,
                magnificationEnabled: sizing.magnificationEnabled,
                itemCount: sizing.itemCount,
                pointerRows: pointerRows,
                magnificationProgress: magnificationProgress,
                spaceAbove: sizing.spaceAbove
            ))
        )
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
