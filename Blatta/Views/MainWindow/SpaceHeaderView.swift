import SwiftUI
import BlattaCore

/// The spoken label for the space header. Split out from the view so the words
/// can be pinned by a test, the same way `ServiceAccessibility` is.
enum SpaceHeader {
    static func label(spaceName: String?, badgeCount: Int, isMuted: Bool) -> String {
        guard let spaceName, !spaceName.isEmpty else { return "No workspace" }
        var parts = [spaceName]
        if badgeCount > 0 {
            parts.append(badgeCount == 1 ? "1 unread" : "\(badgeCount) unread")
        }
        if isMuted { parts.append("muted") }
        return parts.joined(separator: ", ")
    }
}

/// Accessibility text for one accordion section in the all-workspaces view.
enum WorkspaceSectionHeader {
    static func label(
        workspaceName: String,
        badgeCount: Int,
        isMuted: Bool,
        isExpanded: Bool
    ) -> String {
        var parts = [workspaceName]
        if badgeCount > 0 {
            parts.append(badgeCount == 1 ? "1 unread" : "\(badgeCount) unread")
        }
        if isMuted { parts.append("muted") }
        parts.append(isExpanded ? "expanded" : "collapsed")
        return parts.joined(separator: ", ")
    }
}

/// The current space, drawn as a header on the service rail, and the click
/// target that opens the switcher.
///
/// The current space is a named row instead of an unlabelled emoji. The other
/// spaces are available in `SpacePaletteView` rather than always on screen.
///
/// The vertical header uses the same width and inset as each service row. The
/// horizontal header takes the width of its own name, up to 150 points, so a
/// short workspace name leaves its space to the tabs. The rail places the
/// header clear of the traffic lights.
struct SpaceHeaderView: View {
    let spaceName: String?
    let emoji: String
    var axis: Axis = .vertical
    var badgeCount: Int = 0
    var isMuted: Bool = false
    /// True while the palette this header opens is on screen. Held by the owner
    /// so the header can draw itself as pressed for as long as it is.
    var isPaletteOpen: Bool = false
    let action: () -> Void

    @State private var isHovering = false

    /// Matches the rail and row widths in `ServiceRowView`, so the header and
    /// the services below it line up on both edges.
    static let headerWidth = BlattaMetric.Sidebar.rowWidth
    static let headerHeight = BlattaMetric.Sidebar.headerHeight
    /// The most the horizontal bar's header takes. A longer workspace name
    /// truncates here rather than push the service tabs across the bar.
    static let barHeaderMaximumWidth: CGFloat = 150
    static let barHeaderHeight: CGFloat = 32

    private static let cornerRadius = BlattaMetric.Sidebar.rowRadius
    private static let gutter: CGFloat = 8

