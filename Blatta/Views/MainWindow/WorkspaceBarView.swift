import SwiftUI
import SwiftData
import BlattaCore

/// The rail of workspaces, along the top, in the layout that puts the services
/// down the left.
///
/// One chip for each workspace, in the saved order, then the add control. The
/// chips keep their names: the bar has room for them, and a name is what makes
/// one workspace tell itself from another.
struct WorkspaceBarView: View {
    @Binding var selectedSpaceID: UUID?
    /// What the bar leaves clear at its leading end, for the window controls
    /// or for the collapse control that stands over a collapsed rail.
    let contentInset: CGFloat

    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(AppState.self) private var appState

    @State private var editingSpace: Space?
    @State private var confirmingDeleteSpace: Space?

    private var liveSpaces: [Space] {
        spaces.filter { $0.modelContext != nil }
    }

    var body: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: contentInset)
                .accessibilityHidden(true)

            chipStrip

            // This stretch draws nothing, so a click falls through to the
            // window-drag handle behind the row.
            Spacer(minLength: 12)

            WebContentActions(webViewState: appState.webViewState)
                .padding(.trailing, 10)
        }
        .railBarSurface()
        .sheet(item: $editingSpace) { space in
            SpaceEditorSheet(editingSpace: space, selectedSpaceID: $selectedSpaceID)
        }
        .deleteSpaceConfirmation(space: $confirmingDeleteSpace) { space in
            appState.deleteSpace(space.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces")
    }

    /// The strip hugs its chips when it can and scrolls only as a fallback,
    /// like the service bar.
    private var chipStrip: some View {
        ViewThatFits(in: .horizontal) {
            chipRow
            ScrollView(.horizontal, showsIndicators: false) {
                chipRow
            }
        }
    }

    private var chipRow: some View {
        HStack(spacing: ServiceRowView.tabSpacing) {
            ForEach(liveSpaces) { space in
                chip(for: space)
            }

            Button {
                appState.showAddSpace = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .frame(width: 36, height: ServiceRowView.tabHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add workspace")
            .accessibilityLabel("Add workspace")
        }
        .padding(.trailing, 8)
        .padding(.vertical, 2)
    }

    private func chip(for space: Space) -> some View {
        let isCurrent = space.id == selectedSpaceID
        let workspaceMuted = space.isMutedEffective
        // The current workspace has its services in the rail beside this bar,
        // each with a badge of its own. Every other workspace shows a total,
        // which is the only place its unread count appears.
        let badgeCount = WorkspaceNavigationPolicy.showsAggregateBadge(
            serviceRowsVisible: isCurrent
        ) && !workspaceMuted
            ? appState.badgeManager.aggregateCount(
                for: appState.servicesForSpace(space.id).map(\.id)
            )
            : 0

        return BarWorkspaceLabelView(
            workspaceName: space.name,
            emoji: space.emoji,
            isCurrent: isCurrent,
            isMuted: NotificationMutePresentation.showsMutedState(
                scopeMuted: workspaceMuted,
                manualGlobalMute: appState.doNotDisturb
            ),
            badgeCount: badgeCount,
            showsSelection: true,
            glassIntensity: appState.liquidGlassIntensity
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
}
