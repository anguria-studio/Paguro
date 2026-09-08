import SwiftUI
import SwiftData
import BlattaCore

/// The rail of workspaces, down the left, in the layouts that give the
/// workspaces a rail of their own.
///
/// It borrows the geometry of the service rail: the same widths, the same two
/// presentations, the same surface and the same collapse control. Only its
/// cells differ — one workspace each, rather than one service each. The
/// services then live in the bar beside it, which holds the current
/// workspace's own.
///
/// The collapsed rail shows icons alone, so a workspace with no emoji falls
/// back to a folder there. Nowhere else: an emoji-less workspace elsewhere
/// keeps showing its name, which is a choice people make on purpose.
/// `RailBarPresentationPolicy.showsWorkspaceFallbackIcon` holds that rule.
struct WorkspaceRailView: View {
    @Binding var selectedSpaceID: UUID?
    var sidebarPresentation: SidebarPresentation = .expanded

    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var dockMagnification = DockMagnificationState()
    /// The live order and the drag state of a Dock-style reorder.
    @State private var railReorder = RailReorderState()
    /// The scroll values that the magnification rise measures itself against.
    @State private var railScroll = RailScrollGeometry()
    @State private var editingSpace: Space?
    @State private var confirmingDeleteSpace: Space?

    private var modelSpaces: [Space] {
        spaces.filter { $0.modelContext != nil }
    }

    /// The saved order with the live drag order applied.
    private var liveSpaces: [Space] {
        railReorder.ordered(modelSpaces, in: Self.reorderGroupID)
    }

    /// The workspaces are one set, so their live order has one group to belong
    /// to. The services have a workspace each.
    private static let reorderGroupID = UUID()

    private var isCollapsed: Bool {
        sidebarPresentation == .collapsed
    }

