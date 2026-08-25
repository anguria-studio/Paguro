import AppKit
import SwiftUI

/// System font sizes for the main window.
///
/// Renewals and MacCleanerNative use the same compact type ramp. Atoll uses the
/// parts of that ramp that apply to a service workspace.
enum AtollTypeSize {
    static let sidebarLabel: CGFloat = 13
    static let sidebarSection: CGFloat = 11
    static let sidebarAccessory: CGFloat = 10.5
    static let toolbarTitle: CGFloat = 14
    static let toolbarControl: CGFloat = 12
    static let body: CGFloat = 12.5

    static let allValues: [CGFloat] = [
        sidebarLabel,
        sidebarSection,
        sidebarAccessory,
        toolbarTitle,
        toolbarControl,
        body,
    ]
}

extension Font {
    static let atollSidebarLabel = Font.system(size: AtollTypeSize.sidebarLabel)
    static let atollSidebarLabelSelected = Font.system(
        size: AtollTypeSize.sidebarLabel,
        weight: .medium
    )
    static let atollSidebarSection = Font.system(
        size: AtollTypeSize.sidebarSection,
        weight: .medium
    )
    static let atollSidebarAccessory = Font.system(
        size: AtollTypeSize.sidebarAccessory,
        weight: .medium
    ).monospacedDigit()
    static let atollToolbarControl = Font.system(
        size: AtollTypeSize.toolbarControl,
        weight: .medium
    )
    static let atollToolbarTitle = Font.system(
        size: AtollTypeSize.toolbarTitle,
        weight: .medium
    )
    static let atollBody = Font.system(size: AtollTypeSize.body)
}

/// Main-window geometry that is shared by the rail views.
enum AtollMetric {
    enum Sidebar {
        static let surfaceInset: CGFloat = 8
        static let surfaceWidth: CGFloat = 218
        static let expandedWidth: CGFloat = surfaceWidth + (surfaceInset * 2)
        static let collapsedWidth: CGFloat = 64
        static let contentInset: CGFloat = 10
        static let horizontalInset: CGFloat = surfaceInset + contentInset
        static let rowWidth: CGFloat = surfaceWidth - (contentInset * 2)
        static let rowHeight: CGFloat = 28
        static let dockItemSize: CGFloat = 38
        static let dockRowHeight: CGFloat = 46
        static let headerHeight: CGFloat = 24
        static let rowRadius: CGFloat = 7
        static let expandedIconSize: CGFloat = 18
        static let collapsedIconSize: CGFloat = 24
        static let topBarHeight: CGFloat = 52
        static let collapsedSurfaceTopInset: CGFloat = topBarHeight
        static let collapsedContentTopInset: CGFloat =
            collapsedSurfaceTopInset + surfaceInset
        static let expandedToggleTrailingInset: CGFloat = 14
        static let footerHeight: CGFloat = 52
    }

    enum Toolbar {
        static let height: CGFloat = 52
        static let horizontalInset: CGFloat = 8
        static let controlSize: CGFloat = 28
        static let sidebarToggleSize: CGFloat = 32
        static let glyphSize: CGFloat = 14
        static let sidebarGlyphSize: CGFloat = 16
        static let trafficLightTrailingEdge: CGFloat = 79
        static let trafficLightClearance: CGFloat = 16
        static let collapsedLeadingInset: CGFloat =
            trafficLightTrailingEdge
                - Sidebar.collapsedWidth
                + trafficLightClearance
    }
}

/// Motion values shared by the rail and its window-level toggle.
enum AtollMotion {
    static let sidebarTransitionSeconds = 0.25
    static let collapsedChromeDelay: Duration = .milliseconds(300)
    static let collapsedChromeFadeSeconds = 0.08
}

/// The user-facing transparency scale for the Atoll shell.
///
/// Zero keeps the shell opaque. One removes the protective tint so the
/// native behind-window material can receive color from the desktop. The system
/// continues to own blur, saturation, and refraction.
enum GlassIntensityScale {
    static let defaultValue = 0.5
    static let adaptiveSelectionStart = 0.6

    static func normalized(_ value: Double) -> Double {
        min(1, max(0, value))
    }

    static func shellOpacity(_ value: Double) -> CGFloat {
        1.0 - normalized(value)
    }

    /// A light structural tint for the header and other shell-owned planes.
    /// The full-window tint supplies the main opacity transition.
    static func surfaceOpacity(_ value: Double) -> CGFloat {
        0.08 * (1 - normalized(value))
    }

    static func sidebarOpacity(_ value: Double) -> CGFloat {
        0.12 * (1 - normalized(value))
    }

