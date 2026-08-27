import AtollCore
import SwiftUI

/// One service in the rail, drawn as a labelled row in either axis.
///
/// This replaces the two unlabelled cells the rail used to draw — an 18 point
/// icon tab in the horizontal bar and a 32 point icon in the 52 point vertical
/// rail — which the UX audit rated its severity 4 finding: two Slack workspaces
/// were two identical squares and the name lived only in a tooltip. Both axes
/// now carry the name.
///
/// The vertical row follows the source-list geometry in Renewals and
/// MacCleanerNative. The rail is 218 points wide. Each row has a 10 point side
/// inset and a height of 28 points. The horizontal tab keeps the same parts and
/// fits its label instead of taking a fixed width.
///
/// Icon resolution, the spoken label, the badge and the media glyph are all
/// shared with the rest of the app through `ServiceIconView.swift`.
enum ServiceRowLabel {
    static func contextualName(serviceName: String, workspaceName: String?) -> String {
        guard let workspaceName, !workspaceName.isEmpty else { return serviceName }
        return "\(serviceName) — \(workspaceName)"
    }
}

struct ServiceRowView: View {
    let instance: ServiceInstance
    let isSelected: Bool
    var axis: Axis = .vertical
    var sidebarPresentation: SidebarPresentation = .expanded
    var badgeCount: Int = 0
    var isHibernated: Bool = false
    var isMuted: Bool = false
    var cameraActive: Bool = false
    var micActive: Bool = false
    var micMuted: Bool = false
    var health: ServiceHealth = .live
    var glassStyle = GlassLabDefaults.style
    var glassIntensity = GlassIntensityScale.defaultValue
    var dockIconSize = AtollMetric.Sidebar.collapsedIconSize
    var dockItemSize = AtollMetric.Sidebar.dockItemSize
    var dockRowHeight = AtollMetric.Sidebar.dockRowHeight
    var dockIconHorizontalOffset: CGFloat = 0
    var dockTooltipLeadingOffset: CGFloat = 0
    var supplementaryWorkspaceName: String?
    var isDockHovered = false
    var dockMagnificationActive = false
    var onDockHoverChange: (Bool) -> Void = { _ in }
    /// Whether the keyboard is on this row. A ring appears only when keyboard
    /// focus differs from selection — see `RowMark`.
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The expanded rail uses the MacCleanerNative source-list width.
    static let rowWidth = AtollMetric.Sidebar.rowWidth
    /// Compact source-list row height.
    static let rowHeight = AtollMetric.Sidebar.rowHeight
    /// Tab height in the horizontal bar.
    static let tabHeight: CGFloat = 32
    /// Roughly what a labelled tab measures. Used only as the drop-midpoint
    /// fallback before the first geometry pass records a real width.
    static let tabTypicalWidth: CGFloat = 120

    private static let cornerRadius = AtollMetric.Sidebar.rowRadius
    private static let iconCornerRadius = AtollRadius.icon
    private static let gutter: CGFloat = 8

    private var isDockItem: Bool {
        axis == .vertical && sidebarPresentation == .collapsed
    }

    private var presentsHover: Bool {
        isDockItem ? isDockHovered : isHovering
    }

    private var contextualName: String {
        ServiceRowLabel.contextualName(
            serviceName: instance.label,
            workspaceName: supplementaryWorkspaceName
        )
    }

