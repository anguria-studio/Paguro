import SwiftUI
import SwiftData
import BlattaCore

/// One rail, in either axis, holding the current space as its header and that
/// space's services under it.
///
/// The unified rail replaces separate service and space rails. It recovers 161
/// points in the vertical layout and 34 points in the horizontal layout. A
/// single rail has two arrangements: on the left or along the top.
///
/// The rail supports `ServiceReorder`, drag and drop, arrow keys, and VoiceOver
/// move actions. The related space controls live in `SpacePaletteView`, which
/// the header opens.
///
/// This view owns the live order of a reorder drag. `RailReorderState` holds
/// that order, and `links(in:)` gives it to every cell. `BlattaCore` owns the
/// index rules in `RailReorderRule`.
struct UnifiedRailView: View {
    @Binding var selectedSpaceID: UUID?
    @Binding var selectedServiceID: UUID?
    var axis: Axis = .vertical
    var sidebarPresentation: SidebarPresentation = .expanded
    /// Leading inset for the horizontal bar. It keeps the space header clear of
    /// the window traffic lights.
    var contentInset: CGFloat = 0

    @Query var allLinks: [SpaceServiceLink]
    @Query(sort: \Space.sortOrder) var spaces: [Space]
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingPalette = false
    @State var editingSpace: Space?
    @State var confirmingDeleteSpace: Space?
    @State var confirmingDelete: LiveSpaceServiceLink?
    @State var editingService: ServiceInstance?
    @State private var dockMagnification = DockMagnificationState()
    /// The live order and the drag state of a Dock-style reorder.
    @State private var railReorder = RailReorderState()
    /// The same, for a workspace moving among the workspaces. It is a second
    /// state rather than a second group of the one above: a workspace drag
    /// collapses the sections, so the two can never run at once, and keeping
    /// them apart keeps each one's live order to itself.
    @State private var workspaceReorder = RailReorderState()
    /// The scroll values that automatic scroll reads during a reorder drag.
    @State private var railScroll = RailScrollGeometry()
    @State private var railScrollPosition = ScrollPosition()
    /// Empty means every workspace starts expanded. Keeping only collapsed IDs
    /// also makes a newly created workspace appear without another state sync.
    @State private var collapsedWorkspaceIDs: Set<UUID> = []
    /// The link whose service is being moved into a brand-new space: set when the
    /// user picks "New Workspace…", it presents the workspace editor and, on create,
    /// moves the service into the freshly made space.
    @State var movingToNewSpace: LiveSpaceServiceLink?
    /// The service cell that currently holds keyboard focus. Two-way bound to
    /// each cell's `.focused`, so a click or Tab that focuses a cell records it
    /// here and the arrow keys move relative to it.
    @FocusState private var focusedLinkID: UUID?
    /// SwiftUI gives the first focusable row focus when the window opens. Keep
    /// that automatic focus invisible until the user starts keyboard navigation.
    @State private var showsKeyboardFocusRing = false
    var liveSpaces: [Space] {
        spaces.filter { $0.modelContext != nil }
    }

    private var liveLinks: [LiveSpaceServiceLink] {
        // Resolving here keeps every rail arrangement below from unwrapping a
        // link's ends, and drops a link whose space or service has gone.
        allLinks.compactMap(LiveSpaceServiceLink.init)
    }

    /// The saved order of one workspace, with the live drag order applied.
    ///
    /// Every rail arrangement reads its cells through this method, so a drag
    /// reflows the icon dock, the expanded rows, and the top bar in one place.
    private func links(in workspaceID: UUID) -> [LiveSpaceServiceLink] {
        railReorder.ordered(modelLinks(in: workspaceID), in: workspaceID)
    }

