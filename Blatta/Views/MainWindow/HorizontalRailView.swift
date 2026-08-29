import SwiftUI
import BlattaCore

/// Renders the top-bar rail while its parent owns queries and modal state.
struct HorizontalRailView<SpaceHeader: View, ServiceCell: View>: View {
    let links: [SpaceServiceLink]
    let selectedSpaceID: UUID?
    let selectedServiceID: UUID?
    let showsSpaceSwitcher: Bool
    let contentInset: CGFloat
    let dockMagnification: DockMagnificationState

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spaceHeaderContent: () -> SpaceHeader
    private let serviceCell: (SpaceServiceLink, DockMagnificationLayout) -> ServiceCell

    init(
        links: [SpaceServiceLink],
        selectedSpaceID: UUID?,
        selectedServiceID: UUID?,
        showsSpaceSwitcher: Bool,
        contentInset: CGFloat,
        dockMagnification: DockMagnificationState,
        @ViewBuilder spaceHeader: @escaping () -> SpaceHeader,
        @ViewBuilder serviceCell: @escaping (
            SpaceServiceLink,
            DockMagnificationLayout
        ) -> ServiceCell
    ) {
        self.links = links
        self.selectedSpaceID = selectedSpaceID
        self.selectedServiceID = selectedServiceID
        self.showsSpaceSwitcher = showsSpaceSwitcher
        self.contentInset = contentInset
        self.dockMagnification = dockMagnification
        self.spaceHeaderContent = spaceHeader
        self.serviceCell = serviceCell
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsSpaceSwitcher {
                spaceHeaderContent()
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

            // This stretch draws nothing, so a click falls through to the
            // window-drag handle behind the row.
            Spacer(minLength: 40)

            WebContentActions(webViewState: appState.webViewState)
                .padding(.trailing, 10)
        }
        .frame(height: 42)
        // Window dragging is disabled for this layout so tab drags can reorder.
        // This handle restores dragging from every empty part of the bar.
        .background(WindowDragHandle())
        .blattaMaterialBackground(.regularMaterial)
    }

    /// The strip hugs its content when possible and scrolls only as a fallback.
    private var tabStrip: some View {
        ViewThatFits(in: .horizontal) {
            tabRow
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    tabRow
                }
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

    /// A plain stack lets `ViewThatFits` measure the complete tab row.
    private var tabRow: some View {
        let dockLayout = dockMagnification.layout(
            linkIDs: links.map(\.id),
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: false,
            isCollapsed: false
        )

        return HStack(spacing: 4) {
            ForEach(links) { link in
                serviceCell(link, dockLayout)
                    .id(link.service.id)
            }

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
        .padding(.trailing, 8)
        .padding(.vertical, 2)
    }
}
