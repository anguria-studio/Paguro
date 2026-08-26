import SwiftUI
import SwiftData
import os
import AtollCore

/// One rail, in either axis, holding the current space as its header and that
/// space's services under it.
///
/// This is build step 5 of concept C, and it replaces two views rather than
/// bending either into shape: `ServiceSidebarView` drew the services in two
/// axes and `SpaceStripView` drew a second rail of spaces beside it. Dropping
/// the second rail is what the concept buys — 161 points of chrome back in the
/// vertical layout, a whole 34 point bar in the horizontal one — and it is why
/// `hybrid` and `topBars` collapsed into a single layout: with one rail there
/// are only two arrangements left, on the left or along the top.
///
/// Everything the audit rated severity 0 came across untouched: the reorder
/// maths (`ServiceReorder`), drag and drop, the arrow keys, the VoiceOver move
/// actions. The space half of that plumbing now lives in `SpacePaletteView`,
/// which the header opens.
struct UnifiedRailView: View {
    @Binding var selectedSpaceID: UUID?
    @Binding var selectedServiceID: UUID?
    var axis: Axis = .vertical
    var sidebarPresentation: SidebarPresentation = .expanded
    /// Leading inset for the horizontal bar. It keeps the space header clear of
    /// the window traffic lights.
    var contentInset: CGFloat = 0

    @Query private var allLinks: [SpaceServiceLink]
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingPalette = false
    @State private var editingSpace: Space?
    @State private var confirmingDeleteSpace: Space?
    @State private var confirmingDelete: SpaceServiceLink?
    @State private var editingService: ServiceInstance?
    @State private var hoveredDockLinkID: UUID?
    @State private var dockHoverExitTask: Task<Void, Never>?
    /// Empty means every workspace starts expanded. Keeping only collapsed IDs
    /// also makes a newly created workspace appear without another state sync.
    @State private var collapsedWorkspaceIDs: Set<UUID> = []
    /// The link whose service is being moved into a brand-new space: set when the
    /// user picks "New Space…", it presents the space editor and, on create,
    /// moves the service into the freshly made space.
    @State private var movingToNewSpace: SpaceServiceLink?
    /// The service cell that currently holds keyboard focus. Two-way bound to
    /// each cell's `.focused`, so a click or Tab that focuses a cell records it
    /// here and the arrow keys move relative to it.
    @FocusState private var focusedLinkID: UUID?
    // Fallback drop midpoints, used only until the first geometry pass records a
    // cell's real size. They are half of what `ServiceRowView` draws: the active
    // sidebar row height and a labelled tab of roughly 120 points. A wrong (too
    // large) value would make every drop on that
    // axis resolve `.before` and leave the last slot unreachable.
    private static let serviceDropMidpointHorizontal: CGFloat = ServiceRowView.tabTypicalWidth / 2
    /// Measured size of each drop cell, so the before/after split uses the target's
    /// true midpoint instead of a hardcoded guess.
    @State private var cellSizes: [UUID: CGSize] = [:]

    /// The horizontal bar: a 32 point header and 32 point tabs with 5 points
    /// clear above and below. The drawn frame says 42.
    static let barHeight: CGFloat = 42

