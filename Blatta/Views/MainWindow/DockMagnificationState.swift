import Foundation
import Observation
import SwiftUI
import BlattaCore

/// Owns the collapsed rail's hover lifecycle and derives one layout snapshot
/// for all visible service rows.
@MainActor
@Observable
final class DockMagnificationState {
    private(set) var hoveredLinkID: UUID?
    @ObservationIgnored private var hoverExitTask: Task<Void, Never>?

    /// Hover entry is immediate and cancels a pending exit from another row.
    func beginHover(for linkID: UUID) {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        hoveredLinkID = linkID
    }

    /// A short exit delay lets the magnified row settle under a still pointer.
    func endHover(
        for linkID: UUID,
        after delay: Duration = BlattaMotion.dockHoverExitDelay
    ) {
        guard hoveredLinkID == linkID else { return }

        hoverExitTask?.cancel()
        hoverExitTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard self?.hoveredLinkID == linkID else { return }
            self?.hoveredLinkID = nil
        }
    }

    func clearHover() {
        hoverExitTask?.cancel()
        hoverExitTask = nil
        hoveredLinkID = nil
    }

    /// Computes the hover index once and reuses it for every row size.
    func layout(
        linkIDs: [UUID],
        baseSize: Double,
        magnifiedSize: Double,
        magnificationEnabled: Bool,
        isCollapsed: Bool
    ) -> DockMagnificationLayout {
        let defaultSize = CGFloat(DockIconSizing.baseSize(baseSize))
        guard isCollapsed else {
            return DockMagnificationLayout(defaultIconSize: defaultSize)
        }

        let hoveredIndex = hoveredLinkID.flatMap { linkIDs.firstIndex(of: $0) }
        let sizes = Dictionary(uniqueKeysWithValues: linkIDs.enumerated().map { index, linkID in
            let size = DockIconSizing.displayedSize(
                baseSize: baseSize,
                magnifiedSize: magnifiedSize,
                magnificationEnabled: magnificationEnabled,
                itemIndex: index,
                hoveredIndex: hoveredIndex
            )
            return (linkID, CGFloat(size))
        })
        let verticalOffset = DockIconSizing.stackVerticalOffset(
            baseSize: baseSize,
            magnifiedSize: magnifiedSize,
            magnificationEnabled: magnificationEnabled,
            itemCount: linkIDs.count,
            hoveredIndex: hoveredIndex
        )
        return DockMagnificationLayout(
            defaultIconSize: defaultSize,
            iconSizes: sizes,
            stackVerticalOffset: CGFloat(verticalOffset)
        )
    }
}

/// The dock values shared by every row during one rail render.
struct DockMagnificationLayout {
    let defaultIconSize: CGFloat
    var iconSizes: [UUID: CGFloat] = [:]
    var stackVerticalOffset: CGFloat = 0

    func iconSize(for linkID: UUID) -> CGFloat {
        iconSizes[linkID] ?? defaultIconSize
    }
}
