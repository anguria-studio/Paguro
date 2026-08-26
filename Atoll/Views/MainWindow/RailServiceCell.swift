import SwiftUI
import AtollCore

/// Renders and operates one service membership in either rail axis.
struct RailServiceCell<ContextMenu: View>: View {
    let link: SpaceServiceLink
    let workspaceLinks: [SpaceServiceLink]
    let liveLinks: [SpaceServiceLink]
    @Binding var selectedSpaceID: UUID?
    @Binding var selectedServiceID: UUID?
    let axis: Axis
    let sidebarPresentation: SidebarPresentation
    let supplementaryWorkspaceName: String?
    let dockLayout: DockMagnificationLayout
    let dockMagnification: DockMagnificationState
    let focusedLinkID: FocusState<UUID?>.Binding

    @Environment(AppState.self) private var appState
    @State private var measuredSize: CGSize?
    private let contextMenuContent: () -> ContextMenu

    init(
        link: SpaceServiceLink,
        workspaceLinks: [SpaceServiceLink],
        liveLinks: [SpaceServiceLink],
        selectedSpaceID: Binding<UUID?>,
        selectedServiceID: Binding<UUID?>,
        axis: Axis,
        sidebarPresentation: SidebarPresentation,
        supplementaryWorkspaceName: String?,
        dockLayout: DockMagnificationLayout,
        dockMagnification: DockMagnificationState,
        focusedLinkID: FocusState<UUID?>.Binding,
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
        self.dockLayout = dockLayout
        self.dockMagnification = dockMagnification
        self.focusedLinkID = focusedLinkID
        self.contextMenuContent = contextMenu
    }

    var body: some View {
        row
            .draggable(link.id.uuidString) {
                Text(link.service.label)
                    .font(.caption)
                    .padding(6)
                    .atollMaterialBackground(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: AtollRadius.control))
            }
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
            .contextMenu(menuItems: contextMenuContent)
            .focusable()
            .focused(focusedLinkID, equals: link.id)
            .focusEffectDisabled()
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
        let displayedIconSize = dockLayout.iconSize(for: link.id)
        let baseIconSize = appState.iconRailBaseSize

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
            dockIconSize: displayedIconSize,
            dockItemSize: AtollMetric.Sidebar.dockItemSize(
                displayedIconSize: Double(displayedIconSize)
            ),
            dockRowHeight: AtollMetric.Sidebar.dockRowHeight(
                displayedIconSize: Double(displayedIconSize)
            ),
            dockIconHorizontalOffset: CGFloat(DockIconSizing.horizontalOffset(
                baseSize: baseIconSize,
                displayedIconSize: Double(displayedIconSize)
            )),
            dockTooltipLeadingOffset: CGFloat(DockIconSizing.tooltipLeadingOffset(
                baseSize: baseIconSize,
                displayedIconSize: Double(displayedIconSize)
            )),
            supplementaryWorkspaceName: supplementaryWorkspaceName,
            isDockHovered: dockMagnification.hoveredLinkID == link.id,
            dockMagnificationActive: dockMagnification.hoveredLinkID != nil
                && appState.iconRailMagnificationEnabled,
            onDockHoverChange: { hovering in
                if hovering {
                    dockMagnification.beginHover(for: link.id)
                } else {
                    dockMagnification.endHover(for: link.id)
                }
            },
            isFocused: focusedLinkID.wrappedValue == link.id,
            action: select
        )
    }

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
        appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: workspaceLinks[index - 1].id,
            placement: .before
        )
    }

    private func moveDown() {
        guard let index = workspaceLinks.firstIndex(where: { $0.id == link.id }),
              index < workspaceLinks.count - 1 else { return }
        appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: workspaceLinks[index + 1].id,
            placement: .after
        )
    }
}