    static func materialTintOpacity(_ value: Double) -> CGFloat {
        0.86 * (1 - normalized(value))
    }

    static func controlTintAlpha(_ value: Double) -> CGFloat {
        0.12 * (1 - normalized(value))
    }

    /// Changes a selected sidebar row from the solid source-list fill to a
    /// translucent, adaptive highlight. The smooth curve prevents a visible
    /// jump when the slider crosses the start value.
    static func adaptiveSelectionProgress(_ value: Double) -> Double {
        let range = 1 - adaptiveSelectionStart
        let position = (normalized(value) - adaptiveSelectionStart) / range
        let clamped = min(1, max(0, position))
        return clamped * clamped * (3 - (2 * clamped))
    }
}

/// The native glass style behind the main window shell.
enum ShellGlassStyle: String, CaseIterable {
    case off
    case clear
    case regular

    var displayName: String {
        switch self {
        case .off: "Off"
        case .clear: "Clear"
        case .regular: "Regular"
        }
    }

    static func resolving(_ storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? .clear
    }
}

/// Baseline values for the temporary appearance tuning controls.
enum GlassLabDefaults {
    static let style = ShellGlassStyle.clear
    static let transparency = GlassIntensityScale.defaultValue
    static let fixedFrost = 1.0
}

/// The two visual forms of the left sidebar.
enum SidebarPresentation: Equatable {
    case expanded
    case collapsed

    var width: CGFloat {
        switch self {
        case .expanded: AtollMetric.Sidebar.expandedWidth
        case .collapsed: AtollMetric.Sidebar.collapsedWidth
        }
    }

    var serviceRowHeight: CGFloat {
        switch self {
        case .expanded: AtollMetric.Sidebar.rowHeight
        case .collapsed: AtollMetric.Sidebar.dockRowHeight
        }
    }

    /// The expanded material continues behind the window controls, like a
    /// Finder sidebar. The compact dock starts below them because its narrow
    /// trailing edge would otherwise split the traffic-light group.
    var surfaceTopInset: CGFloat {
        switch self {
        case .expanded: AtollMetric.Sidebar.surfaceInset
        case .collapsed: AtollMetric.Sidebar.collapsedSurfaceTopInset
        }
    }

    var contentTopInset: CGFloat {
        switch self {
        case .expanded: AtollMetric.Sidebar.topBarHeight
        case .collapsed: AtollMetric.Sidebar.collapsedContentTopInset
        }
    }

    /// Both surfaces keep the same window gutter at the bottom.
    var surfaceBottomInset: CGFloat {
        AtollMetric.Sidebar.surfaceInset
    }

    /// The toggle is one persistent window-level control. These coordinates
    /// let it travel with the sidebar edge instead of changing view owners.
    var toggleCenterX: CGFloat {
        switch self {
        case .expanded:
            AtollMetric.Sidebar.expandedWidth
                - AtollMetric.Sidebar.expandedToggleTrailingInset
                - (AtollMetric.Toolbar.sidebarToggleSize / 2)
        case .collapsed:
            AtollMetric.Sidebar.collapsedWidth
                + AtollMetric.Toolbar.collapsedLeadingInset
                + (AtollMetric.Toolbar.sidebarToggleSize / 2)
        }
    }

    var showsLabels: Bool { self == .expanded }
}

