import AppKit
import PaguroCore
import SwiftUI

/// System font sizes for the main window.
///
/// Renewals and MacCleanerNative use the same compact type ramp. Paguro uses the
/// parts of that ramp that apply to a service workspace.
enum PaguroTypeSize {
    static let sidebarLabel: CGFloat = 13
    static let sidebarSection: CGFloat = 11
    static let sidebarAccessory: CGFloat = 10.5
    static let toolbarTitle: CGFloat = 14
    static let toolbarControl: CGFloat = 12
    static let body: CGFloat = 12.5
}

extension Font {
    static let paguroSidebarLabel = Font.system(size: PaguroTypeSize.sidebarLabel)
    static let paguroSidebarLabelSelected = Font.system(
        size: PaguroTypeSize.sidebarLabel,
        weight: .medium
    )
    static let paguroSidebarSection = Font.system(
        size: PaguroTypeSize.sidebarSection,
        weight: .medium
    )
    static let paguroSidebarAccessory = Font.system(
        size: PaguroTypeSize.sidebarAccessory,
        weight: .medium
    ).monospacedDigit()
    static let paguroToolbarControl = Font.system(
        size: PaguroTypeSize.toolbarControl,
        weight: .medium
    )
    static let paguroToolbarTitle = Font.system(
        size: PaguroTypeSize.toolbarTitle,
        weight: .medium
    )
    static let paguroBody = Font.system(size: PaguroTypeSize.body)
}

/// Main-window geometry that is shared by the rail views.
enum PaguroMetric {
    enum Window {
        /// The narrowest content the shell lays out without overlap: the
        /// expanded rail, the web content beside it, and the header controls.
        /// The window carries it as its own minimum, so a drag of the window
        /// edge stops here.
        static let minimumContentWidth: CGFloat = 800
    }

    enum Sidebar {
        static let surfaceInset: CGFloat = 8
        static let surfaceWidth: CGFloat = 218
        static let expandedWidth: CGFloat = surfaceWidth + (surfaceInset * 2)
        static let collapsedWidth = CGFloat(
            DockIconSizing.railWidth(baseSize: DockIconSizing.defaultBaseSize)
        )
        static let contentInset: CGFloat = 10
        static let horizontalInset: CGFloat = surfaceInset + contentInset
        static let rowWidth: CGFloat = surfaceWidth - (contentInset * 2)
        static let rowHeight: CGFloat = 28
        static let dockItemSize = CGFloat(
            DockIconSizing.selectionSize(
                displayedIconSize: DockIconSizing.defaultBaseSize
            )
        )
        static let dockRowHeight = CGFloat(
            DockIconSizing.rowHeight(
                displayedIconSize: DockIconSizing.defaultBaseSize
            )
        )
        static let headerHeight: CGFloat = 24
        static let rowRadius: CGFloat = 7
        static let expandedIconSize: CGFloat = 18
        /// The icon of a top-bar tab. It stays under the sidebar size, because
        /// one bar holds every service of every open workspace.
        static let barIconSize: CGFloat = 16
        /// The icon of a top-bar tab that carries no name. It carries the tab
        /// on its own, so it stays a little larger than the labelled one.
        static let barIconOnlySize: CGFloat = 18
        static let collapsedIconSize = CGFloat(DockIconSizing.defaultBaseSize)
        static let topBarHeight: CGFloat = 52
        static let collapsedSurfaceTopInset: CGFloat = topBarHeight
        static let collapsedContentTopInset: CGFloat =
            collapsedSurfaceTopInset + surfaceInset
        static let expandedToggleTrailingInset: CGFloat = 14
        static let footerHeight: CGFloat = 52
        static let workspaceDividerHeight: CGFloat = 13
        static let workspaceDividerHorizontalInset: CGFloat = 15
        static let workspaceSectionTopSpacing: CGFloat = 8

        static func collapsedWidth(iconSize: Double) -> CGFloat {
            CGFloat(DockIconSizing.railWidth(baseSize: iconSize))
        }

        static func dockItemSize(displayedIconSize: Double) -> CGFloat {
            CGFloat(DockIconSizing.selectionSize(displayedIconSize: displayedIconSize))
        }

        static func dockRowHeight(displayedIconSize: Double) -> CGFloat {
            CGFloat(DockIconSizing.rowHeight(displayedIconSize: displayedIconSize))
        }
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