    var body: some View {
        rail
            .onChange(of: modelSpaces.map(\.id)) { _, modelOrder in
                railReorder.settle(modelOrder: modelOrder)
            }
            .onDisappear { railReorder.clear() }
            .sheet(item: $editingSpace) { space in
                SpaceEditorSheet(editingSpace: space, selectedSpaceID: $selectedSpaceID)
            }
            .deleteSpaceConfirmation(space: $confirmingDeleteSpace) { space in
                appState.deleteSpace(space.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workspaces")
    }

    /// What the cells need to size themselves. It holds no pointer, so the
    /// rail does not rebuild when the pointer moves.
    private var dockSizing: DockSizing {
        DockSizing(
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: appState.iconRailMagnificationEnabled
                && !railReorder.isDragging,
            isCollapsed: isCollapsed,
            itemCount: liveSpaces.count,
            spaceAbove: Double(
                dockTopPadding(viewportHeight: railScroll.viewportLength)
                    + railScroll.offset
            )
        )
    }

    private var rail: some View {
        let dockSizing = dockSizing

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: sidebarPresentation.contentTopInset)

            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: railSpacing) {
                        ForEach(Array(liveSpaces.enumerated()), id: \.element.id) { index, space in
                            cell(for: space, index: index, dockSizing: dockSizing)
                        }
                    }
                    // The drag measures inside the scrolling stack, so a
                    // pointer position stays correct while the rail scrolls.
                    .coordinateSpace(.named(RailCoordinateSpace.name))
                    .frame(maxWidth: .infinity)
                    .padding(.top, dockTopPadding(viewportHeight: geometry.size.height))
                    .padding(.bottom, isCollapsed ? 0 : 8)
                }
                .scrollClipDisabled(isCollapsed)
                // One fixed viewport receives every primary click. The
                // resolver decides which drawn icon, if any, owns the event;
                // no animated cell frame participates in mouse targeting.
                .contentShape(Rectangle())
                .simultaneousGesture(
                    dockTapGesture(
                        dockSizing: dockSizing,
                        viewportHeight: geometry.size.height
                    )
                )
                .overlay {
                    if isCollapsed,
                       dockSizing.magnificationEnabled,
                       DockHitAreaDebugConfiguration.isEnabled {
                        dockPointerDebugOverlay(
                            dockSizing: dockSizing,
                            viewportHeight: geometry.size.height
                        )
                    }
                }
                .contextMenu {
                    if isCollapsed,
                       dockSizing.magnificationEnabled,
                       let contextSpace = dockPointerTarget(dockSizing: dockSizing) {
                        workspaceContextMenu(for: contextSpace)
                    } else {
                        // An empty point in the Dock belongs to no workspace,
                        // so it keeps the menu of the rail itself.
                        addWorkspaceMenuItem
                    }
                }
                .onScrollGeometryChange(for: RailScrollGeometry.self) { scroll in
                    RailScrollGeometry(
                        offset: scroll.contentOffset.y,
                        viewportLength: scroll.containerSize.height,
                        contentLength: scroll.contentSize.height
                    )
                } action: { _, updated in
                    railScroll = updated
                }
                // Measured by the rail rather than by its cells, which the
                // pointer has already resized. See `UnifiedRailView`.
                .onContinuousHover(coordinateSpace: .local) { phase in
                    updatePointer(phase, viewportHeight: geometry.size.height)
                }
            }
            .clipShape(WorkspaceRailClipShape())
            .padding(.bottom, isCollapsed ? BlattaMetric.Sidebar.surfaceInset : 0)

            if !isCollapsed {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 14)

                    addWorkspaceButton
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 8)
                }
                .frame(height: BlattaMetric.Sidebar.footerHeight)
            }
        }
        .frame(width: sidebarPresentation.width(iconRailBaseSize: appState.iconRailBaseSize))
        .background {
            RoundedRectangle(cornerRadius: BlattaRadius.surface, style: .continuous)
                .fill(BlattaColor.sidebarCanvas(intensity: appState.liquidGlassIntensity))
                .padding(surfaceInsets)
        }
        .overlay {
            RoundedRectangle(cornerRadius: BlattaRadius.surface, style: .continuous)
                .strokeBorder(BlattaColor.shellBorder, lineWidth: 1)
                .padding(surfaceInsets)
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: BlattaMotion.sidebarTransitionSeconds),
            value: sidebarPresentation
        )
        .onChange(of: sidebarPresentation) { _, presentation in
            if presentation != .collapsed {
                dockMagnification.clearHover()
            }
        }
        .onDisappear {
            dockMagnification.clearHover()
        }
        .contextMenu {
            addWorkspaceMenuItem
        }
    }

    /// The menu of the rail itself, which every point that holds no workspace
    /// shows.
    private var addWorkspaceMenuItem: some View {
        Button("Add Workspace…") {
            appState.showAddSpace = true
        }
    }

    private var railSpacing: CGFloat {
        isCollapsed ? 0 : 2
    }

    private var surfaceInsets: EdgeInsets {
        EdgeInsets(
            top: sidebarPresentation.surfaceTopInset,
            leading: BlattaMetric.Sidebar.surfaceInset,
            bottom: sidebarPresentation.surfaceBottomInset,
            trailing: BlattaMetric.Sidebar.surfaceInset
        )
    }

    private func cell(
        for space: Space,
        index: Int,
        dockSizing: DockSizing
    ) -> some View {
        let isCurrent = space.id == selectedSpaceID
        let serviceIDs = appState.servicesForSpace(space.id).map(\.id)
        let workspaceMuted = space.isMutedEffective
        // The services of the current workspace are all in the bar above with
        // badges of their own, so a total beside its name would say it twice.
        // Every other workspace has no visible rows, so its total is the only
        // place its unread count appears.
        let badgeCount = WorkspaceNavigationPolicy.showsAggregateBadge(
            serviceRowsVisible: isCurrent
        ) && !workspaceMuted
            ? appState.badgeManager.aggregateCount(for: serviceIDs)
            : 0

        // Read here rather than in the rail, so a pointer move re-renders the
        // cells alone. See `DockMagnificationState`.
        let transform = dockMagnification.iconTransform(
            atIndex: index,
            sizing: dockSizing
        )
        let displayedIconSize = dockSizing.baseIconSize * transform.scale

        return WorkspaceCellView(
            space: space,
            isSelected: isCurrent,
            sidebarPresentation: sidebarPresentation,
            badgeCount: badgeCount,
            isMuted: NotificationMutePresentation.showsMutedState(
                scopeMuted: workspaceMuted,
                manualGlobalMute: appState.doNotDisturb
            ),
            glassStyle: appState.liquidGlassStyle,
            glassIntensity: appState.liquidGlassIntensity,
            dockIconSize: dockSizing.baseIconSize,
            dockItemSize: BlattaMetric.Sidebar.dockItemSize(
                displayedIconSize: Double(dockSizing.baseIconSize)
            ),
            dockRowHeight: BlattaMetric.Sidebar.dockRowHeight(
                displayedIconSize: Double(dockSizing.baseIconSize)
            ),
            dockTransform: transform,
            dockTooltipLeadingOffset: CGFloat(DockIconSizing.tooltipLeadingOffset(
                baseSize: appState.iconRailBaseSize,
                displayedIconSize: Double(displayedIconSize),
                railInset: Double(BlattaMetric.Sidebar.surfaceInset)
            )),
            isDockHovered: dockMagnification.hoveredLinkID == space.id,
            onDockHoverChange: { hovering in
                dockMagnification.setCellPointer(
                    hovering,
                    for: space.id,
                    reduceMotion: reduceMotion
                )
            }
        ) {
            // The cell button and the reorder gesture see the same mouse
            // events. A release that ends a drag must not switch workspace.
            guard !railReorder.consumesClick(for: space.id) else { return }
            if dockSizing.isCollapsed, dockSizing.magnificationEnabled {
                // Inside the viewport, the rail spatial tap owns activation.
                // A drawn icon can extend horizontally beyond that viewport;
                // forward only that overflow through the same resolver.
                if !dockMagnification.hasRailPointer {
                    activateDockPointerTarget(dockSizing: dockSizing)
                }
                return
            }
            selectedSpaceID = space.id
        }
        .railReorder(
            itemID: space.id,
            siblingIDs: liveSpaces.map(\.id),
            groupID: Self.reorderGroupID,
            axis: .vertical,
            railSpacing: railSpacing,
            fallbackLength: sidebarPresentation.serviceRowHeight,
            railReorder: railReorder,
            // A magnified neighbor would change the pitch under the drag.
            onBegin: { dockMagnification.clearHover() },
            commit: { commit in
                appState.reorderSpace(
                    droppedSpaceID: commit.linkID,
                    relativeTo: commit.targetLinkID,
                    placement: commit.placement
                )
            }
        )
        .accessibilityAction(.default) {
            selectedSpaceID = space.id
        }
        .contextMenu {
            if let contextSpace = dockContextSpace(
                fallback: space,
                dockSizing: dockSizing
            ) {
                workspaceContextMenu(for: contextSpace)
            }
        }
    }

    /// The index under the pointer in the stack that is currently drawn.
    private func dockPointerTargetIndex(dockSizing: DockSizing) -> Int? {
        guard let targetIndex = dockMagnification.targetIndex(sizing: dockSizing),
              liveSpaces.indices.contains(targetIndex)
        else { return nil }
        return targetIndex
    }

    private func dockPointerTarget(dockSizing: DockSizing) -> Space? {
        guard let targetIndex = dockPointerTargetIndex(dockSizing: dockSizing) else {
            return nil
        }
        return liveSpaces[targetIndex]
    }

    private func activateDockPointerTarget(dockSizing: DockSizing) {
        guard let target = dockPointerTarget(dockSizing: dockSizing) else { return }
        selectedSpaceID = target.id
    }

    private func dockContextSpace(fallback: Space, dockSizing: DockSizing) -> Space? {
        guard dockSizing.isCollapsed,
              dockSizing.magnificationEnabled,
              dockMagnification.hasRailPointer
        else {
            return fallback
        }
        return dockPointerTarget(dockSizing: dockSizing)
    }

    private func dockTapGesture(
        dockSizing: DockSizing,
        viewportHeight: CGFloat
    ) -> some Gesture {
        SpatialTapGesture(coordinateSpace: .local)
            .onEnded { value in
                guard isCollapsed,
                      dockSizing.magnificationEnabled,
                      !railReorder.isDragging
                else { return }

                moveDockPointer(
                    to: value.location,
                    viewportHeight: viewportHeight,
                    dockSizing: dockSizing
                )
                activateDockPointerTarget(dockSizing: dockSizing)
            }
    }

    private func dockPointerDebugOverlay(
        dockSizing: DockSizing,
        viewportHeight: CGFloat
    ) -> some View {
        let spill = CGFloat(DockIconSizing.maximumTargetSpill(
            baseSize: dockSizing.baseSize,
            magnifiedSize: dockSizing.magnifiedSize,
            magnificationEnabled: dockSizing.magnificationEnabled
        ))
        let restingTop = dockTopPadding(viewportHeight: viewportHeight)
            - railScroll.offset
        let restingHeight = CGFloat(dockSizing.itemCount)
            * BlattaMetric.Sidebar.dockRowHeight(
                displayedIconSize: dockSizing.baseSize
            )

        // The resolved outline reads the pointer, so this overlay re-renders on
        // every pointer move. Only the DEBUG launch argument reaches it, and it
        // takes no hit test, so the product pays nothing for it.
        var resolvedTop: CGFloat?
        var resolvedHeight: CGFloat = 0
        if let index = dockPointerTargetIndex(dockSizing: dockSizing) {
            let row = dockDrawnRow(
                atIndex: index,
                sizing: dockSizing,
                transform: dockMagnification.iconTransform(
                    atIndex: index,
                    sizing: dockSizing
                )
            )
            resolvedTop = restingTop + row.top
            resolvedHeight = row.height
        }

        return DockPointerDebugOverlay(
            targetTop: restingTop - spill,
            targetHeight: restingHeight + (spill * 2),
            resolvedTop: resolvedTop,
            resolvedHeight: resolvedHeight
        )
    }

    @ViewBuilder
    private func workspaceContextMenu(for space: Space) -> some View {
        WorkspaceContextMenuItems(
            space: space,
            allowsDelete: liveSpaces.count > 1,
            onAddService: {
                selectedSpaceID = space.id
                appState.showAddService = true
            },
            onEdit: { editingSpace = space },
            onDelete: { confirmingDeleteSpace = space }
        )
    }

    private var addWorkspaceButton: some View {
        Button {
            appState.showAddSpace = true
        } label: {
            Label("Add workspace", systemImage: "plus")
                .font(.blattaToolbarControl)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: ServiceRowView.rowWidth)
        .help("Add workspace")
    }

    private func updatePointer(_ phase: HoverPhase, viewportHeight: CGFloat) {
        guard isCollapsed,
              appState.iconRailMagnificationEnabled,
              !railReorder.isDragging
        else {
            dockMagnification.endPointerTracking(reduceMotion: reduceMotion)
            return
        }

        switch phase {
        case .active(let location):
            moveDockPointer(
                to: location,
                viewportHeight: viewportHeight,
                dockSizing: dockSizing
            )
        case .ended:
            dockMagnification.endRailPointer(reduceMotion: reduceMotion)
        }
    }

    private func moveDockPointer(
        to location: CGPoint,
        viewportHeight: CGFloat,
        dockSizing: DockSizing
    ) {
        let topPadding = dockTopPadding(viewportHeight: viewportHeight)
        let pointerPosition = DockIconSizing.stackPointerPosition(
            viewportPosition: Double(location.y),
            scrollOffset: Double(railScroll.offset),
            topPadding: Double(topPadding)
        )
        dockMagnification.movePointer(
            toRows: DockIconSizing.pointerRows(
                pointerPosition: pointerPosition,
                topPadding: 0,
                baseSize: appState.iconRailBaseSize
            ),
            position: pointerPosition,
            reduceMotion: reduceMotion
        )
        dockMagnification.routeHover(
            to: dockPointerTarget(dockSizing: dockSizing)?.id,
            reduceMotion: reduceMotion
        )
    }

    private func dockTopPadding(viewportHeight: CGFloat) -> CGFloat {
        guard isCollapsed, appState.iconRailPosition == .center else { return 0 }

        let topInset = sidebarPresentation.contentTopInset
        return CGFloat(DockIconSizing.centeredTopPadding(
            containerHeight: Double(
                viewportHeight + topInset + sidebarPresentation.surfaceBottomInset
            ),
            itemCount: liveSpaces.count,
            baseSize: appState.iconRailBaseSize,
            topInset: Double(topInset),
            bottomInset: 0
        ))
    }
}

/// Clips the scrolling workspace rail at its top and bottom while it keeps
/// horizontal room for a magnified icon and its tooltip.
private struct WorkspaceRailClipShape: Shape {
    private static let horizontalOverflow: CGFloat = 4_096

    func path(in rect: CGRect) -> Path {
        Path(
            CGRect(
                x: rect.minX - Self.horizontalOverflow,
                y: rect.minY,
                width: rect.width + (Self.horizontalOverflow * 2),
                height: rect.height
            )
        )
    }
}
