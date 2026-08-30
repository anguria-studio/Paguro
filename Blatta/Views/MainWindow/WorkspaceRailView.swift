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
    @State private var editingSpace: Space?
    @State private var confirmingDeleteSpace: Space?

    private var liveSpaces: [Space] {
        spaces.filter { $0.modelContext != nil }
    }

    private var isCollapsed: Bool {
        sidebarPresentation == .collapsed
    }

    var body: some View {
        rail
            .sheet(item: $editingSpace) { space in
                SpaceEditorSheet(editingSpace: space, selectedSpaceID: $selectedSpaceID)
            }
            .deleteSpaceConfirmation(space: $confirmingDeleteSpace) { space in
                appState.deleteSpace(space.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workspaces")
    }

    private var rail: some View {
        let dockLayout = dockMagnification.layout(
            linkIDs: liveSpaces.map(\.id),
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: appState.iconRailMagnificationEnabled,
            isCollapsed: isCollapsed
        )

        return VStack(spacing: 0) {
            Color.clear
                .frame(height: sidebarPresentation.contentTopInset)

            GeometryReader { geometry in
                ScrollView {
                    LazyVStack(spacing: isCollapsed ? 0 : 2) {
                        ForEach(liveSpaces) { space in
                            cell(for: space, dockLayout: dockLayout)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, dockTopPadding(viewportHeight: geometry.size.height))
                    .padding(.bottom, isCollapsed ? 0 : 8)
                    .offset(y: dockLayout.stackVerticalOffset)
                    .animation(
                        reduceMotion
                            ? nil
                            : .smooth(duration: BlattaMotion.dockMagnificationSeconds),
                        value: dockLayout.stackVerticalOffset
                    )
                }
                .scrollClipDisabled(isCollapsed)
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
            Button("Add Workspace…") {
                appState.showAddSpace = true
            }
        }
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
        dockLayout: DockMagnificationLayout
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
            dockIconSize: dockLayout.iconSize(for: space.id),
            dockItemSize: BlattaMetric.Sidebar.dockItemSize(
                displayedIconSize: Double(dockLayout.iconSize(for: space.id))
            ),
            dockRowHeight: BlattaMetric.Sidebar.dockRowHeight(
                displayedIconSize: Double(dockLayout.iconSize(for: space.id))
            ),
            dockIconHorizontalOffset: CGFloat(DockIconSizing.horizontalOffset(
                baseSize: appState.iconRailBaseSize,
                displayedIconSize: Double(dockLayout.iconSize(for: space.id))
            )),
            dockTooltipLeadingOffset: CGFloat(DockIconSizing.tooltipLeadingOffset(
                baseSize: appState.iconRailBaseSize,
                displayedIconSize: Double(dockLayout.iconSize(for: space.id)),
                railInset: Double(BlattaMetric.Sidebar.surfaceInset)
            )),
            isDockHovered: dockMagnification.hoveredLinkID == space.id,
            dockMagnificationActive: dockMagnification.hoveredLinkID != nil
                && appState.iconRailMagnificationEnabled,
            onDockHoverChange: { hovering in
                if hovering {
                    dockMagnification.beginHover(for: space.id)
                } else {
                    dockMagnification.endHover(for: space.id)
                }
            }
        ) {
            selectedSpaceID = space.id
        }
        .contextMenu {
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