        static func collapsedLeadingInset(sidebarWidth: CGFloat) -> CGFloat {
            max(
                0,
                trafficLightTrailingEdge + trafficLightClearance - sidebarWidth
            )
        }
    }
}

/// Motion values shared by the rail and its window-level toggle.
enum PaguroMotion {
    static let sidebarTransitionSeconds = 0.25
    static let collapsedChromeDelay: Duration = .milliseconds(300)
    static let collapsedChromeFadeSeconds = 0.08
    static let dockMagnificationSeconds = 0.16
    static let dockHoverExitDelay: Duration = .milliseconds(140)
    /// The lift and the return of a service cell during a reorder drag.
    static let railLiftSeconds = 0.12
    /// The spring that moves the other cells out of the way, and that settles
    /// the dragged cell into its new position.
    static let railReorderResponse = 0.28
    static let railReorderDamping = 0.78
    /// One frame of automatic rail scroll during a reorder drag.
    static let railAutoscrollInterval: Duration = .milliseconds(16)
}

/// The user-facing transparency scale for the Paguro shell.
///
/// Zero keeps the shell opaque. One removes the protective tint so the
/// native behind-window material can receive color from the desktop. The system
/// continues to own blur, saturation, and refraction.
enum GlassIntensityScale {
    static let defaultValue = 0.5
    static let adaptiveSelectionStart = SidebarSelectionContrastPolicy.highContrastTextThreshold

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

    var frostOpacity: CGFloat {
        switch self {
        case .clear:
            GlassLabDefaults.regularFrost * 0.7
        case .off, .regular:
            GlassLabDefaults.regularFrost
        }
    }

    static func resolving(_ storedValue: String?) -> Self {
        storedValue.flatMap(Self.init(rawValue:)) ?? GlassLabDefaults.style
    }
}

/// Baseline values for the temporary appearance tuning controls.
enum GlassLabDefaults {
    static let style = ShellGlassStyle.regular
    static let transparency = 1.0
    static let regularFrost: CGFloat = 1.0
}

enum DockRailPosition: String, CaseIterable {
    case top
    case center

    static let defaultPosition = Self.top

    var displayName: String {
        switch self {
        case .top: "Top"
        case .center: "Center"
        }
    }
}

/// The two visual forms of the left sidebar.
enum SidebarPresentation: Equatable {
    case expanded
    case collapsed

    var width: CGFloat {
        width(iconRailBaseSize: DockIconSizing.defaultBaseSize)
    }

    func width(iconRailBaseSize: Double) -> CGFloat {
        switch self {
        case .expanded: PaguroMetric.Sidebar.expandedWidth
        case .collapsed: PaguroMetric.Sidebar.collapsedWidth(iconSize: iconRailBaseSize)
        }
    }

    var serviceRowHeight: CGFloat {
        switch self {
        case .expanded: PaguroMetric.Sidebar.rowHeight
        case .collapsed: PaguroMetric.Sidebar.dockRowHeight
        }
    }

    /// The expanded material continues behind the window controls, like a
    /// Finder sidebar. The compact dock starts below them because its narrow
    /// trailing edge would otherwise split the traffic-light group.
    var surfaceTopInset: CGFloat {
        switch self {
        case .expanded: PaguroMetric.Sidebar.surfaceInset
        case .collapsed: PaguroMetric.Sidebar.collapsedSurfaceTopInset
        }
    }

    var contentTopInset: CGFloat {
        switch self {
        case .expanded: PaguroMetric.Sidebar.topBarHeight
        case .collapsed: PaguroMetric.Sidebar.collapsedContentTopInset
        }
    }

    /// Both surfaces keep the same window gutter at the bottom.
    var surfaceBottomInset: CGFloat {
        PaguroMetric.Sidebar.surfaceInset
    }

    /// The toggle is one persistent window-level control. These coordinates
    /// let it travel with the sidebar edge instead of changing view owners.
    var toggleCenterX: CGFloat {
        switch self {
        case .expanded:
            PaguroMetric.Sidebar.expandedWidth
                - PaguroMetric.Sidebar.expandedToggleTrailingInset
                - (PaguroMetric.Toolbar.sidebarToggleSize / 2)
        case .collapsed:
            PaguroMetric.Sidebar.collapsedWidth
                + PaguroMetric.Toolbar.collapsedLeadingInset
                + (PaguroMetric.Toolbar.sidebarToggleSize / 2)
        }
    }

