import SwiftUI
import BlattaCore

/// One run of tabs in the top bar, and the workspace it belongs to.
///
/// A `nil` space is the current-workspace bar, which draws its tabs with no
/// name above them. A named space is one group of the all-workspaces bar.
struct RailBarGroup: Identifiable {
    let space: Space?
    let links: [SpaceServiceLink]

    /// The identity of the single unnamed group. It is fixed, so the one group
    /// of the current-workspace bar keeps its identity across a space switch.
    private static let currentWorkspaceID = UUID()

    var id: UUID { space?.id ?? Self.currentWorkspaceID }
}

/// The band a top rail draws itself in.
///
/// Both top rails take it: the service bar and the workspace bar. It is as tall
/// as the content header of the sidebar layout, so the window keeps one top
/// edge whichever layout draws it. Window dragging is off in these layouts so a
/// cell drag can reorder, and the handle gives it back from every empty part of
/// the band.
struct RailBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(height: BlattaMetric.Toolbar.height)
            .background(WindowDragHandle())
            .blattaMaterialBackground(.regularMaterial)
    }
}

extension View {
    func railBarSurface() -> some View {
        modifier(RailBarSurface())
    }
}

/// Renders the top-bar rail while its parent owns queries and modal state.
struct HorizontalRailView<SpaceHeader: View, WorkspaceLabel: View, ServiceCell: View>: View {
    let groups: [RailBarGroup]
    let selectedSpaceID: UUID?
    let selectedServiceID: UUID?
    let showsSpaceSwitcher: Bool
    let contentInset: CGFloat
    let dockMagnification: DockMagnificationState

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let spaceHeaderContent: () -> SpaceHeader
    private let workspaceLabel: (Space) -> WorkspaceLabel
    private let serviceCell: (
        SpaceServiceLink,
        [SpaceServiceLink],
        DockMagnificationLayout
    ) -> ServiceCell

    init(
        groups: [RailBarGroup],
        selectedSpaceID: UUID?,
        selectedServiceID: UUID?,
        showsSpaceSwitcher: Bool,
        contentInset: CGFloat,
        dockMagnification: DockMagnificationState,
        @ViewBuilder spaceHeader: @escaping () -> SpaceHeader,
        @ViewBuilder workspaceLabel: @escaping (Space) -> WorkspaceLabel,
        @ViewBuilder serviceCell: @escaping (
            SpaceServiceLink,
            [SpaceServiceLink],
            DockMagnificationLayout
        ) -> ServiceCell
    ) {
        self.groups = groups
        self.selectedSpaceID = selectedSpaceID
        self.selectedServiceID = selectedServiceID
        self.showsSpaceSwitcher = showsSpaceSwitcher
        self.contentInset = contentInset
        self.dockMagnification = dockMagnification
        self.spaceHeaderContent = spaceHeader
        self.workspaceLabel = workspaceLabel
        self.serviceCell = serviceCell
    }

    private var allLinks: [SpaceServiceLink] {
        groups.flatMap(\.links)
    }

    var body: some View {
        HStack(spacing: 8) {
            // 72 points of traffic light, then 8, puts what follows at x 80.
            // Beside a rail, it clears what the rail does not cover instead.
            Color.clear
                .frame(width: contentInset)
                .accessibilityHidden(true)

            if showsSpaceSwitcher {
                spaceHeaderContent()

                Divider().frame(width: 1, height: 20)
            }

            tabStrip

            // This stretch draws nothing, so a click falls through to the
            // window-drag handle behind the row. Its minimum is the window
            // drag area that stays when the tabs fill the bar.
            Spacer(minLength: 12)

            WebContentActions(webViewState: appState.webViewState)
                .padding(.trailing, 10)
        }
        .railBarSurface()
        .overlayPreferenceValue(RailTabTooltipKey.self) { tooltip in
            tabTooltip(tooltip)
        }
    }

    /// The name of the hovered icons-only tab, under that tab.
    ///
    /// The tooltip hangs below the bar, so it is drawn here rather than by the
    /// tab: the strip that holds the tabs cuts off everything outside it once
    /// the tabs stop fitting.
    @ViewBuilder
    private func tabTooltip(_ tooltip: RailTabTooltip?) -> some View {
        GeometryReader { proxy in
            if let tooltip {
                let frame = proxy[tooltip.anchor]

                // A point under the middle of the tab, carrying the tooltip
                // as its overlay. The overlay has to be attached before the
                // point moves: `position` fills the container it is given, so
                // an overlay added after it would align to the whole bar
                // instead of to the point.
                //
                // The point sits below the bar rather than below the tab, so
                // the gap under the bar stays the same whatever the bar holds.
                Color.clear
                    .frame(width: 1, height: 1)
                    .overlay(alignment: .top) {
                        RailTooltipView(
                            text: tooltip.text,
                            glassStyle: appState.liquidGlassStyle,
                            glassIntensity: appState.liquidGlassIntensity
                        )
                    }
                    .position(x: frame.midX, y: proxy.size.height + 6)
            }
        }
        .allowsHitTesting(false)
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
        let links = allLinks
        let dockLayout = dockMagnification.layout(
            linkIDs: links.map(\.id),
            baseSize: appState.iconRailBaseSize,
            magnifiedSize: appState.iconRailMagnifiedSize,
            magnificationEnabled: false,
            isCollapsed: false
        )

        return HStack(spacing: ServiceRowView.tabSpacing) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if let space = group.space {
                    if index > 0 {
                        Divider()
                            .frame(width: 1, height: 18)
                            .padding(.horizontal, 2)
                            .accessibilityHidden(true)
                    }

                    workspaceLabel(space)
                }

                ForEach(group.links) { link in
                    serviceCell(link, group.links, dockLayout)
                        .id(link.service.id)
                }
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
        // The reorder drag measures inside the tab row, in both the plain row
        // and the scrolling fallback that `ViewThatFits` can choose.
        .coordinateSpace(.named(RailCoordinateSpace.name))
    }
}