    var body: some View {
        Button(action: action) {
            content
                .background {
                    RoundedRectangle(cornerRadius: Self.cornerRadius)
                        .fill(fillStyle)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(displayName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpaceHeader.label(
            spaceName: spaceName,
            badgeCount: badgeCount,
            isMuted: isMuted
        ))
        .accessibilityHint("Switch workspace")
        .accessibilityAddTraits(.isButton)
    }

    private var content: some View {
        HStack(spacing: Self.gutter) {
            if let emoji = WorkspaceEmoji.displayValue(emoji) {
                Text(emoji)
                    .font(.system(size: axis == .vertical ? 11 : 15))
                    .opacity(isMuted ? 0.5 : 1.0)
                    .accessibilityHidden(true)
            }

            Text(displayName)
                .font(axis == .vertical ? .blattaSidebarSection : .blattaSidebarLabelSelected)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(
                    axis == .vertical
                        ? BlattaColor.Text.tertiary
                        : (spaceName == nil ? BlattaColor.Text.secondary : BlattaColor.Text.primary)
                )

            Spacer(minLength: 0)

            if badgeCount > 0 {
                BadgeCountView(count: badgeCount)
            }

            if isMuted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            // Says the header does something. `chevron.up.chevron.down` is what
            // AppKit puts on a pop-up button, which is what this behaves like.
            Image(systemName: axis == .vertical ? "chevron.down" : "chevron.up.chevron.down")
                .font(.system(size: axis == .vertical ? 8 : BlattaTypeSize.sidebarAccessory, weight: .medium))
                .foregroundStyle(BlattaColor.Text.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, axis == .vertical ? 4 : Self.gutter)
        .frame(
            width: axis == .vertical ? Self.headerWidth : nil,
            height: axis == .vertical ? Self.headerHeight : Self.barHeaderHeight
        )
        // The bar gives the header the width of its own parts. This cap keeps
        // a long workspace name from pushing the service tabs across the bar;
        // the name truncates instead.
        .frame(maxWidth: axis == .vertical ? nil : Self.barHeaderMaximumWidth)
    }

    private var displayName: String {
        guard let spaceName, !spaceName.isEmpty else { return "No workspace" }
        return spaceName
    }

    /// No selected-state fill: the header is not one of a set you pick from, it
    /// is the one thing that is always true. It fills while the palette it owns
    /// is open, which is the pop-up button behaviour it borrows.
    private var fillStyle: AnyShapeStyle {
        if isPaletteOpen {
            return AnyShapeStyle(BlattaColor.Fill.control)
        } else if isHovering {
            return AnyShapeStyle(BlattaColor.Fill.rowHover)
        }
        return AnyShapeStyle(Color.clear)
    }
}

/// One workspace disclosure row in the expanded all-workspaces sidebar.
struct WorkspaceSectionHeaderView: View {
    let workspaceName: String
    let emoji: String
    let badgeCount: Int
    let isMuted: Bool
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(BlattaColor.Text.tertiary)
                    // Match the service icon column below this header.
                    .frame(width: BlattaMetric.Sidebar.expandedIconSize)
                    .accessibilityHidden(true)

                if let emoji = WorkspaceEmoji.displayValue(emoji) {
                    Text(emoji)
                        .font(.system(size: 11))
                        .opacity(isMuted ? 0.5 : 1)
                        .accessibilityHidden(true)
                }

                Text(workspaceName)
                    .font(.blattaSidebarSection)
                    .foregroundStyle(BlattaColor.Text.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 0)

                if badgeCount > 0 {
                    BadgeCountView(count: badgeCount)
                }

                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, 8)
            .frame(
                width: BlattaMetric.Sidebar.rowWidth,
                height: BlattaMetric.Sidebar.headerHeight
            )
            .background {
                RoundedRectangle(cornerRadius: BlattaMetric.Sidebar.rowRadius)
                    .fill(isHovering ? BlattaColor.Fill.rowHover : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Collapse \(workspaceName)" : "Expand \(workspaceName)")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(WorkspaceSectionHeader.label(
            workspaceName: workspaceName,
            badgeCount: badgeCount,
            isMuted: isMuted,
            isExpanded: isExpanded
        ))
        .accessibilityHint(isExpanded ? "Collapse workspace" : "Expand workspace")
        .accessibilityAddTraits(.isButton)
    }
}

/// One workspace in a top bar, and the click target that opens it.
///
/// Two bars draw it. In the grouped service bar it is a label that marks where
/// a workspace's tabs start, and it keeps its name even while those tabs show
/// icons alone: the name is what tells the runs of tabs apart. In the workspace
/// bar it is a chip of its own, so there it also carries a selected fill and
/// the workspace's unread total.
struct BarWorkspaceLabelView: View {
    let workspaceName: String
    let emoji: String
    let isCurrent: Bool
    let isMuted: Bool
    var badgeCount: Int = 0
    /// True where the chip is the thing you pick, rather than a label above the
    /// things you pick.
    var showsSelection: Bool = false
    var glassIntensity = GlassIntensityScale.defaultValue
    let action: () -> Void

    @State private var isHovering = false

    private var isSelected: Bool {
        showsSelection && isCurrent
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let emoji = WorkspaceEmoji.displayValue(emoji) {
                    Text(emoji)
                        .font(.system(size: 13))
                        .opacity(isMuted ? 0.5 : 1)
                        .accessibilityHidden(true)
                }

                Text(workspaceName)
                    .font(isSelected ? .blattaSidebarLabelSelected : .blattaSidebarSection)
                    .foregroundStyle(nameColor)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }

                if badgeCount > 0 {
                    BadgeCountView(count: badgeCount)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: ServiceRowView.tabHeight)
            .background {
                let mark = RowMark(
                    isSelected: isSelected,
                    isFocused: false,
                    isHovering: isHovering
                )
                let adaptiveProgress = mark.fill == .selected
                    ? GlassIntensityScale.adaptiveSelectionProgress(glassIntensity)
                    : 0

                ZStack {
                    RoundedRectangle(cornerRadius: BlattaMetric.Sidebar.rowRadius)
                        .fill(fillStyle(for: mark))
                        .opacity(1 - adaptiveProgress)

                    if mark.fill == .selected {
                        RoundedRectangle(cornerRadius: BlattaMetric.Sidebar.rowRadius)
                            .fill(BlattaColor.Fill.sidebarAdaptiveSelection)
                            .opacity(adaptiveProgress)
                    }
                }
            }
            .contentShape(Rectangle())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(workspaceName)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpaceHeader.label(
            spaceName: workspaceName,
            badgeCount: badgeCount,
            isMuted: isMuted
        ))
        .accessibilityHint("Open this workspace")
        .accessibilityAddTraits([.isButton, isSelected ? .isSelected : []])
    }

    private var nameColor: Color {
        guard isSelected else {
            return isCurrent ? BlattaColor.Text.secondary : BlattaColor.Text.tertiary
        }
        return SidebarSelectionContrastPolicy.usesHighContrastText(
            shellTransparency: glassIntensity
        )
            ? BlattaColor.Text.selectedOnGlass
            : BlattaColor.Fill.sidebarSelectedTint
    }

    private func fillStyle(for mark: RowMark) -> AnyShapeStyle {
        guard mark.fill == .hover else { return mark.fillStyle }
        return AnyShapeStyle(BlattaColor.Fill.barTabHover)
    }
}
