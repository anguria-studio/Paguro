import SwiftUI
import SwiftData
import AtollCore

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

    private func links(in workspaceID: UUID) -> [SpaceServiceLink] {
        liveLinks
            .filter { $0.space.id == workspaceID }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private var filteredLinks: [SpaceServiceLink] {
        guard let spaceID = selectedSpaceID else { return [] }
        return links(in: spaceID)
    }

    /// All-workspaces is a sidebar presentation. The top-bar layout stays a
    /// compact current-workspace switcher and service tab strip.
    private var showsAllWorkspaces: Bool {
        axis == .vertical
            && appState.workspaceViewMode == .all
            && liveSpaces.count > 1
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
            let links = filteredLinks
            HorizontalRailView(
                links: links,
                selectedSpaceID: selectedSpaceID,
                selectedServiceID: selectedServiceID,
                showsSpaceSwitcher: showsSpaceSwitcher,
                contentInset: contentInset,
                dockMagnification: dockMagnification,
                spaceHeader: { spaceHeader },
                serviceCell: { link, dockLayout in
                    serviceRow(
                        for: link,
                        workspaceLinks: links,
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
            magnificationEnabled: appState.iconRailMagnificationEnabled,
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
                    LazyVStack(spacing: sidebarPresentation == .expanded ? 2 : 0) {
                        verticalRailContent(dockLayout: dockLayout)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, dockRailTopPadding(viewportHeight: geometry.size.height))
                    .padding(.bottom, sidebarPresentation == .expanded ? 8 : 0)
                    .offset(y: dockLayout.stackVerticalOffset)
                    .animation(
                        reduceMotion
                            ? nil
                            : .smooth(duration: AtollMotion.dockMagnificationSeconds),
                        value: dockLayout.stackVerticalOffset
                    )
                }
                .scrollClipDisabled(sidebarPresentation == .collapsed)
            }
            .clipShape(VerticalRailClipShape())
            .padding(
                .bottom,
                sidebarPresentation == .collapsed
                    ? AtollMetric.Sidebar.surfaceInset
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
                .frame(height: AtollMetric.Sidebar.footerHeight)
            }
        }
        .frame(
            width: sidebarPresentation.width(
                iconRailBaseSize: appState.iconRailBaseSize
            )
        )
        .background {
            RoundedRectangle(cornerRadius: AtollRadius.surface, style: .continuous)
                .fill(
                    AtollColor.sidebarCanvas(
                        intensity: appState.liquidGlassIntensity
                    )
                )
                .padding(
                    EdgeInsets(
                        top: sidebarPresentation.surfaceTopInset,
                        leading: AtollMetric.Sidebar.surfaceInset,
                        bottom: sidebarPresentation.surfaceBottomInset,
                        trailing: AtollMetric.Sidebar.surfaceInset
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: AtollRadius.surface, style: .continuous)
                .strokeBorder(AtollColor.shellBorder, lineWidth: 1)
                .padding(
                    EdgeInsets(
                        top: sidebarPresentation.surfaceTopInset,
                        leading: AtollMetric.Sidebar.surfaceInset,
                        bottom: sidebarPresentation.surfaceBottomInset,
                        trailing: AtollMetric.Sidebar.surfaceInset
                    )
                )
        }
        .animation(
            reduceMotion ? nil : .smooth(duration: AtollMotion.sidebarTransitionSeconds),
            value: sidebarPresentation
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: AtollMotion.sidebarTransitionSeconds),
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
                        : AtollMetric.Sidebar.workspaceSectionTopSpacing
                )
            }
        } else if showsAllWorkspaces && sidebarPresentation == .collapsed {
            ForEach(Array(dockWorkspaceGroups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider()
                        .padding(
                            .horizontal,
                            AtollMetric.Sidebar.workspaceDividerHorizontalInset
                        )
                        .frame(height: AtollMetric.Sidebar.workspaceDividerHeight)
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

    private var showsSpaceSwitcher: Bool {
        SpaceSwitcherVisibility.showsSwitcher(spaceCount: liveSpaces.count)
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
            dockLayout: dockLayout,
            dockMagnification: dockMagnification,
            focusedLinkID: $focusedLinkID
        ) {
            serviceContextMenu(for: link)
        }
    }

    private func dockRailTopPadding(viewportHeight: CGFloat) -> CGFloat {
        guard sidebarPresentation == .collapsed,
              appState.iconRailPosition == .center
        else { return 0 }

        return CGFloat(DockIconSizing.centeredTopPadding(
            viewportHeight: Double(viewportHeight),
            itemCount: dockLinks.count,
            baseSize: appState.iconRailBaseSize,
            bottomInset: 0,
            additionalContentHeight: Double(dockDividerCount)
                * Double(AtollMetric.Sidebar.workspaceDividerHeight)
        ))
    }

    /// The expanded vertical rail uses a small native bordered action.
    private var addServiceButton: some View {
        Button {
            appState.showAddService = true
        } label: {
            Label("Add service", systemImage: "plus")
                .font(.atollToolbarControl)
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
