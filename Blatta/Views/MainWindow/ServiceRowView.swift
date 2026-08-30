import BlattaCore
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
    /// The resting size the Dock item lays out at. The pointer changes what it
    /// draws through `dockTransform`, never this.
    var dockIconSize = BlattaMetric.Sidebar.collapsedIconSize
    var dockItemSize = BlattaMetric.Sidebar.dockItemSize
    var dockRowHeight = BlattaMetric.Sidebar.dockRowHeight
    var dockTransform = DockIconTransform()
    var dockTooltipLeadingOffset: CGFloat = 0
    var supplementaryWorkspaceName: String?
    /// Draws the tab as its icon alone. The top bar uses this when it groups
    /// its tabs under workspace names and the person asked for icons only.
    var hidesLabel: Bool = false
    var isDockHovered = false
    var onDockHoverChange: (Bool) -> Void = { _ in }
    /// Whether the keyboard is on this row. A ring appears only when keyboard
    /// focus differs from selection — see `RowMark`.
    var isFocused: Bool = false
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The expanded rail uses the MacCleanerNative source-list width.
    static let rowWidth = BlattaMetric.Sidebar.rowWidth
    /// Compact source-list row height.
    static let rowHeight = BlattaMetric.Sidebar.rowHeight
    /// Tab height in the horizontal bar.
    static let tabHeight: CGFloat = 32
    /// The gap between two tabs in the horizontal bar. The reorder drag adds it
    /// to a measured tab to get the pitch of that rail.
    static let tabSpacing: CGFloat = 8
    /// Roughly what a labelled tab measures. Used only as the drop-midpoint
    /// fallback before the first geometry pass records a real width.
    static let tabTypicalWidth: CGFloat = 120

    private static let cornerRadius = BlattaMetric.Sidebar.rowRadius
    private static let iconCornerRadius = BlattaRadius.icon
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
                    // The tab bar and the sidebar stand on the same material,
                    // so a selected cell adapts the same way in both.
                    let adaptiveProgress = mark.fill == .selected
                        ? GlassIntensityScale.adaptiveSelectionProgress(glassIntensity)
                        : 0

                    ZStack {
                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .fill(fillStyle(for: mark))
                            .opacity(1 - adaptiveProgress)

                        if mark.fill == .selected {
                            RoundedRectangle(cornerRadius: Self.cornerRadius)
                                .fill(BlattaColor.Fill.sidebarAdaptiveSelection)
                                .opacity(adaptiveProgress)
                        }

                        RoundedRectangle(cornerRadius: Self.cornerRadius)
                            .strokeBorder(
                                mark.ring ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.clear),
                                lineWidth: 2
                            )
                    }
                    // The fill sits behind a resting tile. A magnified icon
                    // has left it, in size and in place, so it goes with the
                    // effect and comes back with it: both changes belong to
                    // the same animation, which is why this reads the
                    // transform rather than the hover that started it.
                    .opacity(isDockItem && !dockTransform.isResting ? 0 : 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The row keeps its exact resting height: the pointer is converted to
        // a position in the stack through that height, so a row of any other
        // height puts every icon somewhere the pointer does not agree with.
        .frame(height: isDockItem ? dockRowHeight : nil)
        // The Dock tile stays square while its target fills the rail, so the
        // sides of the rail belong to the icon in them rather than to nothing.
        .frame(maxWidth: isDockItem ? .infinity : nil)
        // Declared before the move below. A shape declared after it is placed
        // against the frame the cell lays out in, which the move does not
        // change: the icon would travel and its target would stay behind.
        .contentShape(Rectangle())
        // The move is drawn and nothing else. `offset` would move the target
        // with it, and rows moved by different amounts leave a band between
        // them that belongs to no row, where a click does nothing. The target
        // stays in the resting stack, which is the same stack the pointer is
        // measured in, so the row under the pointer is the row drawn there.
        .visualEffect { [offset = isDockItem ? dockTransform.verticalOffset : 0] content, _ in
            content.offset(y: offset)
        }
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
                isEnabled: !isDockItem && !hidesLabel
            )
        )
        .zIndex((isDockItem || hidesLabel) && presentsHover ? 10 : 0)
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
        } else if hidesLabel {
            iconOnlyContent
        } else {
            labelledContent
        }
    }

    /// The icons-only tab. It carries the same marks as the collapsed Dock
    /// item, on the icon rather than beside it, so a tab stays square. The name
    /// remains in the tooltip and in the accessibility text.
    private var iconOnlyContent: some View {
        serviceIcon(size: BlattaMetric.Sidebar.barIconOnlySize)
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
            .frame(width: Self.tabHeight, height: Self.tabHeight)
            // The bar draws the tooltip, not the tab: a tooltip drawn here
            // would be cut off by the scrolling strip that holds the tabs when
            // they do not fit.
            .anchorPreference(key: RailTabTooltipKey.self, value: .bounds) { anchor in
                presentsHover
                    ? RailTabTooltip(text: contextualName, anchor: anchor)
                    : nil
            }
    }

    private var labelledContent: some View {
        HStack(spacing: Self.gutter) {
            serviceIcon(
                size: axis == .vertical
                    ? BlattaMetric.Sidebar.expandedIconSize
                    : BlattaMetric.Sidebar.barIconSize
            )

            Text(instance.label)
                .font(isSelected ? .blattaSidebarLabelSelected : .blattaSidebarLabel)
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

    /// Each rail hovers against its own ground, so each takes its own fill.
    /// The Dock item keeps the shared one: it hovers over service artwork.
    private func fillStyle(for mark: RowMark) -> AnyShapeStyle {
        guard mark.fill == .hover, !isDockItem else { return mark.fillStyle }
        return AnyShapeStyle(
            axis == .vertical
                ? BlattaColor.Fill.railRowHover
                : BlattaColor.Fill.barTabHover
        )
    }

    private var serviceNameColor: Color {
        guard isSelected else { return BlattaColor.Text.primary }
        return SidebarSelectionContrastPolicy.usesHighContrastText(
            shellTransparency: glassIntensity
        )
            ? BlattaColor.Text.selectedOnGlass
            : BlattaColor.Fill.sidebarSelectedTint
    }


    /// The collapsed sidebar keeps only the service icon and its live marks.
    /// The label remains available through the tooltip and accessibility text.
    ///
    /// The tile lays out at its resting size and the pointer scales it from
    /// there. A scale changes no frame, so the stack and the scroll view around
    /// it do not measure themselves again for every step of the pointer. The
    /// tooltip stays outside the scale: it is a label, not part of the icon.
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
            .scaleEffect(dockTransform.scale, anchor: .leading)
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
        RailTooltipView(
            text: contextualName,
            glassStyle: glassStyle,
            glassIntensity: glassIntensity
        )
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
                    .font(.blattaSidebarAccessory)
                    .foregroundStyle(BlattaColor.Text.tertiary)
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

/// The floating name of a cell that shows its icon alone. The collapsed dock
/// puts it beside the icon; the top bar puts it under the tab.
struct RailTooltipView: View {
    let text: String
    var glassStyle = GlassLabDefaults.style
    var glassIntensity = GlassIntensityScale.defaultValue

    var body: some View {
        Text(text)
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
                    cornerRadius: BlattaRadius.surface,
                    style: .continuous
                )
                .strokeBorder(BlattaColor.shellBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, y: 2)
            .fixedSize()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// The name and the frame of the hovered icons-only tab, sent up to the bar
/// that draws its tooltip.
struct RailTabTooltip {
    let text: String
    let anchor: Anchor<CGRect>
}

struct RailTabTooltipKey: PreferenceKey {
    static let defaultValue: RailTabTooltip? = nil

    static func reduce(value: inout RailTabTooltip?, nextValue: () -> RailTabTooltip?) {
        value = nextValue() ?? value
    }
}

private struct DockTooltipSurfaceModifier: ViewModifier {
    let glassStyle: ShellGlassStyle
    let glassIntensity: Double

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: BlattaRadius.surface, style: .continuous)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        switch glassStyle {
        case .off:
            content.background {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(
                        BlattaColor.Fill.shellMaterialTint(
                            intensity: glassIntensity
                        )
                    )
                }
            }
        case .clear:
            content.glassEffect(
                .clear.tint(
                    BlattaColor.Fill.glassTint(intensity: glassIntensity)
                ),
                in: shape
            )
        case .regular:
            content.glassEffect(
                .regular.tint(
                    BlattaColor.Fill.glassTint(intensity: glassIntensity)
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