    var showsLabels: Bool { self == .expanded }
}

/// Semantic colors for the native shell.
///
/// Most colors use AppKit meanings. The selection pair matches the App Store
/// source list that Renewals and MacCleanerNative use as their reference.
enum PaguroColor {
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
        static let secondary = PaguroColor.ink(light: 0.60, dark: 0.62)
        static let tertiary = PaguroColor.ink(light: 0.55, dark: 0.52)
        static let selectedOnGlass = PaguroColor.dynamic(
            light: .black,
            dark: .white
        )
    }

    enum Fill {
        static let sidebarSelection = PaguroColor.dynamic(
            light: .black.withAlphaComponent(0.045),
            dark: NSColor(srgbRed: 0.173, green: 0.169, blue: 0.184, alpha: 1)
        )
        static let sidebarAdaptiveSelection = PaguroColor.dynamic(
            light: .black.withAlphaComponent(0.08),
            dark: .white.withAlphaComponent(0.18)
        )
        static let sidebarSelectedTint = PaguroColor.dynamic(
            light: .systemBlue,
            dark: NSColor(displayP3Red: 0.094, green: 0.569, blue: 1, alpha: 1)
        )
        static let sidebarRowHover = PaguroColor.dynamic(
            light: .black.withAlphaComponent(0.04),
            dark: .white.withAlphaComponent(0.08)
        )
        /// The hover fill of an expanded rail row. In dark appearance it lifts
        /// more than the bar fill below, because the rail canvas is a darker
        /// ground than the material behind the top bar, and the same lift reads
        /// weaker on it.
        static let railRowHover = PaguroColor.dynamic(
            light: .black.withAlphaComponent(0.04),
            dark: .white.withAlphaComponent(0.12)
        )
        /// The hover fill of a top-bar tab.
        static let barTabHover = PaguroColor.dynamic(
            light: .black.withAlphaComponent(0.04),
            dark: .white.withAlphaComponent(0.08)
        )
        static let rowHover = PaguroColor.ink(light: 0.04, dark: 0.03)
        static let control = PaguroColor.ink(light: 0.07, dark: 0.09)
        static let controlHover = PaguroColor.ink(light: 0.12, dark: 0.14)
        static let quietSurface = PaguroColor.dynamic(
            light: .white.withAlphaComponent(0.85),
            dark: .white.withAlphaComponent(0.055)
        )
        /// A protective tint over Paguro-owned transient material surfaces. It
        /// becomes transparent as the user increases glass intensity.
        static func shellMaterialTint(intensity: Double) -> Color {
            PaguroColor.dynamic(
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
            PaguroColor.dynamic(
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
    static let hairline = PaguroColor.ink(light: 0.08, dark: 0.08)

    /// The shadow under a service cell that a person moves in the rail.
    static let railLiftShadow = PaguroColor.ink(light: 0.28, dark: 0.45)

    /// The full protective tint used above the native window material.
    static func shellTint(intensity: Double) -> Color {
        PaguroColor.dynamic(
            light: NSColor(
                srgbRed: 0.95,
                green: 0.95,
                blue: 0.96,
                alpha: GlassIntensityScale.shellOpacity(intensity)
            ),
            dark: NSColor(
                srgbRed: CGFloat(36) / 255,
                green: CGFloat(33) / 255,
                blue: CGFloat(37) / 255,
                alpha: GlassIntensityScale.shellOpacity(intensity)
            )
        )
    }

    /// The protective tint over the window material.
    ///
    /// The RGB value stays stable. Only its opacity changes, so the setting
    /// reveals the desktop instead of turning the app gray.
    static func shellCanvas(intensity: Double) -> Color {
        PaguroColor.dynamic(
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
        PaguroColor.dynamic(
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

/// Applies the shell-wide tint scale to a Paguro-owned material surface.
///
/// This does not replace system glass. The selected material still supplies
/// blur and depth. The overlay changes only the neutral tint strength that the
/// user controls in Settings.
private struct PaguroMaterialBackgroundModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    let material: Material

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                Rectangle().fill(material)
                Rectangle().fill(
                    PaguroColor.Fill.shellMaterialTint(
                        intensity: appState.liquidGlassIntensity
                    )
                )
            }
        }
    }
}

extension View {
    /// Gives a Paguro-owned surface native material and the shared shell tint.
    func paguroMaterialBackground(_ material: Material) -> some View {
        modifier(PaguroMaterialBackgroundModifier(material: material))
    }
}

/// The three corner radii the app is allowed to draw, named by what they wrap
/// rather than by number. A fourth value is the thing to argue about, not to
/// add quietly.
enum PaguroRadius {
    /// Service icons and other small squares.
    static let icon: CGFloat = 4
    /// Chips, tabs, rows, buttons, fields — anything you click.
    static let control: CGFloat = 8
    /// Sheets, popovers, palettes: the surfaces those things sit on.
    static let surface: CGFloat = 14
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
        case .selected: return AnyShapeStyle(PaguroColor.Fill.sidebarSelection)
        case .hover: return AnyShapeStyle(PaguroColor.Fill.rowHover)
        case .none: return AnyShapeStyle(Color.clear)
        }
    }
}

/// A quiet toolbar control that shows its surface on hover.
///
/// A disabled control keeps its place and dims. The header uses this state for
/// page history, where a missing entry must read as unavailable rather than
/// make the group change width.
struct PaguroToolbarButtonStyle: ButtonStyle {
    var isSelected = false
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    /// The opacity of a control that the user cannot press.
    private static let disabledOpacity: CGFloat = 0.35

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: PaguroMetric.Toolbar.glyphSize, weight: .medium))
            .frame(
                width: PaguroMetric.Toolbar.controlSize,
                height: PaguroMetric.Toolbar.controlSize
            )
            .background(
                isHovering && isEnabled
                    ? PaguroColor.Fill.controlHover
                    : (isSelected ? PaguroColor.Fill.control : Color.clear),
                in: Circle()
            )
            .contentShape(Circle())
            .opacity(opacity(isPressed: configuration.isPressed))
            .onHover { isHovering = $0 }
    }

    private func opacity(isPressed: Bool) -> CGFloat {
        guard isEnabled else { return Self.disabledOpacity }
        return isPressed ? 0.7 : 1
    }
}