/// Semantic colors for the native shell.
///
/// Most colors use AppKit meanings. The selection pair matches the App Store
/// source list that Renewals and MacCleanerNative use as their reference.
enum AtollColor {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }

    static func ink(light: CGFloat, dark: CGFloat) -> Color {
        dynamic(
            light: .black.withAlphaComponent(light),
            dark: .white.withAlphaComponent(dark)
        )
    }

    enum Text {
        static let primary = Color(nsColor: .labelColor)
        static let secondary = AtollColor.ink(light: 0.60, dark: 0.62)
        static let tertiary = AtollColor.ink(light: 0.55, dark: 0.52)
    }

    enum Fill {
        static let sidebarSelection = AtollColor.dynamic(
            light: .black.withAlphaComponent(0.045),
            dark: NSColor(srgbRed: 0.173, green: 0.169, blue: 0.184, alpha: 1)
        )
        static let sidebarAdaptiveSelection = AtollColor.dynamic(
            light: .black.withAlphaComponent(0.08),
            dark: .white.withAlphaComponent(0.18)
        )
        static let sidebarSelectedTint = AtollColor.dynamic(
            light: .systemBlue,
            dark: NSColor(displayP3Red: 0.094, green: 0.569, blue: 1, alpha: 1)
        )
        static let rowHover = AtollColor.ink(light: 0.04, dark: 0.03)
        static let control = AtollColor.ink(light: 0.07, dark: 0.09)
        static let controlHover = AtollColor.ink(light: 0.12, dark: 0.14)
        static let quietSurface = AtollColor.dynamic(
            light: .white.withAlphaComponent(0.85),
            dark: .white.withAlphaComponent(0.055)
        )
        /// A protective tint over Atoll-owned transient material surfaces. It
        /// becomes transparent as the user increases glass intensity.
        static func shellMaterialTint(intensity: Double) -> Color {
            AtollColor.dynamic(
                light: NSColor(
                    srgbRed: 0.95,
                    green: 0.95,
                    blue: 0.96,
                    alpha: GlassIntensityScale.materialTintOpacity(intensity)
                ),
                dark: NSColor(
                    srgbRed: CGFloat(36) / 255,
                    green: CGFloat(33) / 255,
                    blue: CGFloat(37) / 255,
                    alpha: GlassIntensityScale.materialTintOpacity(intensity)
                )
            )
        }

        static func glassTint(intensity: Double) -> Color {
            AtollColor.dynamic(
                light: .white.withAlphaComponent(
                    GlassIntensityScale.controlTintAlpha(intensity)
                ),
                dark: .black.withAlphaComponent(
                    GlassIntensityScale.controlTintAlpha(intensity)
                )
            )
        }
    }

    /// Use the native separator so the sidebar edge matches Finder and follows
    /// Increase Contrast.
    static let shellBorder = Color(nsColor: .separatorColor)
    static let hairline = AtollColor.ink(light: 0.08, dark: 0.08)

    /// The protective tint over the window material.
    ///
    /// The RGB value stays stable. Only its opacity changes, so the setting
    /// reveals the desktop instead of turning the app gray.
    static func shellCanvas(intensity: Double) -> Color {
        AtollColor.dynamic(
            light: NSColor(
                srgbRed: 0.95,
                green: 0.95,
                blue: 0.96,
                alpha: GlassIntensityScale.surfaceOpacity(intensity)
            ),
            dark: NSColor(
                srgbRed: CGFloat(36) / 255,
                green: CGFloat(33) / 255,
                blue: CGFloat(37) / 255,
                alpha: GlassIntensityScale.surfaceOpacity(intensity)
            )
        )
    }

    /// The sidebar keeps slightly more tint than the surrounding canvas so
    /// labels stay legible over a bright or detailed wallpaper.
    static func sidebarCanvas(intensity: Double) -> Color {
        AtollColor.dynamic(
            light: NSColor(
                srgbRed: 0.96,
                green: 0.96,
                blue: 0.97,
                alpha: GlassIntensityScale.sidebarOpacity(intensity)
            ),
            dark: NSColor(
                srgbRed: CGFloat(32) / 255,
                green: CGFloat(30) / 255,
                blue: CGFloat(34) / 255,
                alpha: GlassIntensityScale.sidebarOpacity(intensity)
            )
        )
    }
}

/// Applies the shell-wide tint scale to an Atoll-owned material surface.
///
/// This does not replace system glass. The selected material still supplies
/// blur and depth. The overlay changes only the neutral tint strength that the
/// user controls in Settings.
private struct AtollMaterialBackgroundModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    let material: Material

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Rectangle().fill(material)
                Rectangle().fill(
                    AtollColor.Fill.shellMaterialTint(
                        intensity: appState.liquidGlassIntensity
                    )
                )
            }
        }
    }
}

extension View {
    /// Gives an Atoll-owned surface native material and the shared shell tint.
    func atollMaterialBackground(_ material: Material) -> some View {
        modifier(AtollMaterialBackgroundModifier(material: material))
    }
}

/// The three corner radii the app is allowed to draw, and the one notice shape.
///
/// Build step 7 of concept C, which is mostly the baseline's own list: eight
/// radii collapsed to three, three hand-rolled banners collapsed to one, and
/// keyboard focus given a mark of its own instead of being switched off.

/// Eight values down to three, named by what they wrap rather than by number.
/// A fourth value is the thing to argue about, not to add quietly.
enum AtollRadius {
    /// Service icons and other small squares.
    static let icon: CGFloat = 4
    /// Chips, tabs, rows, buttons, fields — anything you click.
    static let control: CGFloat = 8
    /// Sheets, popovers, palettes: the surfaces those things sit on.
    static let surface: CGFloat = 14

    static let allValues: [CGFloat] = [icon, control, surface]
}