    var body: some View {
        Button(action: action) {
            content
                .opacity(isHibernated ? 0.6 : (isMuted ? 0.85 : 1.0))
                .background {
                    let mark = RowMark(
                        isSelected: isSelected,
                        isFocused: isFocused,
                        isHovering: presentsHover
                    )
                    let adaptiveProgress = axis == .vertical && mark.fill == .selected
                        ? GlassIntensityScale.adaptiveSelectionProgress(glassIntensity)
                        : 0

                    ZStack {
                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .fill(fillStyle(for: mark))
                            .opacity(1 - adaptiveProgress)

                        if mark.fill == .selected {
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .fill(AtollColor.Fill.sidebarAdaptiveSelection)
                                .opacity(adaptiveProgress)
                        }

                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .strokeBorder(
                                mark.ring ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                                lineWidth: 2
                            )
                    }
                    .opacity(isDockItem && dockMagnificationActive ? 0 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(height: isDockItem ? dockRowHeight : nil)
        // The visible Dock tile stays square, while its outer hover target
        // fills the row so adjacent targets meet without a dead area.
        .contentShape(Rectangle())
        .offset(x: isDockItem ? dockIconHorizontalOffset : 0)
        .animation(
            reduceMotion
                ? nil
                : .smooth(duration: AtollMotion.dockMagnificationSeconds),
            value: dockIconSize
        )
        .animation(
            reduceMotion ? nil : .easeOut(duration: 0.1),
            value: presentsHover
        )
        .onHover { hovering in
            isHovering = hovering
            if isDockItem {
                onDockHoverChange(hovering)
            }
        }
        .modifier(
            ServiceHelpModifier(
                label: contextualName,
                isEnabled: !isDockItem
            )
        )
        .zIndex(isDockItem && presentsHover ? 10 : 0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ServiceAccessibility.label(
            name: contextualName,
            badgeCount: badgeCount,
            isHibernated: isHibernated,
            isMuted: isMuted,
            cameraActive: cameraActive,
            micActive: micActive,
            micMuted: micMuted,
            health: health
        ))
        .accessibilityAddTraits([.isButton, isSelected ? .isSelected : []])
    }

    @ViewBuilder
    private var content: some View {
        if isDockItem {
            dockContent
        } else {
            labelledContent
        }
    }

    private var labelledContent: some View {
        HStack(spacing: Self.gutter) {
            serviceIcon(size: AtollMetric.Sidebar.expandedIconSize)

            Text(instance.label)
                .font(isSelected ? .atollSidebarLabelSelected : .atollSidebarLabel)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(serviceNameColor)

            if axis == .vertical {
                // Pushes the accessories to the trailing edge of the fixed-width
                // row. The horizontal tab has no fixed width to push against, so
                // it leaves this out and the accessories sit after the name.
                Spacer(minLength: 0)
            }

            accessories
        }
        .padding(.horizontal, Self.gutter)
        .frame(
            width: axis == .vertical ? Self.rowWidth : nil,
            height: axis == .vertical ? Self.rowHeight : Self.tabHeight
        )
        // The tab takes exactly the width its label needs and no more. Left
        // free to grow rather than capped: a cap only bites when something
        // proposes an unbounded width, which the horizontal scroll view does,
        // and there it would stretch every short tab to the cap instead of
        // trimming the long ones. `ViewThatFits` in the strip already hands
        // overflow to that scroll view, so a wide tab costs scrolling, not
        // layout.
        .fixedSize(horizontal: axis == .horizontal, vertical: false)
    }

    private var serviceNameColor: Color {
        guard isSelected else { return AtollColor.Text.primary }
        guard axis == .vertical else { return AtollColor.Fill.sidebarSelectedTint }
        return SidebarSelectionContrastPolicy.usesHighContrastText(
            shellTransparency: glassIntensity
        )
            ? AtollColor.Text.selectedOnGlass
            : AtollColor.Fill.sidebarSelectedTint
    }

    private func fillStyle(for mark: RowMark) -> AnyShapeStyle {
        if axis == .vertical,
           sidebarPresentation == .expanded,
           mark.fill == .hover {
            return AnyShapeStyle(AtollColor.Fill.sidebarRowHover)
        }
        return mark.fillStyle
    }

    /// The collapsed sidebar keeps only the service icon and its live marks.
    /// The label remains available through the tooltip and accessibility text.
    private var dockContent: some View {
        serviceIcon(size: dockIconSize)
            .overlay(alignment: .topLeading) {
                if isMuted {
                    MutedNotificationGlyph()
                        .offset(x: -5, y: -5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if badgeCount > 0 && instance.showBadge {
                    BadgeCountView(count: badgeCount)
                        .scaleEffect(0.86)
                        .offset(x: 7, y: -6)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if cameraActive || micActive || micMuted {
                    MediaIndicatorGlyph(
                        cameraActive: cameraActive,
                        micActive: micActive,
                        micMuted: micMuted
                    )
                    .offset(x: -5, y: 5)
                }
            }
            .frame(
                width: dockItemSize,
                height: dockItemSize
            )
            .overlay(alignment: .leading) {
                // Keep the native glass surface alive before hover. Creating it
                // on pointer entry exposes the first background sample as
                // a brief color change.
                dockTooltip
                    .offset(x: dockTooltipLeadingOffset)
                    .opacity(presentsHover ? 1 : 0)
            }
    }

    private var dockTooltip: some View {
        Text(contextualName)
            .font(.callout)
            .foregroundStyle(.primary)
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .modifier(
                DockTooltipSurfaceModifier(
                    glassStyle: glassStyle,
                    glassIntensity: glassIntensity
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: AtollRadius.surface,
                    style: .continuous
                )
                .strokeBorder(AtollColor.shellBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func serviceIcon(size: CGFloat) -> some View {
        ServiceIconSquare(
            instance: instance,
            size: size,
            cornerRadius: Self.iconCornerRadius
        )
        // Health belongs to the service page, so it stays on the icon in both
        // sidebar forms.
        .overlay(alignment: .bottomTrailing) {
            ServiceHealthDot(health: health)
                .offset(x: 3, y: 3)
        }
    }

    /// State that used to hang off the icon's corners, now inline where there is
    /// room for it. Ordered so the badge — the one thing that changes on its own
    /// while you are not looking — always lands last, on the trailing edge.
    private var accessories: some View {
        HStack(spacing: 4) {
            // Asked for by hand rather than let through unconditionally: the
            // glyph draws nothing when nothing is live, but an HStack still
            // spends a spacing slot on it and the row picks up 4 dead points.
            if cameraActive || micActive || micMuted {
                MediaIndicatorGlyph(cameraActive: cameraActive, micActive: micActive, micMuted: micMuted)
            }

            if isHibernated {
                Image(systemName: "moon.zzz.fill")
                    .font(.atollSidebarAccessory)
                    .foregroundStyle(AtollColor.Text.tertiary)
                    .accessibilityHidden(true)
            }

            if isMuted {
                MutedNotificationGlyph(isCompact: false)
            }

            if badgeCount > 0 && instance.showBadge {
                BadgeCountView(count: badgeCount)
            }
        }
    }

}

private struct DockTooltipSurfaceModifier: ViewModifier {
    let glassStyle: ShellGlassStyle
    let glassIntensity: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: AtollRadius.surface, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch glassStyle {
        case .off:
            content.background {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(
                        AtollColor.Fill.shellMaterialTint(
                            intensity: glassIntensity
                        )
                    )
                }
            }
        case .clear:
            content.glassEffect(
                .clear.tint(
                    AtollColor.Fill.glassTint(intensity: glassIntensity)
                ),
                in: shape
            )
        case .regular:
            content.glassEffect(
                .regular.tint(
                    AtollColor.Fill.glassTint(intensity: glassIntensity)
                ),
                in: shape
            )
        }
    }
}

private struct ServiceHelpModifier: ViewModifier {
    let label: String
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content.help(label)
        } else {
            content
        }
    }
}
