import Testing
@testable import PaguroCore

struct ShellGlassStyleTests {
    @Test func systemAddsNoAppTintOrFrost() {
        #expect(ShellGlassStyle.system.transparency == 1)
        #expect(ShellGlassStyle.system.backdropFrostOpacity == 0)
    }

    @Test func offIsSolidAndClearIsLighterThanRegular() {
        #expect(ShellGlassStyle.off.transparency == 0)
        #expect(ShellGlassStyle.off.backdropFrostOpacity == 0)
        #expect(ShellGlassStyle.clear.transparency > ShellGlassStyle.regular.transparency)
        #expect(ShellGlassStyle.clear.backdropFrostOpacity < ShellGlassStyle.regular.backdropFrostOpacity)
        #expect(ShellGlassStyle.regular.transparency > 0)
    }

    @Test(arguments: ShellGlassStyle.allCases)
    func unsupportedSystemsAlwaysUseSolid(preference: ShellGlassStyle) {
        #expect(ShellGlassSupport.unavailable.effectiveStyle(for: preference) == .off)
        #expect(ShellGlassSupport.unavailable.availableStyles.isEmpty)
    }

    @Test(arguments: ShellGlassStyle.allCases)
    func systemsWithoutSliderFallBackToRegular(preference: ShellGlassStyle) {
        let support = ShellGlassSupport.presets
        let expected: ShellGlassStyle = preference == .system ? .regular : preference
        #expect(support.effectiveStyle(for: preference) == expected)
        #expect(support.availableStyles == [.off, .clear, .regular])
        #expect(support.availableStyles.contains(expected))
    }

    @Test(arguments: ShellGlassStyle.allCases)
    func systemsWithSliderRespectEveryPreference(preference: ShellGlassStyle) {
        #expect(ShellGlassSupport.systemAppearance.effectiveStyle(for: preference) == preference)
        #expect(ShellGlassSupport.systemAppearance.availableStyles == ShellGlassStyle.allCases)
    }
}