/// How bad a notice is. Three, and the fill is the same weight for all of them:
/// the tone is carried by the icon and the rule under the strip, not by shouting
/// with the background. This replaces two raw SwiftUI yellows and a solid red
/// bar that read as three unrelated designs.
enum NoticeSeverity: CaseIterable {
    /// Something is offered, and nothing is wrong.
    case info
    /// Something is degraded and will probably fix itself.
    case warning
    /// Something is wrong and will not fix itself.
    case error

    var systemImage: String {
        switch self {
        case .info: return "clock.arrow.circlepath"
        case .warning: return "wifi.slash"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return ServiceIconPalette.badgeRed
        }
    }

    /// One weight for all three, on purpose. See the type's note.
    var fillOpacity: Double { 0.12 }
}

/// The one notice strip: a tinted band with a rule under it.
///
/// The window-drag handle is part of the shape rather than left to each caller.
/// A notice sits at the very top of the window, inside the title-bar drag band,
/// and the bar layout turns the OS window drag off (see
/// `WindowChromeConfigurator`). Without a handle the strip is dead to dragging,
/// and because it also pushes the rail's own handle down out of the band, the
/// window could not be moved by its top edge at all while a notice was up. The
/// handle goes behind the content and in front of the fill, so buttons still
/// take their own clicks.
struct NoticeStrip<Content: View>: View {
    let severity: NoticeSeverity
    /// Overrides the severity's own icon where a notice is about something more
    /// specific than its seriousness.
    var systemImage: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: systemImage ?? severity.systemImage)
                    .foregroundStyle(severity.tint)
                    .accessibilityHidden(true)

                content()
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(severity.tint)
                .frame(height: 1)
        }
        .background(WindowDragHandle())
        .background(severity.tint.opacity(severity.fillOpacity))
    }
}

/// Which mark a rail row draws, worked out apart from the drawing so the rule
/// can be tested and stated once.
///
/// The audit's finding was that 1.5.10 fixed a doubled focus box by suppressing
/// the system ring, which removed the signal rather than reshaping it. This is
/// the reshape: selection is a fill, and focus uses a ring only when it is on a
/// different row. The expanded rail gives the ring enough room, and the dock
/// draws it inside its item.
struct RowMark: Equatable {
    enum Fill: Equatable {
        case none
        case hover
        case selected
    }

    let fill: Fill
    let ring: Bool

    init(fill: Fill, ring: Bool) {
        self.fill = fill
        self.ring = ring
    }

    init(isSelected: Bool, isFocused: Bool, isHovering: Bool = false) {
        if isSelected {
            fill = .selected
        } else if isHovering {
            fill = .hover
        } else {
            fill = .none
        }
        ring = isFocused && !isSelected
    }

    var fillStyle: AnyShapeStyle {
        switch fill {
        case .selected: return AnyShapeStyle(AtollColor.Fill.sidebarSelection)
        case .hover: return AnyShapeStyle(AtollColor.Fill.rowHover)
        case .none: return AnyShapeStyle(Color.clear)
        }
    }
}

/// A quiet toolbar control that shows its surface on hover.
struct AtollToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AtollMetric.Toolbar.glyphSize, weight: .medium))
            .frame(
                width: AtollMetric.Toolbar.controlSize,
                height: AtollMetric.Toolbar.controlSize
            )
            .background(
                isHovering
                    ? AtollColor.Fill.controlHover
                    : (isSelected ? AtollColor.Fill.control : Color.clear),
                in: RoundedRectangle(cornerRadius: AtollRadius.control)
            )
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .onHover { isHovering = $0 }
    }
}

/// The unbordered sidebar button used by the native reference applications.
struct AtollSidebarButtonStyle: ButtonStyle {
    let isCollapsed: Bool
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: AtollMetric.Toolbar.sidebarGlyphSize, weight: .medium))
            .frame(
                width: AtollMetric.Toolbar.sidebarToggleSize,
                height: AtollMetric.Toolbar.sidebarToggleSize
            )
            .background {
                if isCollapsed {
                    Circle()
                        .fill(
                            AtollColor.sidebarCanvas(
                                intensity: appState.liquidGlassIntensity
                            )
                        )
                    if isHovering {
                        Circle()
                            .fill(AtollColor.Fill.controlHover)
                    }
                } else if isHovering {
                    Circle()
                        .fill(AtollColor.Fill.controlHover)
                }
            }
            .overlay {
                if isCollapsed {
                    Circle()
                        .strokeBorder(AtollColor.shellBorder, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { isHovering = $0 }
    }
}