/// The unbordered sidebar button used by the native reference applications.
struct PaguroSidebarButtonStyle: ButtonStyle {
    let isCollapsed: Bool
    @Environment(AppState.self) private var appState
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: PaguroMetric.Toolbar.sidebarGlyphSize, weight: .medium))
            .frame(
                width: PaguroMetric.Toolbar.sidebarToggleSize,
                height: PaguroMetric.Toolbar.sidebarToggleSize
            )
            .background {
                if isCollapsed {
                    Circle()
                        .fill(
                            PaguroColor.sidebarCanvas(
                                intensity: appState.liquidGlassIntensity
                            )
                        )
                    if isHovering {
                        Circle()
                            .fill(PaguroColor.Fill.controlHover)
                    }
                } else if isHovering {
                    Circle()
                        .fill(PaguroColor.Fill.controlHover)
                }
            }
            .overlay {
                if isCollapsed {
                    Circle()
                        .strokeBorder(PaguroColor.shellBorder, lineWidth: 1)
                }
            }
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { isHovering = $0 }
    }
}

/// The round surface behind a toolbar control.
///
/// macOS 26 draws it with interactive Liquid Glass. Earlier systems have no
/// such API, so they get the material capsule that stands in for glass
/// everywhere else in the shell. Both forms read the same intensity, so the
/// appearance slider keeps working below macOS 26.
private struct ToolbarControlSurfaceModifier: ViewModifier {
    let intensity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(
                .regular
                    .tint(PaguroColor.Fill.glassTint(intensity: intensity))
                    .interactive(),
                in: .circle
            )
        } else {
            content.background {
                ZStack {
                    Circle().fill(.regularMaterial)
                    Circle().fill(
                        PaguroColor.Fill.shellMaterialTint(intensity: intensity)
                    )
                }
            }
        }
    }
}

extension View {
    /// Applies the toolbar control surface for the running system.
    func toolbarControlSurface(intensity: Double) -> some View {
        modifier(ToolbarControlSurfaceModifier(intensity: intensity))
    }
}
