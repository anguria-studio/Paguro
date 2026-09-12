import SwiftUI
import PaguroCore

/// Renders and operates one service membership in either rail axis.
struct RailServiceCell<ContextMenu: View>: View {
    let link: LiveSpaceServiceLink
    let workspaceLinks: [LiveSpaceServiceLink]
    let liveLinks: [LiveSpaceServiceLink]
    @Binding var selectedSpaceID: UUID?
    @Binding var selectedServiceID: UUID?
    let axis: Axis
    let sidebarPresentation: SidebarPresentation
    let supplementaryWorkspaceName: String?
    /// Draws the cell as its icon alone. Only the grouped top bar sets it.
    let hidesLabel: Bool
    /// Where this cell sits in the dock stack, which is what the pointer
    /// distance is measured against.
    let dockIndex: Int
    let dockSizing: DockSizing
    let dockMagnification: DockMagnificationState
    /// The live order and the drag state that the rail container owns.
    let railReorder: RailReorderState
    /// The gap that the container puts between two cells. The cell adds it to
    /// its own measured length to get the pitch of the rail.
    let railSpacing: CGFloat
    let focusedLinkID: FocusState<UUID?>.Binding
    @Binding var showsKeyboardFocusRing: Bool
    /// Handles a click on the part of a magnified icon that extends outside
    /// the rail viewport. Inside the viewport, the rail spatial tap owns it.
    let onDockOverflowPointerAction: () -> Void
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Measured for the drop midpoint of a drag that starts outside the rail.
    /// The reorder drag inside the rail measures its own cell.
    @State private var measuredSize: CGSize?
    private let contextMenuContent: () -> ContextMenu

    init(
        link: LiveSpaceServiceLink,
        workspaceLinks: [LiveSpaceServiceLink],
        liveLinks: [LiveSpaceServiceLink],
        selectedSpaceID: Binding<UUID?>,
        selectedServiceID: Binding<UUID?>,
        axis: Axis,
        sidebarPresentation: SidebarPresentation,
        supplementaryWorkspaceName: String?,
        hidesLabel: Bool = false,
        dockIndex: Int,
        dockSizing: DockSizing,
        dockMagnification: DockMagnificationState,
        railReorder: RailReorderState,
        railSpacing: CGFloat,
        focusedLinkID: FocusState<UUID?>.Binding,
        showsKeyboardFocusRing: Binding<Bool>,
        onDockOverflowPointerAction: @escaping () -> Void = {},
        @ViewBuilder contextMenu: @escaping () -> ContextMenu
    ) {
        self.link = link
        self.workspaceLinks = workspaceLinks
        self.liveLinks = liveLinks
        self._selectedSpaceID = selectedSpaceID
        self._selectedServiceID = selectedServiceID
        self.axis = axis
        self.sidebarPresentation = sidebarPresentation
        self.supplementaryWorkspaceName = supplementaryWorkspaceName
        self.hidesLabel = hidesLabel
        self.dockIndex = dockIndex
        self.dockSizing = dockSizing
        self.dockMagnification = dockMagnification
        self.railReorder = railReorder
        self.railSpacing = railSpacing
        self.focusedLinkID = focusedLinkID
        self._showsKeyboardFocusRing = showsKeyboardFocusRing
        self.onDockOverflowPointerAction = onDockOverflowPointerAction
        self.contextMenuContent = contextMenu
    }