    private var liveSpaces: [Space] {
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
            horizontalBody
        }
    }

    /// A compact source list in expanded form and an icon dock when collapsed.
    private var verticalBody: some View {
        VStack(spacing: 0) {
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
                        verticalRailContent
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, dockRailTopPadding(viewportHeight: geometry.size.height))
                    .padding(.bottom, sidebarPresentation == .expanded ? 8 : 0)
                    .offset(y: dockStackVerticalOffset)
                    .animation(
                        reduceMotion
                            ? nil
                            : .smooth(duration: AtollMotion.dockMagnificationSeconds),
                        value: dockStackVerticalOffset
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
                clearDockHover()
            }
        }
        .onChange(of: appState.iconRailMagnificationEnabled) { _, enabled in
            if !enabled {
                clearDockHover()
            }
        }
        .onChange(of: appState.workspaceViewMode) { _, _ in
            clearDockHover()
        }
        .onChange(of: selectedSpaceID) { _, workspaceID in
            guard showsAllWorkspaces,
                  sidebarPresentation == .expanded,
                  let workspaceID
            else { return }
            collapsedWorkspaceIDs.remove(workspaceID)
        }
        .onDisappear {
            clearDockHover()
        }
        .contextMenu {
            railCreationMenu
        }
    }

    @ViewBuilder
    private var verticalRailContent: some View {
        if showsAllWorkspaces && sidebarPresentation == .expanded {
            ForEach(Array(workspaceGroups.enumerated()), id: \.element.id) { index, group in
                workspaceSection(
                    group,
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
                    serviceRow(for: link)
                }
            }
        } else {
            ForEach(filteredLinks) { link in
                serviceRow(for: link)
            }
        }
    }

    @ViewBuilder
    private func workspaceSection(
        _ group: WorkspaceLinkGroup,
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
                serviceRow(for: link)
            }
        }
    }

    private var horizontalBody: some View {
        HStack(spacing: 8) {
            if showsSpaceSwitcher {
                spaceHeader
                    // 72 points of traffic light, then 8, puts the header at x 80.
                    .padding(.leading, 8 + contentInset)

                Divider().frame(width: 1, height: 20)
            } else {
                // The workspace control is gone, but service tabs must still
                // start after the traffic lights.
                Color.clear
                    .frame(width: contentInset)
                    .accessibilityHidden(true)
            }

            tabStrip

            // Empty stretch between the tabs and the service controls. It draws
            // nothing and takes no hit of its own, so a click here falls through
            // to the window-drag handle behind the row.
            Spacer(minLength: 40)

            // Service controls live at the far right of the bar.
            WebContentActions(webViewState: appState.webViewState)
                .padding(.trailing, 10)
        }
        .frame(height: Self.barHeight)
        // The OS window drag is off in the bar layout, so tab drags reorder
        // instead of moving the window (see WindowChromeConfigurator). A
        // full-width drag handle behind the row restores "click any empty part
        // of the bar to move the window": the header, tabs and service controls sit
        // in front and take their own clicks, and every empty area falls through
        // to here.
        .background(WindowDragHandle())
        .atollMaterialBackground(.regularMaterial)
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

    /// The tab strip hugs its content when the tabs fit — leaving the rest of the
    /// bar as draggable empty space — and scrolls only when there are too many to
    /// fit. `ViewThatFits` picks the plain (hugging) row first and falls back to
    /// the scrolling row, which is deterministic where measuring the content
    /// width and capping the scroll view was not.
    private var tabStrip: some View {
        ViewThatFits(in: .horizontal) {
            tabRow
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow
                }
                // Keep the active service visible when it's selected off-screen
                // (⌘1–9, quick switcher, or a routed link).
                .onChange(of: selectedServiceID) { _, newID in
                    guard let newID else { return }
                    if reduceMotion {
                        proxy.scrollTo(newID, anchor: .center)
                    } else {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(newID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    /// The row of service tabs plus the add button. A plain `HStack` (not lazy)
    /// so `ViewThatFits` can measure its width to decide whether the tabs fit.
    /// The traffic-light inset is spent by the header now, so this starts flush.
    private var tabRow: some View {
        HStack(spacing: 4) {
            ForEach(filteredLinks) { link in
                serviceRow(for: link)
                    .id(link.service.id)
            }
            addServiceButton
        }
        .padding(.trailing, 8)
        .padding(.vertical, 2)
    }

    // MARK: - Service cells

    @ViewBuilder
    private func serviceRow(for link: SpaceServiceLink) -> some View {
        let isSel = selectedServiceID == link.service.id
            && selectedSpaceID == link.space.id
        let badge = appState.badgeManager.badgeCount(for: link.service.id)
        let hibernated = !isSel && appState.webViewPool.isHibernated(link.service.id)
        let muted = NotificationMutePresentation.showsMutedState(
            scopeMuted: link.service.isEffectivelyMuted,
            manualGlobalMute: appState.doNotDisturb
        )
        let media = appState.webViewPool.mediaCaptureStates[link.service.id]
        // A hibernated service has no page to be healthy or broken, and the moon
        // already says why it is not loaded — so it reports live and draws no dot.
        let health = hibernated ? ServiceHealth.live : appState.webViewPool.health(for: link.service.id)

        cell(
            for: link,
            isSelected: isSel,
            badge: badge,
            hibernated: hibernated,
            muted: muted,
            media: media,
            health: health,
            focused: focusedLinkID == link.id
        )
            .draggable(link.id.uuidString) {
                // Custom drag preview. Source-dimming is left to SwiftUI:
                // manually tracking a "dragging" id can't be cleared reliably —
                // a drop on itself or a cancelled drag never fires the drop
                // handler — which left the row stuck at 0.4 opacity.
                Text(link.service.label)
                    .font(.caption)
                    .padding(6)
                    .atollMaterialBackground(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: AtollRadius.control))
            }
            .dropDestination(for: String.self) { items, location in
                guard let droppedIDString = items.first,
                      let droppedID = UUID(uuidString: droppedIDString),
                      droppedID != link.id,
                      let droppedLink = liveLinks.first(where: { $0.id == droppedID }),
                      WorkspaceNavigationPolicy.allowsReorder(
                        sourceWorkspaceID: droppedLink.space.id,
                        targetWorkspaceID: link.space.id
                      )
                else { return false }
                let placement: ServiceReorderPlacement = {
                    let size = cellSizes[link.id]
                    if axis == .vertical {
                        let mid = (size?.height).map { $0 / 2 } ?? sidebarPresentation.serviceRowHeight / 2
                        return location.y < mid ? .before : .after
                    }
                    let mid = (size?.width).map { $0 / 2 } ?? Self.serviceDropMidpointHorizontal
                    return location.x < mid ? .before : .after
                }()
                return appState.reorderService(
                    droppedLinkID: droppedID,
                    relativeTo: link.id,
                    placement: placement
                )
            }
            .background(
                GeometryReader { proxy in
                    Color.clear.onChange(of: proxy.size, initial: true) {
                        cellSizes[link.id] = proxy.size
                    }
                }
            )
            .accessibilityAction(named: "Move up") { moveServiceUp(link) }
            .accessibilityAction(named: "Move down") { moveServiceDown(link) }
            .contextMenu { serviceContextMenu(for: link) }
            .focusable()
            .focused($focusedLinkID, equals: link.id)
            // The system's rectangular ring stays off, but the signal it used to
            // carry is now drawn by the row itself (`RowMark`): a fill for
            // selection, and a ring only when focus differs from selection.
            // 1.5.10 switched the system ring off because it stacked on the
            // app's own border and the 52 point strip clipped the result.
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
                handleServiceKey(press, for: link)
            }
            .onKeyPress(keys: [.return, .space]) { _ in
                selectService(link)
                return .handled
            }
    }

    @ViewBuilder
    private func cell(
        for link: SpaceServiceLink,
        isSelected: Bool,
        badge: Int,
        hibernated: Bool,
        muted: Bool,
        media: WebViewPool.MediaCaptureState?,
        health: ServiceHealth,
        focused: Bool
    ) -> some View {
        let displayedIconSize = dockIconSize(for: link.id)
        let baseIconSize = appState.iconRailBaseSize
        ServiceRowView(
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
            supplementaryWorkspaceName: duplicateServiceIDs.contains(link.service.id)
                ? link.space.name
                : nil,
            isDockHovered: hoveredDockLinkID == link.id,
            dockMagnificationActive: hoveredDockLinkID != nil
                && appState.iconRailMagnificationEnabled,
            onDockHoverChange: { hovering in
                if hovering {
                    beginDockHover(for: link.id)
                } else {
                    endDockHover(for: link.id)
                }
            },
            isFocused: focused
        ) {
            selectService(link)
        }
    }

    private func dockIconSize(for linkID: UUID) -> CGFloat {
        guard sidebarPresentation == .collapsed,
              let itemIndex = dockLinks.firstIndex(where: { $0.id == linkID })
        else {
            return CGFloat(DockIconSizing.baseSize(appState.iconRailBaseSize))
        }

        let hoveredIndex = hoveredDockLinkID.flatMap { hoveredID in
            dockLinks.firstIndex(where: { $0.id == hoveredID })
        }
        return CGFloat(DockIconSizing.displayedSize(
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: appState.iconRailMagnificationEnabled,
            itemIndex: itemIndex,
            hoveredIndex: hoveredIndex
        ))
    }

    private var dockStackVerticalOffset: CGFloat {
        guard sidebarPresentation == .collapsed else { return 0 }

        let hoveredIndex = hoveredDockLinkID.flatMap { hoveredID in
            dockLinks.firstIndex(where: { $0.id == hoveredID })
        }
        return CGFloat(DockIconSizing.stackVerticalOffset(
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: appState.iconRailMagnificationEnabled,
            itemCount: dockLinks.count,
            hoveredIndex: hoveredIndex
        ))
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

    /// A magnified row changes the pointer target while the pointer is still.
    /// Keep its hover state briefly so the new geometry can settle. Entry stays
    /// immediate, and entry on any icon cancels the pending exit.
    private func beginDockHover(for linkID: UUID) {
        dockHoverExitTask?.cancel()
        dockHoverExitTask = nil
        hoveredDockLinkID = linkID
    }

    private func endDockHover(for linkID: UUID) {
        guard hoveredDockLinkID == linkID else { return }

        dockHoverExitTask?.cancel()
        dockHoverExitTask = Task { @MainActor in
            do {
                try await Task.sleep(for: AtollMotion.dockHoverExitDelay)
            } catch {
                return
            }

            guard hoveredDockLinkID == linkID else { return }
            hoveredDockLinkID = nil
        }
    }

    private func clearDockHover() {
        dockHoverExitTask?.cancel()
        dockHoverExitTask = nil
        hoveredDockLinkID = nil
    }

    /// Selects a service and co-locates keyboard focus on its cell, so a click
    /// (or ⌘-digit) leaves the arrow keys with an anchor to move from — a plain
    /// Button click doesn't reliably promote the enclosing `.focusable()` to
    /// focused on its own.
    private func selectService(_ link: SpaceServiceLink) {
        selectedSpaceID = link.space.id
        selectedServiceID = link.service.id
        focusedLinkID = link.id
    }

    /// Arrow keys move the selection along the rail's axis (↑/↓ vertical,
    /// ←/→ horizontal); ⌥+arrow reorders the focused service, reusing the same
    /// move helpers that back the VoiceOver actions. Selection stops at the ends
    /// (no wrap). Cross-axis arrows are left unhandled so the scroll view keeps
    /// them.
    private func handleServiceKey(_ press: KeyPress, for link: SpaceServiceLink) -> KeyPress.Result {
        let forward: Bool
        switch (axis, press.key) {
        case (.vertical, .upArrow), (.horizontal, .leftArrow):
            forward = false
        case (.vertical, .downArrow), (.horizontal, .rightArrow):
            forward = true
        default:
            return .ignored
        }

        if press.modifiers.contains(.option) {
            if forward { moveServiceDown(link) } else { moveServiceUp(link) }
            // The service kept its id but changed slot — hold focus on it.
            focusedLinkID = link.id
            return .handled
        }

        let links = links(in: link.space.id)
        guard let index = links.firstIndex(where: { $0.id == link.id }) else { return .handled }
        let neighborIndex = forward ? index + 1 : index - 1
        guard links.indices.contains(neighborIndex) else { return .handled }
        let neighbor = links[neighborIndex]
        selectedSpaceID = neighbor.space.id
        selectedServiceID = neighbor.service.id
        focusedLinkID = neighbor.id
        return .handled
    }

    /// The vertical rail uses a small native bordered action. The horizontal bar
    /// has no width to spare, so it stays a plain plus.
    @ViewBuilder
    private var addServiceButton: some View {
        if axis == .vertical {
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
        } else {
            Button {
                appState.showAddService = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 36, height: ServiceRowView.tabHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add service")
            .accessibilityLabel("Add service")
            .disabled(selectedSpaceID == nil)
        }
    }

    @ViewBuilder
    private var railCreationMenu: some View {
        Button("Add Service...") {
            appState.showAddService = true
        }
        .disabled(selectedSpaceID == nil)

        Button("Add Workspace...") {
            appState.showAddSpace = true
        }
    }

    @ViewBuilder
    private func workspaceContextMenu(for space: Space) -> some View {
        Toggle("Mute Workspace", isOn: Binding(
            get: { space.isMutedEffective },
            set: { appState.setWorkspaceMuted($0, for: space.id) }
        ))

        Divider()

        Button("Add Service…") {
            selectedSpaceID = space.id
            appState.showAddService = true
        }

        Button("Edit Workspace…") {
            editingSpace = space
        }

        if liveSpaces.count > 1 {
            Divider()
            Button("Delete Workspace", role: .destructive) {
                confirmingDeleteSpace = space
            }
        }
    }

    @ViewBuilder
    private func serviceContextMenu(for link: SpaceServiceLink) -> some View {
        Button("Edit Service…") {
            editingService = link.service
        }

        Toggle("Mute Notifications", isOn: Binding(
            get: { link.service.isMuted },
            set: { newValue in
                appState.setServiceMuted(newValue, for: link.service.id)
            }
        ))

        if let media = appState.webViewPool.mediaCaptureStates[link.service.id],
           media.micActive || media.micMuted {
            Button(media.micMuted ? "Unmute Microphone" : "Mute Microphone") {
                appState.webViewPool.setMicrophoneMuted(
                    !media.micMuted,
                    for: link.service.id
                )
            }
        }

        Divider()

        Button("Open in Safari") {
            openInDefaultBrowser(link.service)
        }

        Divider()

        if appState.webViewPool.hasWebView(for: link.service.id) {
            Button("Hibernate") {
                appState.webViewPool.hibernate(link.service.id)
                if selectedServiceID == link.service.id {
                    selectedServiceID = nil
                }
            }
        }

        Divider()
        Button("Change Icon...") {
            appState.pickCustomIcon(for: link.service.id)
        }
        if link.service.customIconData != nil {
            Button("Reset Icon") {
                appState.resetIcon(for: link.service.id)
            }
        }
        Divider()
        Menu("Move to Space") {
            let targets = eligibleSpaces(for: link.service)
            ForEach(targets) { space in
                Button {
                    appState.moveService(
                        linkID: link.id,
                        to: space.id,
                        followToSpace: false
                    )
                } label: {
                    Text("\(space.emoji)  \(space.name)")
                }
                .accessibilityLabel(space.name)
            }
            if !targets.isEmpty {
                Divider()
            }
            Button("New Space…") {
                movingToNewSpace = link
            }
        }
        Button("Remove from this space") {
            removeFromSpace(link: link)
        }
        Divider()
        Button("Delete service entirely", role: .destructive) {
            confirmingDelete = link
        }
    }

    /// Opens the service's current page in the system default browser,
    /// preferring the live WKWebView's URL over the catalog/home URL so
    /// the user lands where they actually were.
    private func openInDefaultBrowser(_ service: ServiceInstance) {
        let liveURL = appState.webViewPool.liveWebView(for: service.id)?.url
        let target = liveURL ?? URL(string: service.url)
        if let target {
            WebViewCoordinator.openExternally(target)
        }
    }

    /// Spaces the service can be moved into: every space except the ones it's
    /// already in. Membership is read from the reliable `allLinks` query, not the
    /// service's inverse `spaceLinks` relationship, which can be stale.
    private func eligibleSpaces(for service: ServiceInstance) -> [Space] {
        let memberIDs = Set(
            allLinks
                .filter { $0.modelContext != nil && $0.service.modelContext != nil && $0.space.modelContext != nil && $0.service.id == service.id }
                .map { $0.space.id }
        )
        let eligible = Set(SpaceMove.eligibleSpaceIDs(allSpaceIDs: spaces.map(\.id), memberSpaceIDs: memberIDs))
        return spaces.filter { eligible.contains($0.id) }
    }

    /// The view only fixes up selection. `AppState.removeLink` owns the
    /// decision to delete the service, the save, and the teardown order.
    private func removeFromSpace(link: SpaceServiceLink) {
        if selectedServiceID == link.service.id && selectedSpaceID == link.space.id {
            selectedServiceID = nil
        }
        appState.removeLink(link.id)
    }

    private func moveServiceUp(_ link: SpaceServiceLink) {
        let links = links(in: link.space.id)
        guard let index = links.firstIndex(where: { $0.id == link.id }), index > 0 else { return }
        appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: links[index - 1].id,
            placement: .before
        )
    }

    private func moveServiceDown(_ link: SpaceServiceLink) {
        let links = links(in: link.space.id)
        guard let index = links.firstIndex(where: { $0.id == link.id }), index < links.count - 1 else { return }
        appState.reorderService(
            droppedLinkID: link.id,
            relativeTo: links[index + 1].id,
            placement: .after
        )
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