    /// The saved order of one workspace, without the live drag order.
    private func modelLinks(in workspaceID: UUID) -> [LiveSpaceServiceLink] {
        liveLinks
            .filter { $0.space.id == workspaceID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    /// The saved order of the workspace that waits for its committed drag.
    ///
    /// The live order stays until this value matches it. A cell then never
    /// shows the old position for one frame after the release.
    private var pendingSettleOrder: [UUID]? {
        guard let groupID = railReorder.settlingGroupID else { return nil }
        return modelLinks(in: groupID).map(\.id)
    }

    /// The gap between two cells in the vertical rail.
    private var verticalRailSpacing: CGFloat {
        sidebarPresentation == .expanded ? 2 : 0
    }

    private var filteredLinks: [LiveSpaceServiceLink] {
        guard let spaceID = selectedSpaceID else { return [] }
        return links(in: spaceID)
    }

    /// Both axes can group their services under workspace names: the vertical
    /// rail as disclosure sections, the top bar as a name before each run of
    /// tabs.
    private var groupsByWorkspace: Bool {
        RailBarPresentationPolicy.groupsByWorkspace(
            mode: appState.workspaceViewMode,
            workspaceCount: liveSpaces.count,
            hasWorkspaceRail: appState.railLayout.showsBothRails
        )
    }

    private var showsAllWorkspaces: Bool {
        axis == .vertical && groupsByWorkspace
    }

    /// The top bar drops every name and keeps the icons.
    private var showsIconsOnly: Bool {
        RailBarPresentationPolicy.showsIconsOnly(
            servicesInBar: axis == .horizontal,
            iconsOnlyPreference: appState.railBarIconsOnly
        )
    }

    /// The runs of tabs in the top bar. The grouped bar names each workspace;
    /// the plain bar is the current workspace alone, with no name.
    private var barGroups: [RailBarGroup] {
        guard axis == .horizontal && groupsByWorkspace else {
            return [RailBarGroup(space: nil, links: filteredLinks)]
        }
        // A workspace drag folds the tabs away, the way it folds the sections
        // of the sidebar: the bar is then one name after another, which is a
        // row a name can move through.
        return workspaceGroups.map {
            RailBarGroup(space: $0.space, links: isDraggingWorkspace ? [] : $0.links)
        }
    }

    private var workspaceGroups: [WorkspaceLinkGroup] {
        orderedSpaces.map { space in
            WorkspaceLinkGroup(space: space, links: links(in: space.id))
        }
    }

    /// The saved workspace order with the live drag order applied.
    private var orderedSpaces: [Space] {
        workspaceReorder.ordered(liveSpaces, in: Self.workspaceReorderGroupID)
    }

    /// The workspaces are one set, so their live order has one group to belong
    /// to. Each workspace is the group for its own services.
    private static let workspaceReorderGroupID = UUID()

    /// A workspace drag collapses every section for as long as it lasts.
    ///
    /// A section is a header and the rows under it, so a stack of sections has
    /// no single pitch to move by. Collapsed, the stack is one header after
    /// another, which is a list a cell can move through. It is also the clearer
    /// picture: a workspace moving among workspaces, with nothing else in the
    /// way.
    private var isDraggingWorkspace: Bool {
        workspaceReorder.isDragging
    }

    private var dockWorkspaceGroups: [WorkspaceLinkGroup] {
        workspaceGroups.filter { !$0.links.isEmpty }
    }

    private var dockLinks: [LiveSpaceServiceLink] {
        showsAllWorkspaces ? dockWorkspaceGroups.flatMap(\.links) : filteredLinks
    }

    private var dockDividerCount: Int {
        showsAllWorkspaces ? max(0, dockWorkspaceGroups.count - 1) : 0
    }

    /// Item indices followed by a workspace divider in the collapsed Dock.
    private var dockSeparatorAfterIndices: [Int] {
        guard showsAllWorkspaces else { return [] }

        var itemCount = 0
        return dockWorkspaceGroups.dropLast().map { group in
            itemCount += group.links.count
            return itemCount - 1
        }
    }

    private var duplicateServiceIDs: Set<UUID> {
        // The grouped top bar already names the workspace before each run of
        // tabs, so a tab there needs no workspace suffix of its own.
        guard showsAllWorkspaces else { return [] }
        let counts = Dictionary(grouping: liveLinks, by: { $0.service.id })
        return Set(counts.compactMap { serviceID, links in
            Set(links.map { $0.space.id }).count > 1 ? serviceID : nil
        })
    }

    private var currentSpace: Space? {
        guard let selectedSpaceID else { return nil }
        return liveSpaces.first { $0.id == selectedSpaceID }
    }

    // MARK: - Layout

    var body: some View {
        content
        .onChange(of: pendingSettleOrder) { _, modelOrder in
            guard let modelOrder else { return }
            railReorder.settle(modelOrder: modelOrder)
        }
        .onChange(of: liveSpaces.map(\.id)) { _, modelOrder in
            workspaceReorder.settle(modelOrder: modelOrder)
        }
        .onDisappear {
            workspaceReorder.clear()
        }
        .onDisappear {
            railReorder.clear()
        }
        .sheet(item: $editingService) { service in
            EditServiceSheet(service: service)
        }
        .sheet(item: $movingToNewSpace) { link in
            SpaceEditorSheet(
                editingSpace: nil,
                selectedSpaceID: $selectedSpaceID,
                onCreate: { newSpace in
                    appState.moveService(
                        linkID: link.id,
                        to: newSpace.id,
                        followToSpace: true
                    )
                }
            )
        }
        .sheet(item: $editingSpace) { space in
            SpaceEditorSheet(editingSpace: space, selectedSpaceID: $selectedSpaceID)
        }
        .confirmationDialog(
            "Delete \(confirmingDelete?.service.label ?? "service")?",
            isPresented: Binding(
                get: { confirmingDelete != nil },
                set: { if !$0 { confirmingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let link = confirmingDelete {
                    appState.deleteService(link.service.id)
                }
                confirmingDelete = nil
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        } message: {
            Text("This will permanently remove the service and all its data.")
        }
        // Kept on the outside of the service dialog above rather than beside it:
        // two confirmation dialogs bound to one view can race when both are
        // attached at the same level, and only one of these is ever up.
        .deleteSpaceConfirmation(space: $confirmingDeleteSpace) { space in
            appState.deleteSpace(space.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        if axis == .vertical {
            verticalBody
        } else {
            HorizontalRailView(
                groups: barGroups,
                selectedSpaceID: selectedSpaceID,
                selectedServiceID: selectedServiceID,
                // The grouped bar names every workspace already. A current
                // workspace control beside those names would say it twice.
                showsSpaceSwitcher: showsSpaceSwitcher && !groupsByWorkspace,
                // The dividers stand between runs of tabs. Folded, there are
                // no runs, and a divider between two names would sit in the
                // step the drag moves by.
                showsGroupDividers: !isDraggingWorkspace,
                contentInset: contentInset,
                dockMagnification: dockMagnification,
                spaceHeader: { spaceHeader },
                workspaceLabel: { space in barWorkspaceLabel(for: space) },
                serviceCell: { link, groupLinks, dockSizing in
                    serviceRow(
                        for: link,
                        workspaceLinks: groupLinks,
                        dockSizing: dockSizing,
                        dockIndex: 0
                    )
                }
            )
        }
    }

    /// What the cells need to size themselves. It holds no pointer, so the
    /// rail does not rebuild when the pointer moves.
    private var dockSizing: DockSizing {
        DockSizing(
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            // Magnification changes the item pitch. Hold it while a person
            // moves a cell, so the reorder keeps one measure.
            magnificationEnabled: appState.iconRailMagnificationEnabled
                && !railReorder.isDragging,
            isCollapsed: sidebarPresentation == .collapsed,
            itemCount: dockLinks.count,
            spaceAbove: Double(railSpaceAboveStack)
        )
    }

    /// A compact source list in expanded form and an icon dock when collapsed.
    private var verticalBody: some View {
        let dockSizing = dockSizing

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: sidebarPresentation.contentTopInset)

            if sidebarPresentation == .expanded
                && showsSpaceSwitcher
                && !showsAllWorkspaces {
                spaceHeader
                    .padding(.bottom, 7)
            }

            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: verticalRailSpacing) {
                        verticalRailContent(dockSizing: dockSizing)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(
                        .top,
                        dockRailTopPadding(viewportHeight: geometry.size.height)
                    )
                    .padding(.bottom, sidebarPresentation == .expanded ? 8 : 0)
                    // The drag measures inside the scrolling stack. A pointer
                    // position then stays correct while the rail scrolls.
                    .coordinateSpace(.named(RailCoordinateSpace.name))
                }
                .scrollClipDisabled(sidebarPresentation == .collapsed)
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
                    if sidebarPresentation == .collapsed,
                       dockSizing.magnificationEnabled,
                       DockHitAreaDebugConfiguration.isEnabled {
                        dockPointerDebugOverlay(
                            dockSizing: dockSizing,
                            viewportHeight: geometry.size.height
                        )
                    }
                }
                .contextMenu {
                    if sidebarPresentation == .collapsed,
                       dockSizing.magnificationEnabled,
                       let contextLink = dockPointerTarget(dockSizing: dockSizing) {
                        serviceContextMenu(for: contextLink)
                    } else {
                        // An empty point in the Dock belongs to no service, so
                        // it keeps the menu of the rail itself.
                        railCreationMenu
                    }
                }
                .scrollPosition($railScrollPosition)
                .onScrollGeometryChange(for: RailScrollGeometry.self) { scroll in
                    RailScrollGeometry(
                        offset: scroll.contentOffset.y,
                        viewportLength: scroll.containerSize.height,
                        contentLength: scroll.contentSize.height
                    )
                } action: { _, updated in
                    railScroll = updated
                }
                .task(id: railReorder.draggingLinkID) {
                    await runRailAutoscroll()
                }
                // The rail measures the pointer, not its cells: a cell reports
                // a position inside a cell the pointer has already resized,
                // which feeds the size back into its own input. This frame
                // does not resize, so the reading stays stable.
                .onContinuousHover(coordinateSpace: .local) { phase in
                    updatePointer(phase, viewportHeight: geometry.size.height)
                }
            }
            .clipShape(VerticalRailClipShape())
            .padding(
                .bottom,
                sidebarPresentation == .collapsed
                    ? BlattaMetric.Sidebar.surfaceInset
                    : 0
            )

            if sidebarPresentation == .expanded {
                VStack(spacing: 0) {
                    Divider()
                        .padding(.horizontal, 14)

                    addServiceButton
                        .frame(maxHeight: .infinity)
                        .padding(.bottom, 8)
                }
                .frame(height: BlattaMetric.Sidebar.footerHeight)
            }
        }
        .frame(
            width: sidebarPresentation.width(
                iconRailBaseSize: appState.iconRailBaseSize
            )
        )
        .background {
            RoundedRectangle(cornerRadius: BlattaRadius.surface, style: .continuous)
                .fill(
                    BlattaColor.sidebarCanvas(
                        intensity: appState.liquidGlassIntensity
                    )
                )
                .padding(
                    EdgeInsets(
                        top: sidebarPresentation.surfaceTopInset,
                        leading: BlattaMetric.Sidebar.surfaceInset,
                        bottom: sidebarPresentation.surfaceBottomInset,
                        trailing: BlattaMetric.Sidebar.surfaceInset
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: BlattaRadius.surface, style: .continuous)
                .strokeBorder(BlattaColor.shellBorder, lineWidth: 1)
                .padding(
                    EdgeInsets(
                        top: sidebarPresentation.surfaceTopInset,
                        leading: BlattaMetric.Sidebar.surfaceInset,
                        bottom: sidebarPresentation.surfaceBottomInset,
                        trailing: BlattaMetric.Sidebar.surfaceInset
                    )
                )
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: BlattaMotion.sidebarTransitionSeconds),
            value: sidebarPresentation
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: BlattaMotion.sidebarTransitionSeconds),
            value: appState.iconRailBaseSize
        )
        .onChange(of: sidebarPresentation) { _, presentation in
            if presentation != .collapsed {
                dockMagnification.clearHover()
            }
        }
        .onChange(of: appState.iconRailMagnificationEnabled) { _, enabled in
            if !enabled {
                dockMagnification.clearHover()
            }
        }
        .onChange(of: appState.workspaceViewMode) { _, _ in
            dockMagnification.clearHover()
        }
        .onChange(of: selectedSpaceID) { _, workspaceID in
            guard showsAllWorkspaces,
                  sidebarPresentation == .expanded,
                  let workspaceID
            else { return }
            collapsedWorkspaceIDs.remove(workspaceID)
        }
        .onDisappear {
            dockMagnification.clearHover()
        }
        .contextMenu {
            railCreationMenu
        }
    }

    @ViewBuilder
    private func verticalRailContent(dockSizing: DockSizing) -> some View {
        // One index for each cell in the dock stack, which is what the pointer
        // distance is measured against.
        let dockIndexes = Dictionary(
            uniqueKeysWithValues: dockLinks.enumerated().map { ($0.element.id, $0.offset) }
        )

        if showsAllWorkspaces && sidebarPresentation == .expanded {
            let groups = workspaceGroups
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                workspaceSection(
                    group,
                    dockSizing: dockSizing,
                    dockIndexes: dockIndexes,
                    siblingIDs: groups.map(\.id),
                    topSpacing: index == 0
                        ? 0
                        : BlattaMetric.Sidebar.workspaceSectionTopSpacing
                )
            }
        } else if showsAllWorkspaces && sidebarPresentation == .collapsed {
            let separatorAfterIndices = dockSeparatorAfterIndices
            ForEach(Array(dockWorkspaceGroups.enumerated()), id: \.element.id) { index, group in
                if index > 0, separatorAfterIndices.indices.contains(index - 1) {
                    DockWorkspaceDividerView(
                        afterIndex: separatorAfterIndices[index - 1],
                        dockSizing: dockSizing,
                        dockMagnification: dockMagnification
                    )
                }
                ForEach(group.links) { link in
                    serviceRow(
                        for: link,
                        workspaceLinks: group.links,
                        dockSizing: dockSizing,
                        dockIndex: dockIndexes[link.id] ?? 0
                    )
                }
            }
        } else {
            let links = filteredLinks
            ForEach(links) { link in
                serviceRow(
                    for: link,
                    workspaceLinks: links,
                    dockSizing: dockSizing,
                    dockIndex: dockIndexes[link.id] ?? 0
                )
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(
        _ group: WorkspaceLinkGroup,
        dockSizing: DockSizing,
        dockIndexes: [UUID: Int],
        siblingIDs: [UUID],
        topSpacing: CGFloat
    ) -> some View {
        let space = group.space
        let isExpanded = !collapsedWorkspaceIDs.contains(space.id) && !isDraggingWorkspace
        let workspaceMuted = space.isMutedEffective
        let showsMutedState = NotificationMutePresentation.showsMutedState(
            scopeMuted: workspaceMuted,
            manualGlobalMute: appState.doNotDisturb
        )
        let badgeCount = WorkspaceNavigationPolicy.showsAggregateBadge(
            serviceRowsVisible: isExpanded
        ) && !workspaceMuted
            ? appState.badgeManager.aggregateCount(for: group.links.map { $0.service.id })
            : 0

        WorkspaceSectionHeaderView(
            workspaceName: space.name,
            emoji: space.emoji,
            badgeCount: badgeCount,
            isMuted: showsMutedState,
            isExpanded: isExpanded
        ) {
            // The header and the reorder gesture see the same mouse events. A
            // release that ends a drag must not also fold the section.
            guard !workspaceReorder.consumesClick(for: space.id) else { return }
            if isExpanded {
                collapsedWorkspaceIDs.insert(space.id)
            } else {
                collapsedWorkspaceIDs.remove(space.id)
            }
        }
        .padding(.top, isDraggingWorkspace ? 0 : topSpacing)
        .railReorder(
            itemID: space.id,
            siblingIDs: siblingIDs,
            groupID: Self.workspaceReorderGroupID,
            axis: .vertical,
            railSpacing: verticalRailSpacing,
            fallbackLength: BlattaMetric.Sidebar.headerHeight,
            railReorder: workspaceReorder,
            commit: { commit in
                appState.reorderSpace(
                    droppedSpaceID: commit.linkID,
                    relativeTo: commit.targetLinkID,
                    placement: commit.placement
                )
            }
        )
        .contextMenu {
            workspaceContextMenu(for: space)
        }

        if isExpanded {
            ForEach(group.links) { link in
                serviceRow(
                    for: link,
                    workspaceLinks: group.links,
                    dockSizing: dockSizing,
                    dockIndex: dockIndexes[link.id] ?? 0
                )
            }
        }
    }

    // MARK: - The space header, and the palette it opens

    /// The rail names the current workspace only while it is the one rail. A
    /// workspace rail beside it already says which workspace is open, and says
    /// it for every other workspace too.
    private var showsSpaceSwitcher: Bool {
        SpaceSwitcherVisibility.showsSwitcher(spaceCount: liveSpaces.count)
            && !appState.railLayout.showsBothRails
    }

    private var spaceHeader: some View {
        let space = currentSpace
        let muted = NotificationMutePresentation.showsMutedState(
            scopeMuted: space?.isMutedEffective ?? false,
            manualGlobalMute: appState.doNotDisturb
        )

        return SpaceHeaderView(
            spaceName: space?.name,
            emoji: space?.emoji ?? "🏠",
            axis: axis,
            // The visible service rows already carry their own badges. A second
            // total beside the workspace name would repeat the same state.
            badgeCount: 0,
            isMuted: muted,
            isPaletteOpen: showingPalette
        ) {
            showingPalette = true
        }
        .popover(isPresented: $showingPalette, arrowEdge: axis == .vertical ? .trailing : .bottom) {
            SpacePaletteView(
                selectedSpaceID: $selectedSpaceID,
                onEditSpace: { editingSpace = $0 },
                onDeleteSpace: { confirmingDeleteSpace = $0 },
                onAddSpace: { appState.showAddSpace = true }
            )
            // Re-injected rather than left to inheritance, matching how
            // ContentView presents the quick switcher: the palette is
            // @Query-backed and a popover that came up without the container
            // would render an empty list.
            .environment(appState)
            .modelContainer(appState.modelContainer)
        }
        .contextMenu {
            if let space {
                workspaceContextMenu(for: space)
            }
        }
    }

    /// One workspace name in the grouped top bar. It opens that workspace.
    private func barWorkspaceLabel(for space: Space) -> some View {
        BarWorkspaceLabelView(
            workspaceName: space.name,
            emoji: space.emoji,
            isCurrent: space.id == selectedSpaceID,
            isMuted: NotificationMutePresentation.showsMutedState(
                scopeMuted: space.isMutedEffective,
                manualGlobalMute: appState.doNotDisturb
            )
        ) {
            // A release that ends a drag must not switch workspace.
            guard !workspaceReorder.consumesClick(for: space.id) else { return }
            selectedSpaceID = space.id
        }
        .railReorder(
            itemID: space.id,
            siblingIDs: orderedSpaces.map(\.id),
            groupID: Self.workspaceReorderGroupID,
            axis: .horizontal,
            railSpacing: ServiceRowView.tabSpacing,
            fallbackLength: SpaceHeaderView.barHeaderMaximumWidth,
            railReorder: workspaceReorder,
            commit: { commit in
                appState.reorderSpace(
                    droppedSpaceID: commit.linkID,
                    relativeTo: commit.targetLinkID,
                    placement: commit.placement
                )
            }
        )
        .contextMenu {
            workspaceContextMenu(for: space)
        }
    }

    // MARK: - Service cells

    private func serviceRow(
        for link: LiveSpaceServiceLink,
        workspaceLinks: [LiveSpaceServiceLink],
        dockSizing: DockSizing,
        dockIndex: Int
    ) -> some View {
        RailServiceCell(
            link: link,
            workspaceLinks: workspaceLinks,
            liveLinks: liveLinks,
            selectedSpaceID: $selectedSpaceID,
            selectedServiceID: $selectedServiceID,
            axis: axis,
            sidebarPresentation: sidebarPresentation,
            supplementaryWorkspaceName: duplicateServiceIDs.contains(link.service.id)
                ? link.space.name
                : nil,
            hidesLabel: showsIconsOnly,
            dockIndex: dockIndex,
            dockSizing: dockSizing,
            dockMagnification: dockMagnification,
            railReorder: railReorder,
            railSpacing: axis == .vertical
                ? verticalRailSpacing
                : ServiceRowView.tabSpacing,
            focusedLinkID: $focusedLinkID,
            showsKeyboardFocusRing: $showsKeyboardFocusRing,
            onDockOverflowPointerAction: {
                activateDockPointerTarget(dockSizing: dockSizing)
            }
        ) {
            if let contextLink = dockContextLink(
                fallback: link,
                dockSizing: dockSizing
            ) {
                serviceContextMenu(for: contextLink)
            }
        }
    }

    /// The index under the pointer in the stack that is currently drawn.
    private func dockPointerTargetIndex(dockSizing: DockSizing) -> Int? {
        guard let targetIndex = dockMagnification.targetIndex(
            sizing: dockSizing,
            separatorAfterIndices: dockSeparatorAfterIndices,
            separatorHeight: Double(BlattaMetric.Sidebar.workspaceDividerHeight)
        ), dockLinks.indices.contains(targetIndex) else {
            return nil
        }
        return targetIndex
    }

    /// The item under the pointer in the stack that is currently drawn.
    private func dockPointerTarget(dockSizing: DockSizing) -> LiveSpaceServiceLink? {
        guard let targetIndex = dockPointerTargetIndex(dockSizing: dockSizing) else {
            return nil
        }
        return dockLinks[targetIndex]
    }

    private func activateDockPointerTarget(dockSizing: DockSizing) {
        guard let target = dockPointerTarget(dockSizing: dockSizing) else { return }
        selectedSpaceID = target.space.id
        selectedServiceID = target.service.id
        focusedLinkID = target.id
    }

    /// A context menu opened outside the Dock keeps the semantic cell. A menu
    /// opened in an active Dock follows the item that is drawn at the pointer.
    private func dockContextLink(
        fallback: LiveSpaceServiceLink,
        dockSizing: DockSizing
    ) -> LiveSpaceServiceLink? {
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
                guard sidebarPresentation == .collapsed,
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
        let restingTop = dockRailTopPadding(viewportHeight: viewportHeight)
            - railScroll.offset
        let restingHeight = CGFloat(dockSizing.itemCount)
            * BlattaMetric.Sidebar.dockRowHeight(
                displayedIconSize: dockSizing.baseSize
            )
            + CGFloat(dockDividerCount)
                * BlattaMetric.Sidebar.workspaceDividerHeight

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
                ),
                separatorAfterIndices: dockSeparatorAfterIndices,
                separatorHeight: BlattaMetric.Sidebar.workspaceDividerHeight
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

    // MARK: - Automatic scroll

    /// Scrolls the rail while a drag holds the pointer near an edge.
    ///
    /// The vertical rail scrolls when it holds more services than its viewport
    /// shows. The loop runs only during a drag, and it stops when the drag ends
    /// or the rail goes away.
    private func runRailAutoscroll() async {
        guard railReorder.isDragging else { return }

        while !Task.isCancelled {
            do {
                try await Task.sleep(for: BlattaMotion.railAutoscrollInterval)
            } catch {
                return
            }
            guard !Task.isCancelled, railReorder.isDragging else { return }
            advanceRailAutoscroll()
        }
    }

    private func advanceRailAutoscroll() {
        guard railScroll.scrolls else { return }

        // The drag reports a position inside the scrolling stack. Remove the
        // current scroll offset to get the position inside the viewport.
        let pointerInViewport = railReorder.pointerPosition - railScroll.offset
        let step = RailReorderRule.autoscrollStep(
            pointerPosition: Double(pointerInViewport),
            viewportLength: Double(railScroll.viewportLength)
        )
        guard step != 0 else { return }

        let next = min(max(railScroll.offset + CGFloat(step), 0), railScroll.maximumOffset)
        let applied = next - railScroll.offset
        guard abs(applied) > 0.01 else { return }

        railScrollPosition.scrollTo(y: next)
        railReorder.extend(byScroll: applied)
    }

    /// Converts a pointer position in the rail viewport to a position in the
    /// resting stack, in rows. The resting stack is the one measure that the
    /// magnification does not change, so sizes taken from it cannot oscillate.
    private func updatePointer(_ phase: HoverPhase, viewportHeight: CGFloat) {
        guard sidebarPresentation == .collapsed,
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
        let topPadding = dockRailTopPadding(viewportHeight: viewportHeight)
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

    /// How far the icon stack can rise before it leaves the rail: the padding
    /// that centers it, plus the distance it has already scrolled.
    private var railSpaceAboveStack: CGFloat {
        dockRailTopPadding(viewportHeight: railScroll.viewportLength) + railScroll.offset
    }

    private func dockRailTopPadding(viewportHeight: CGFloat) -> CGFloat {
        guard sidebarPresentation == .collapsed,
              appState.iconRailPosition == .center
        else { return 0 }

        let topInset = sidebarPresentation.contentTopInset
        let windowHeight = viewportHeight
            + topInset
            + sidebarPresentation.surfaceBottomInset
        return CGFloat(DockIconSizing.centeredTopPadding(
            containerHeight: Double(windowHeight),
            itemCount: dockLinks.count,
            baseSize: appState.iconRailBaseSize,
            topInset: Double(topInset),
            bottomInset: 0,
            additionalContentHeight: Double(dockDividerCount)
                * Double(BlattaMetric.Sidebar.workspaceDividerHeight)
        ))
    }

    /// The expanded vertical rail uses a small native bordered action.
    private var addServiceButton: some View {
        Button {
            appState.showAddService = true
        } label: {
            Label("Add service", systemImage: "plus")
                .font(.blattaToolbarControl)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(width: ServiceRowView.rowWidth)
        .help("Add service")
        .disabled(selectedSpaceID == nil)
    }

}

private struct WorkspaceLinkGroup: Identifiable {
    let space: Space
    let links: [LiveSpaceServiceLink]

    var id: UUID { space.id }
}

/// Clips the scrolling rail at its top and bottom while it keeps enough
/// horizontal space for a magnified icon and its tooltip.
private struct VerticalRailClipShape: Shape {
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