    var body: some View {
        row
            .railReorder(
                itemID: link.id,
                siblingIDs: workspaceLinks.map(\.id),
                groupID: link.space.id,
                axis: axis,
                railSpacing: railSpacing,
                fallbackLength: axis == .vertical
                    ? sidebarPresentation.serviceRowHeight
                    : ServiceRowView.tabTypicalWidth,
                railReorder: railReorder,
                // A magnified neighbor would change the pitch under the drag.
                onBegin: { dockMagnification.clearHover() },
                commit: { commit in
                    appState.reorderService(
                        droppedLinkID: commit.linkID,
                        relativeTo: commit.targetLinkID,
                        placement: commit.placement
                    )
                }
            )
            // Kept for a drag that starts outside the rail. An internal
            // reorder uses the gesture above instead of a system drag.
            .dropDestination(for: String.self) { items, location in
                handleDrop(items: items, location: location)
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) {
                        measuredSize = proxy.size
                    }
                }
            )
            .accessibilityAction(named: "Move up") { moveUp() }
            .accessibilityAction(named: "Move down") { moveDown() }
            .accessibilityAction(.default) { select() }
            .contextMenu(menuItems: contextMenuContent)
            .focusable()
            .focused(focusedLinkID, equals: link.id)
            .focusEffectDisabled()
            .onKeyPress(keys: [.tab]) { _ in
                showsKeyboardFocusRing = true
                return .ignored
            }
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                handleArrowKey(press)
            }
            .onKeyPress(keys: [.return, .space]) { _ in
                select()
                return .handled
            }
    }

    private var row: some View {
        let isSelected = selectedServiceID == link.service.id
            && selectedSpaceID == link.space.id
        let badge = appState.badgeManager.badgeCount(for: link.service.id)
        let hibernated = !isSelected && appState.webViewPool.isHibernated(link.service.id)
        let muted = NotificationMutePresentation.showsMutedState(
            scopeMuted: link.service.isEffectivelyMuted,
            manualGlobalMute: appState.doNotDisturb
        )
        let media = appState.webViewPool.mediaCaptureStates[link.service.id]
        let health = hibernated
            ? ServiceHealth.live
            : appState.webViewPool.health(for: link.service.id)
        // Read here rather than in the rail: the rail would then rebuild every
        // cell, and re-run the fetches behind them, on every pointer move.
        let transform = dockMagnification.iconTransform(
            atIndex: dockIndex,
            sizing: dockSizing
        )
        let baseIconSize = appState.iconRailBaseSize
        let displayedIconSize = dockSizing.baseIconSize * transform.scale

        return ServiceRowView(
            instance: link.service,
            isSelected: isSelected,
            axis: axis,
            sidebarPresentation: axis == .vertical ? sidebarPresentation : .expanded,
            badgeCount: badge,
            isHibernated: hibernated,
            isMuted: muted,
            cameraActive: media?.cameraActive ?? false,
            micActive: media?.micActive ?? false,
            micMuted: media?.micMuted ?? false,
            health: health,
            glassStyle: appState.liquidGlassStyle,
            glassIntensity: appState.liquidGlassIntensity,
            dockIconSize: dockSizing.baseIconSize,
            dockItemSize: PaguroMetric.Sidebar.dockItemSize(
                displayedIconSize: Double(dockSizing.baseIconSize)
            ),
            dockRowHeight: PaguroMetric.Sidebar.dockRowHeight(
                displayedIconSize: Double(dockSizing.baseIconSize)
            ),
            dockTransform: transform,
            dockTooltipLeadingOffset: CGFloat(DockIconSizing.tooltipLeadingOffset(
                baseSize: baseIconSize,
                displayedIconSize: Double(displayedIconSize),
                railInset: Double(PaguroMetric.Sidebar.surfaceInset)
            )),
            supplementaryWorkspaceName: supplementaryWorkspaceName,
            hidesLabel: hidesLabel,
            isDockHovered: dockMagnification.hoveredLinkID == link.id,
            onDockHoverChange: { hovering in
                dockMagnification.setCellPointer(
                    hovering,
                    for: link.id,
                    reduceMotion: reduceMotion
                )
            },
            isFocused: showsKeyboardFocusRing && focusedLinkID.wrappedValue == link.id,
            action: openAfterClick
        )
    }

    // MARK: - Drops from outside the rail

    private func handleDrop(items: [String], location: CGPoint) -> Bool {
        guard let droppedIDString = items.first,
              let droppedID = UUID(uuidString: droppedIDString),
              droppedID != link.id,
              let droppedLink = liveLinks.first(where: { $0.id == droppedID }),
              WorkspaceNavigationPolicy.allowsReorder(
                sourceWorkspaceID: droppedLink.space.id,
                targetWorkspaceID: link.space.id
              )
        else { return false }

        let placement: ServiceReorderPlacement
        if axis == .vertical {
            let midpoint = measuredSize.map { $0.height / 2 }
                ?? sidebarPresentation.serviceRowHeight / 2
            placement = location.y < midpoint ? .before : .after
        } else {
            let midpoint = measuredSize.map { $0.width / 2 }
                ?? ServiceRowView.tabTypicalWidth / 2
            placement = location.x < midpoint ? .before : .after
        }
        return appState.reorderService(
            droppedLinkID: droppedID,
            relativeTo: link.id,
            placement: placement
        )
    }

    // MARK: - Selection, keys, and VoiceOver moves

    /// The cell button and the reorder gesture see the same mouse events. A
    /// release that ends a drag must not open the service.
    private func openAfterClick() {
        guard !railReorder.consumesClick(for: link.id) else { return }
        if dockSizing.isCollapsed, dockSizing.magnificationEnabled {
            // The rail spatial tap handles its complete viewport. A magnified
            // icon can extend horizontally beyond that viewport; only this
            // semantic cell exists there, so it forwards that overflow click
            // through the same resolver and keeps no identity of its own.
            if !dockMagnification.hasRailPointer {
                onDockOverflowPointerAction()
            }
            return
        }
        select()
    }

    private func select() {
        selectedSpaceID = link.space.id
        selectedServiceID = link.service.id
        focusedLinkID.wrappedValue = link.id
    }

    private func handleArrowKey(_ press: KeyPress) -> KeyPress.Result {
        let movesForward: Bool
        switch (axis, press.key) {
        case (.vertical, .upArrow), (.horizontal, .leftArrow):
            movesForward = false
        case (.vertical, .downArrow), (.horizontal, .rightArrow):
            movesForward = true
        default:
            return .ignored
        }

        showsKeyboardFocusRing = true

        if press.modifiers.contains(.option) {
            if movesForward { moveDown() } else { moveUp() }
            focusedLinkID.wrappedValue = link.id
            return .handled
        }

        guard let index = workspaceLinks.firstIndex(where: { $0.id == link.id }) else {
            return .handled
        }
        let neighborIndex = movesForward ? index + 1 : index - 1
        guard workspaceLinks.indices.contains(neighborIndex) else { return .handled }
        let neighbor = workspaceLinks[neighborIndex]
        selectedSpaceID = neighbor.space.id
        selectedServiceID = neighbor.service.id
        focusedLinkID.wrappedValue = neighbor.id
        return .handled
    }

    private func moveUp() {
        guard let index = workspaceLinks.firstIndex(where: { $0.id == link.id }),
              index > 0 else { return }
        _ = appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: workspaceLinks[index - 1].id,
            placement: .before
        )
    }

    private func moveDown() {
        guard let index = workspaceLinks.firstIndex(where: { $0.id == link.id }),
              index < workspaceLinks.count - 1 else { return }
        _ = appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: workspaceLinks[index + 1].id,
            placement: .after
        )
    }
}

/// The values that make a rail cell move to a new position.
struct RailReorderToken: Equatable {
    let order: [UUID]
    let draggingLinkID: UUID?
}
