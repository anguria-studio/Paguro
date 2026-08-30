import SwiftUI
import BlattaCore

/// One workspace in the workspace rail, drawn as a row or as an icon.
///
/// It follows `ServiceRowView`: the same row geometry, the same marks, the same
/// two presentations, so the two rails read as one shell. The workspace icon is
/// its emoji, which the collapsed rail sets on a quiet tile.
struct WorkspaceCellView: View {
    let space: Space
    let isSelected: Bool
    var sidebarPresentation: SidebarPresentation = .expanded
    var badgeCount: Int = 0
    var isMuted: Bool = false
    var glassStyle = GlassLabDefaults.style
    var glassIntensity = GlassIntensityScale.defaultValue
    var dockIconSize = BlattaMetric.Sidebar.collapsedIconSize
    var dockItemSize = BlattaMetric.Sidebar.dockItemSize
    var dockRowHeight = BlattaMetric.Sidebar.dockRowHeight
    var dockIconHorizontalOffset: CGFloat = 0
    var dockTooltipLeadingOffset: CGFloat = 0
    var isDockHovered = false
    var dockMagnificationActive = false
    var onDockHoverChange: (Bool) -> Void = { _ in }
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isDockItem: Bool {
        sidebarPresentation == .collapsed
    }

    private var presentsHover: Bool {
        isDockItem ? isDockHovered : isHovering
    }

    private var emoji: String? {
        WorkspaceEmoji.displayValue(space.emoji)
    }

    /// The collapsed rail shows icons alone, so a workspace with no emoji needs
    /// something to be. Every other rail keeps it as its name alone.
    private var showsFallbackIcon: Bool {
        RailBarPresentationPolicy.showsWorkspaceFallbackIcon(
            emoji: space.emoji,
            isIconOnlyWorkspaceRail: isDockItem
        )
    }

    var body: some View {
        Button(action: action) {
            content
                .opacity(isMuted ? 0.85 : 1)
                .background {
                    let mark = RowMark(
                        isSelected: isSelected,
                        isFocused: false,
                        isHovering: presentsHover
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
                    .opacity(isDockItem && dockMagnificationActive ? 0 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: isDockItem ? dockRowHeight : nil)
        .contentShape(Rectangle())
        .offset(x: isDockItem ? dockIconHorizontalOffset : 0)
        .animation(
            reduceMotion ? nil : .smooth(duration: BlattaMotion.dockMagnificationSeconds),
            value: dockIconSize
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: presentsHover)
        .onHover { hovering in
            isHovering = hovering
            if isDockItem {
                onDockHoverChange(hovering)
            }
        }
        .zIndex(isDockItem && presentsHover ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(SpaceHeader.label(
            spaceName: space.name,
            badgeCount: badgeCount,
            isMuted: isMuted
        ))
        .accessibilityHint("Open this workspace")
        .accessibilityAddTraits([.isButton, isSelected ? .isSelected : []])
    }

    @ViewBuilder
    private var content: some View {
        if isDockItem {
            dockContent
        } else {
            rowContent
        }
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            icon(size: BlattaMetric.Sidebar.expandedIconSize)

            Text(space.name)
                .font(isSelected ? .blattaSidebarLabelSelected : .blattaSidebarLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(nameColor)

            Spacer(minLength: 0)

            if isMuted {
                MutedNotificationGlyph(isCompact: false)
            }

            if badgeCount > 0 {
                BadgeCountView(count: badgeCount)
            }
        }
        .padding(.horizontal, 8)
        .frame(width: ServiceRowView.rowWidth, height: BlattaMetric.Sidebar.rowHeight)
    }

    private var dockContent: some View {
        icon(size: dockIconSize)
            .overlay(alignment: .topLeading) {
                if isMuted {
                    MutedNotificationGlyph()
                        .offset(x: -5, y: -5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if badgeCount > 0 {
                    BadgeCountView(count: badgeCount)
                        .scaleEffect(0.86)
                        .offset(x: 7, y: -6)
                }
            }
            .frame(width: dockItemSize, height: dockItemSize)
            .overlay(alignment: .leading) {
                RailTooltipView(
                    text: space.name,
                    glassStyle: glassStyle,
                    glassIntensity: glassIntensity
                )
                .offset(x: dockTooltipLeadingOffset)
                .opacity(presentsHover ? 1 : 0)
            }
    }

    /// The workspace emoji, or the folder that stands in for a workspace
    /// without one in the collapsed rail.
    ///
    /// The collapsed tile carries a quiet surface, which gives an icon-only
    /// cell a shape to be. The row does not: it follows the rest of the app,
    /// where a workspace emoji stands on its own. A row for a workspace with no
    /// emoji keeps the space and draws nothing in it, so the names below and
    /// above it stay in one column.
    @ViewBuilder
    private func icon(size: CGFloat) -> some View {
        let glyph = Group {
            if let emoji {
                Text(emoji)
                    .font(.system(size: size * 0.62))
                    .opacity(isMuted ? 0.5 : 1)
            } else if showsFallbackIcon {
                Image(systemName: "folder.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundStyle(BlattaColor.Text.tertiary)
            }
        }

        if isDockItem {
            RoundedRectangle(cornerRadius: BlattaRadius.icon, style: .continuous)
                .fill(BlattaColor.Fill.quietSurface)
                .frame(width: size, height: size)
                .overlay { glyph }
                .accessibilityHidden(true)
        } else {
            Color.clear
                .frame(width: size, height: size)
                .overlay { glyph }
                .accessibilityHidden(true)
        }
    }

    private var nameColor: Color {
        guard isSelected else { return BlattaColor.Text.primary }
        return SidebarSelectionContrastPolicy.usesHighContrastText(
            shellTransparency: glassIntensity
        )
            ? BlattaColor.Text.selectedOnGlass
            : BlattaColor.Fill.sidebarSelectedTint
    }

    private func fillStyle(for mark: RowMark) -> AnyShapeStyle {
        guard mark.fill == .hover, !isDockItem else { return mark.fillStyle }
        return AnyShapeStyle(BlattaColor.Fill.railRowHover)
    }
}
