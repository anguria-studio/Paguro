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
    @State var confirmingDelete: SpaceServiceLink?
    @State var editingService: ServiceInstance?
    @State private var dockMagnification = DockMagnificationState()
    /// The live order and the drag state of a Dock-style reorder.
    @State private var railReorder = RailReorderState()
    /// The scroll values that automatic scroll reads during a reorder drag.
    @State private var railScroll = RailScrollGeometry()
    @State private var railScrollPosition = ScrollPosition()
    /// Empty means every workspace starts expanded. Keeping only collapsed IDs
    /// also makes a newly created workspace appear without another state sync.
    @State private var collapsedWorkspaceIDs: Set<UUID> = []
    /// The link whose service is being moved into a brand-new space: set when the
    /// user picks "New Workspace…", it presents the workspace editor and, on create,
    /// moves the service into the freshly made space.
    @State var movingToNewSpace: SpaceServiceLink?
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

    private var liveLinks: [SpaceServiceLink] {
        return allLinks
            // Guard all three relationships before reading `$0.space.id`: a
            // deleted relationship would fault the freed model on this render path.
            .filter {
                $0.modelContext != nil
                    && $0.service.modelContext != nil
                    && $0.space.modelContext != nil
            }
    }

    /// The saved order of one workspace, with the live drag order applied.
    ///
    /// Every rail arrangement reads its cells through this method, so a drag
    /// reflows the icon dock, the expanded rows, and the top bar in one place.
    private func links(in workspaceID: UUID) -> [SpaceServiceLink] {
        railReorder.ordered(modelLinks(in: workspaceID), in: workspaceID)
    }

    /// The saved order of one workspace, without the live drag order.
    private func modelLinks(in workspaceID: UUID) -> [SpaceServiceLink] {
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

    private var filteredLinks: [SpaceServiceLink] {
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
        return workspaceGroups.map { RailBarGroup(space: $0.space, links: $0.links) }
    }

    private var workspaceGroups: [WorkspaceLinkGroup] {
        liveSpaces.map { space in
            WorkspaceLinkGroup(space: space, links: links(in: space.id))
        }
    }

    private var dockWorkspaceGroups: [WorkspaceLinkGroup] {
        workspaceGroups.filter { !$0.links.isEmpty }
    }

    private var dockLinks: [SpaceServiceLink] {
        showsAllWorkspaces ? dockWorkspaceGroups.flatMap(\.links) : filteredLinks
    }

    private var dockDividerCount: Int {
        showsAllWorkspaces ? max(0, dockWorkspaceGroups.count - 1) : 0
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
                contentInset: contentInset,
                dockMagnification: dockMagnification,
                spaceHeader: { spaceHeader },
                workspaceLabel: { space in barWorkspaceLabel(for: space) },
                serviceCell: { link, groupLinks, dockLayout in
                    serviceRow(
                        for: link,
                        workspaceLinks: groupLinks,
                        dockLayout: dockLayout
                    )
                }
            )
        }
    }

    /// A compact source list in expanded form and an icon dock when collapsed.
    private var verticalBody: some View {
        let dockLayout = dockMagnification.layout(
            linkIDs: dockLinks.map(\.id),
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            // Magnification changes the item pitch. Hold it while a person
            // moves a cell, so the reorder keeps one measure.
            magnificationEnabled: appState.iconRailMagnificationEnabled
                && !railReorder.isDragging,
            isCollapsed: sidebarPresentation == .collapsed
        )

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
                        verticalRailContent(dockLayout: dockLayout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, dockRailTopPadding(viewportHeight: geometry.size.height))
                    .padding(.bottom, sidebarPresentation == .expanded ? 8 : 0)
                    .offset(y: dockLayout.stackVerticalOffset)
                    .animation(
                        reduceMotion
                            ? nil
                            : .smooth(duration: BlattaMotion.dockMagnificationSeconds),
                        value: dockLayout.stackVerticalOffset
                    )
                    // The drag measures inside the scrolling stack. A pointer
                    // position then stays correct while the rail scrolls.
                    .coordinateSpace(.named(RailCoordinateSpace.name))
                }
                .scrollClipDisabled(sidebarPresentation == .collapsed)
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
    private func verticalRailContent(
        dockLayout: DockMagnificationLayout
    ) -> some View {
        if showsAllWorkspaces && sidebarPresentation == .expanded {
            ForEach(Array(workspaceGroups.enumerated()), id: \.element.id) { index, group in
                workspaceSection(
                    group,
                    dockLayout: dockLayout,
                    topSpacing: index == 0
                        ? 0
                        : BlattaMetric.Sidebar.workspaceSectionTopSpacing
                )
            }
        } else if showsAllWorkspaces && sidebarPresentation == .collapsed {
            ForEach(Array(dockWorkspaceGroups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider()
                        .padding(
                            .horizontal,
                            BlattaMetric.Sidebar.workspaceDividerHorizontalInset
                        )
                        .frame(height: BlattaMetric.Sidebar.workspaceDividerHeight)
                        .accessibilityHidden(true)
                }
                ForEach(group.links) { link in
                    serviceRow(
                        for: link,
                        workspaceLinks: group.links,
                        dockLayout: dockLayout
                    )
                }
            }
        } else {
            let links = filteredLinks
            ForEach(links) { link in
                serviceRow(for: link, workspaceLinks: links, dockLayout: dockLayout)
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(
        _ group: WorkspaceLinkGroup,
        dockLayout: DockMagnificationLayout,
        topSpacing: CGFloat
    ) -> some View {
        let space = group.space
        let isExpanded = !collapsedWorkspaceIDs.contains(space.id)
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
            if isExpanded {
                collapsedWorkspaceIDs.insert(space.id)
            } else {
                collapsedWorkspaceIDs.remove(space.id)
            }
        }
        .padding(.top, topSpacing)
        .contextMenu {
            workspaceContextMenu(for: space)
        }

        if isExpanded {
            ForEach(group.links) { link in
                serviceRow(
                    for: link,
                    workspaceLinks: group.links,
                    dockLayout: dockLayout
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
            selectedSpaceID = space.id
        }
        .contextMenu {
            workspaceContextMenu(for: space)
        }
    }

    // MARK: - Service cells

    private func serviceRow(
        for link: SpaceServiceLink,
        workspaceLinks: [SpaceServiceLink],
        dockLayout: DockMagnificationLayout
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
            dockLayout: dockLayout,
            dockMagnification: dockMagnification,
            railReorder: railReorder,
            railSpacing: axis == .vertical
                ? verticalRailSpacing
                : ServiceRowView.tabSpacing,
            focusedLinkID: $focusedLinkID,
            showsKeyboardFocusRing: $showsKeyboardFocusRing
        ) {
            serviceContextMenu(for: link)
        }
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
    let links: [SpaceServiceLink]

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
