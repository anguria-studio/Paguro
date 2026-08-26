import Foundation
import AtollCore

/// Stores the main-window appearance and rail preferences as one value.
@MainActor
struct ShellPreferences: Equatable {
    private enum Key {
        static let glassStyle = "Atoll.liquidGlassStyle"
        static let glassIntensity = "Atoll.liquidGlassIntensity"
        static let iconRailBaseSize = "Atoll.iconRailBaseSize"
        static let iconRailMagnificationEnabled = "Atoll.iconRailMagnificationEnabled"
        static let iconRailMagnifiedSize = "Atoll.iconRailMagnifiedSize"
        static let iconRailPosition = "Atoll.iconRailPosition"
        static let workspaceViewMode = "Atoll.workspaceViewMode"
        static let retiredFrostIntensity = "Atoll.backdropFrostIntensity"
    }

    private(set) var liquidGlassStyle: ShellGlassStyle
    private(set) var liquidGlassIntensity: Double
    private(set) var iconRailBaseSize: Double
    private(set) var iconRailMagnificationEnabled: Bool
    private(set) var iconRailMagnifiedSize: Double
    private(set) var iconRailPosition: DockRailPosition
    private(set) var workspaceViewMode: WorkspaceViewMode
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
        let storedIntensity = defaults.object(forKey: Key.glassIntensity) != nil
            ? defaults.double(forKey: Key.glassIntensity)
            : GlassLabDefaults.transparency
        let storedBaseSize = defaults.object(forKey: Key.iconRailBaseSize) != nil
            ? defaults.double(forKey: Key.iconRailBaseSize)
            : DockIconSizing.defaultBaseSize
        let baseSize = DockIconSizing.baseSize(storedBaseSize)
        let magnificationEnabled = defaults.object(
            forKey: Key.iconRailMagnificationEnabled
        ) != nil
            ? defaults.bool(forKey: Key.iconRailMagnificationEnabled)
            : DockIconSizing.defaultMagnification > 0
        let storedMagnifiedSize = defaults.object(forKey: Key.iconRailMagnifiedSize) != nil
            ? defaults.double(forKey: Key.iconRailMagnifiedSize)
            : DockIconSizing.defaultMagnifiedSize

        // Frost now has one fixed rule. Remove the retired experimental value
        // so it cannot affect a future setting.
        defaults.removeObject(forKey: Key.retiredFrostIntensity)

        return Self(
            liquidGlassStyle: ShellGlassStyle.resolving(
                defaults.string(forKey: Key.glassStyle)
            ),
            liquidGlassIntensity: GlassIntensityScale.normalized(storedIntensity),
            iconRailBaseSize: baseSize,
            iconRailMagnificationEnabled: magnificationEnabled,
            iconRailMagnifiedSize: DockIconSizing.magnifiedSize(
                storedMagnifiedSize,
                baseSize: baseSize
            ),
            iconRailPosition: defaults.string(forKey: Key.iconRailPosition)
                .flatMap(DockRailPosition.init(rawValue:))
                ?? DockRailPosition.defaultPosition,
            workspaceViewMode: WorkspaceViewMode.resolving(
                defaults.string(forKey: Key.workspaceViewMode)
            ),
            railLayout: preferencesStore.railLayout,
            appearanceMode: preferencesStore.appearanceMode
        )
    }

    mutating func setLiquidGlassIntensity(
        _ value: Double,
        defaults: UserDefaults = .standard
    ) {
        liquidGlassIntensity = GlassIntensityScale.normalized(value)
        defaults.set(liquidGlassIntensity, forKey: Key.glassIntensity)
    }

    mutating func setLiquidGlassStyle(
        _ style: ShellGlassStyle,
        defaults: UserDefaults = .standard
    ) {
        liquidGlassStyle = style
        defaults.set(style.rawValue, forKey: Key.glassStyle)
    }

    mutating func resetGlass(defaults: UserDefaults = .standard) {
        liquidGlassStyle = GlassLabDefaults.style
        liquidGlassIntensity = GlassLabDefaults.transparency
        defaults.removeObject(forKey: Key.glassStyle)
        defaults.removeObject(forKey: Key.glassIntensity)
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
        defaults.set(iconRailBaseSize, forKey: Key.iconRailBaseSize)
        defaults.set(iconRailMagnifiedSize, forKey: Key.iconRailMagnifiedSize)
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
            forKey: Key.iconRailMagnificationEnabled
        )
        defaults.set(iconRailMagnifiedSize, forKey: Key.iconRailMagnifiedSize)
    }

    mutating func setIconRailPosition(
        _ position: DockRailPosition,
        defaults: UserDefaults = .standard
    ) {
        iconRailPosition = position
        defaults.set(position.rawValue, forKey: Key.iconRailPosition)
    }

    mutating func setWorkspaceViewMode(
        _ mode: WorkspaceViewMode,
        defaults: UserDefaults = .standard
    ) {
        workspaceViewMode = mode
        defaults.set(mode.rawValue, forKey: Key.workspaceViewMode)
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
