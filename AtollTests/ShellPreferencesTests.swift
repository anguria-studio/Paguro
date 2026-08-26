import SwiftData
import XCTest
import AtollCore
@testable import Atoll

final class ShellPreferencesTests: XCTestCase {
    @MainActor
    func testLoadCombinesDefaultsAndTransactionalPreferences() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "shell-load")
        let defaults = sandbox.defaults
        defaults.set(ShellGlassStyle.clear.rawValue, forKey: "Atoll.liquidGlassStyle")
        defaults.set(0.4, forKey: "Atoll.liquidGlassIntensity")
        defaults.set(30.0, forKey: "Atoll.iconRailBaseSize")
        defaults.set(true, forKey: "Atoll.iconRailMagnificationEnabled")
        defaults.set(68.0, forKey: "Atoll.iconRailMagnifiedSize")
        defaults.set(DockRailPosition.center.rawValue, forKey: "Atoll.iconRailPosition")
        defaults.set(WorkspaceViewMode.current.rawValue, forKey: "Atoll.workspaceViewMode")
        defaults.set(0.8, forKey: "Atoll.backdropFrostIntensity")
        let fixture = try makePreferencesStore(
            AppPreferences(
                railLayoutRaw: RailLayout.topBars.rawValue,
                appearanceModeRaw: AppearanceMode.dark.rawValue
            )
        )
        defer { withExtendedLifetime(fixture.container) {} }
        let store = fixture.store

        let preferences = ShellPreferences.load(
            defaults: defaults,
            preferencesStore: store
        )

        XCTAssertEqual(preferences.liquidGlassStyle, .clear)
        XCTAssertEqual(preferences.liquidGlassIntensity, 0.4)
        XCTAssertEqual(preferences.iconRailBaseSize, 30)
        XCTAssertTrue(preferences.iconRailMagnificationEnabled)
        XCTAssertEqual(preferences.iconRailMagnifiedSize, 68)
        XCTAssertEqual(preferences.iconRailPosition, .center)
        XCTAssertEqual(preferences.workspaceViewMode, .current)
        XCTAssertEqual(preferences.railLayout, .topBars)
        XCTAssertEqual(preferences.appearanceMode, .dark)
        XCTAssertNil(defaults.object(forKey: "Atoll.backdropFrostIntensity"))
    }

    @MainActor
    func testLoadRejectsUnknownValuesAndClampsGeometry() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "shell-invalid")
        let defaults = sandbox.defaults
        defaults.set("unsupported", forKey: "Atoll.liquidGlassStyle")
        defaults.set(4.0, forKey: "Atoll.liquidGlassIntensity")
        defaults.set(-20.0, forKey: "Atoll.iconRailBaseSize")
        defaults.set(2.0, forKey: "Atoll.iconRailMagnifiedSize")
        defaults.set("sideways", forKey: "Atoll.iconRailPosition")
        defaults.set("one", forKey: "Atoll.workspaceViewMode")
        let fixture = try makePreferencesStore(AppPreferences())
        defer { withExtendedLifetime(fixture.container) {} }
        let store = fixture.store

        let preferences = ShellPreferences.load(
            defaults: defaults,
            preferencesStore: store
        )

        XCTAssertEqual(preferences.liquidGlassStyle, GlassLabDefaults.style)
        XCTAssertEqual(preferences.liquidGlassIntensity, 1)
        XCTAssertEqual(preferences.iconRailBaseSize, DockIconSizing.minimumBaseSize)
        XCTAssertEqual(
            preferences.iconRailMagnifiedSize,
            DockIconSizing.minimumMagnifiedSize
        )
        XCTAssertEqual(preferences.iconRailPosition, DockRailPosition.defaultPosition)
        XCTAssertEqual(preferences.workspaceViewMode, WorkspaceViewMode.defaultMode)
        XCTAssertEqual(preferences.railLayout, .sidebar)
        XCTAssertEqual(preferences.appearanceMode, .system)
    }

    @MainActor
    func testSettersPersistOneNormalizedValueAndRoundTrip() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "shell-round-trip")
        let defaults = sandbox.defaults
        let fixture = try makePreferencesStore(AppPreferences())
        defer { withExtendedLifetime(fixture.container) {} }
        let store = fixture.store
        var preferences = ShellPreferences.load(
            defaults: defaults,
            preferencesStore: store
        )

        preferences.setLiquidGlassStyle(.clear, defaults: defaults)
        preferences.setLiquidGlassIntensity(-1, defaults: defaults)
        preferences.setIconRailBaseSize(30, defaults: defaults)
        XCTAssertEqual(
            preferences.iconRailMagnification,
            DockIconSizing.defaultMagnification,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            preferences.iconRailMagnifiedSize,
            DockIconSizing.peakSize(
                baseSize: 30,
                magnification: DockIconSizing.defaultMagnification
            ),
            accuracy: 0.000_001
        )

        preferences.setIconRailMagnification(0.5, defaults: defaults)
        preferences.setIconRailPosition(.center, defaults: defaults)
        preferences.setWorkspaceViewMode(.current, defaults: defaults)
        XCTAssertTrue(preferences.setRailLayout(.topBars, preferencesStore: store))
        XCTAssertTrue(preferences.setAppearanceMode(.dark, preferencesStore: store))

        let reloaded = ShellPreferences.load(
            defaults: defaults,
            preferencesStore: store
        )
        XCTAssertEqual(reloaded, preferences)
        XCTAssertEqual(defaults.double(forKey: "Atoll.liquidGlassIntensity"), 0)
        XCTAssertEqual(
            defaults.double(forKey: "Atoll.iconRailMagnifiedSize"),
            DockIconSizing.peakSize(baseSize: 30, magnification: 0.5),
            accuracy: 0.000_001
        )
        XCTAssertEqual(store.railLayout, .topBars)
        XCTAssertEqual(store.appearanceMode, .dark)
    }

    @MainActor
    func testResetGlassRestoresDefaultsAndRemovesOverrides() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "shell-reset")
        let defaults = sandbox.defaults
        let fixture = try makePreferencesStore(AppPreferences())
        defer { withExtendedLifetime(fixture.container) {} }
        let store = fixture.store
        var preferences = ShellPreferences.load(
            defaults: defaults,
            preferencesStore: store
        )
        preferences.setLiquidGlassStyle(.off, defaults: defaults)
        preferences.setLiquidGlassIntensity(0.25, defaults: defaults)

        preferences.resetGlass(defaults: defaults)

        XCTAssertEqual(preferences.liquidGlassStyle, GlassLabDefaults.style)
        XCTAssertEqual(preferences.liquidGlassIntensity, GlassLabDefaults.transparency)
        XCTAssertNil(defaults.object(forKey: "Atoll.liquidGlassStyle"))
        XCTAssertNil(defaults.object(forKey: "Atoll.liquidGlassIntensity"))
    }

    @MainActor
    private func makePreferencesStore(
        _ row: AppPreferences
    ) throws -> (container: ModelContainer, store: PreferencesStore) {
        let container = try ModelContainer(
            for: AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.insert(row)
        try container.mainContext.save()
        return (container, PreferencesStore(context: container.mainContext))
    }
}
