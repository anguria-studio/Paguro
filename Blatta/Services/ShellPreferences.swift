import Foundation
import BlattaCore

/// Stores the main-window appearance and rail preferences as one value.
@MainActor
struct ShellPreferences: Equatable {
    private(set) var liquidGlassStyle: ShellGlassStyle
    private(set) var liquidGlassIntensity: Double
    private(set) var iconRailBaseSize: Double
    private(set) var iconRailMagnificationEnabled: Bool
    private(set) var iconRailMagnifiedSize: Double
    private(set) var iconRailPosition: DockRailPosition
    private(set) var workspaceViewMode: WorkspaceViewMode
    private(set) var sidebarCollapsed: Bool
    private(set) var railLayout: RailLayout
    private(set) var appearanceMode: AppearanceMode

    var iconRailMagnification: Double {
        guard iconRailMagnificationEnabled else { return 0 }
        return DockIconSizing.magnification(
            baseSize: iconRailBaseSize,
            peakSize: iconRailMagnifiedSize
        )
    }

    static func load(
        defaults: UserDefaults = .standard,
        preferencesStore: PreferencesStore
    ) -> Self {
        let storedIntensity = defaults.object(forKey: DefaultsKey.liquidGlassIntensity) != nil
            ? defaults.double(forKey: DefaultsKey.liquidGlassIntensity)
            : GlassLabDefaults.transparency
        let storedBaseSize = defaults.object(forKey: DefaultsKey.iconRailBaseSize) != nil
            ? defaults.double(forKey: DefaultsKey.iconRailBaseSize)
            : DockIconSizing.defaultBaseSize
        let baseSize = DockIconSizing.baseSize(storedBaseSize)
        let magnificationEnabled = defaults.object(
            forKey: DefaultsKey.iconRailMagnificationEnabled
        ) != nil
            ? defaults.bool(forKey: DefaultsKey.iconRailMagnificationEnabled)
            : DockIconSizing.defaultMagnification > 0
        let storedMagnifiedSize = defaults.object(forKey: DefaultsKey.iconRailMagnifiedSize) != nil
            ? defaults.double(forKey: DefaultsKey.iconRailMagnifiedSize)
            : DockIconSizing.defaultMagnifiedSize

        // Frost now has one fixed rule. Remove the retired experimental value
        // so it cannot affect a future setting.
        defaults.removeObject(forKey: DefaultsKey.retiredBackdropFrostIntensity)

        return Self(
            liquidGlassStyle: ShellGlassStyle.resolving(
                defaults.string(forKey: DefaultsKey.liquidGlassStyle)
            ),
            liquidGlassIntensity: GlassIntensityScale.normalized(storedIntensity),
            iconRailBaseSize: baseSize,
            iconRailMagnificationEnabled: magnificationEnabled,
            iconRailMagnifiedSize: DockIconSizing.magnifiedSize(
                storedMagnifiedSize,
                baseSize: baseSize
            ),
            iconRailPosition: defaults.string(forKey: DefaultsKey.iconRailPosition)
                .flatMap(DockRailPosition.init(rawValue:))
                ?? DockRailPosition.defaultPosition,
            workspaceViewMode: WorkspaceViewMode.resolving(
                defaults.string(forKey: DefaultsKey.workspaceViewMode)
            ),
            sidebarCollapsed: defaults.bool(forKey: DefaultsKey.sidebarCollapsed),
            railLayout: preferencesStore.railLayout,
            appearanceMode: preferencesStore.appearanceMode
        )
    }

    mutating func setLiquidGlassIntensity(
        _ value: Double,
        defaults: UserDefaults = .standard
    ) {
        liquidGlassIntensity = GlassIntensityScale.normalized(value)
        defaults.set(liquidGlassIntensity, forKey: DefaultsKey.liquidGlassIntensity)
    }

    mutating func setLiquidGlassStyle(
        _ style: ShellGlassStyle,
        defaults: UserDefaults = .standard
    ) {
        liquidGlassStyle = style
        defaults.set(style.rawValue, forKey: DefaultsKey.liquidGlassStyle)
    }

    mutating func resetGlass(defaults: UserDefaults = .standard) {
        liquidGlassStyle = GlassLabDefaults.style
        liquidGlassIntensity = GlassLabDefaults.transparency
        defaults.removeObject(forKey: DefaultsKey.liquidGlassStyle)
        defaults.removeObject(forKey: DefaultsKey.liquidGlassIntensity)
    }

    mutating func setIconRailBaseSize(
        _ value: Double,
        defaults: UserDefaults = .standard
    ) {
        let magnification = iconRailMagnification
        iconRailBaseSize = DockIconSizing.baseSize(value)
        iconRailMagnifiedSize = DockIconSizing.peakSize(
            baseSize: iconRailBaseSize,
            magnification: magnification
        )
        defaults.set(iconRailBaseSize, forKey: DefaultsKey.iconRailBaseSize)
        defaults.set(iconRailMagnifiedSize, forKey: DefaultsKey.iconRailMagnifiedSize)
    }

    mutating func setIconRailMagnification(
        _ value: Double,
        defaults: UserDefaults = .standard
    ) {
        let magnification = DockIconSizing.magnification(value)
        iconRailMagnificationEnabled = magnification > 0
        iconRailMagnifiedSize = DockIconSizing.peakSize(
            baseSize: iconRailBaseSize,
            magnification: magnification
        )
        defaults.set(
            iconRailMagnificationEnabled,
            forKey: DefaultsKey.iconRailMagnificationEnabled
        )
        defaults.set(iconRailMagnifiedSize, forKey: DefaultsKey.iconRailMagnifiedSize)
    }

    mutating func setIconRailPosition(
        _ position: DockRailPosition,
        defaults: UserDefaults = .standard
    ) {
        iconRailPosition = position
        defaults.set(position.rawValue, forKey: DefaultsKey.iconRailPosition)
    }

    mutating func setWorkspaceViewMode(
        _ mode: WorkspaceViewMode,
        defaults: UserDefaults = .standard
    ) {
        workspaceViewMode = mode
        defaults.set(mode.rawValue, forKey: DefaultsKey.workspaceViewMode)
    }

    mutating func setSidebarCollapsed(
        _ collapsed: Bool,
        defaults: UserDefaults = .standard
    ) {
        sidebarCollapsed = collapsed
        defaults.set(collapsed, forKey: DefaultsKey.sidebarCollapsed)
    }

    @discardableResult
    mutating func setRailLayout(
        _ layout: RailLayout,
        preferencesStore: PreferencesStore
    ) -> Bool {
        guard preferencesStore.setRailLayout(layout) else { return false }
        railLayout = layout
        return true
    }

    @discardableResult
    mutating func setAppearanceMode(
        _ mode: AppearanceMode,
        preferencesStore: PreferencesStore
    ) -> Bool {
        guard preferencesStore.setAppearanceMode(mode) else { return false }
        appearanceMode = mode
        return true
    }
}
