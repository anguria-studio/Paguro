import Testing
@testable import PaguroCore

struct ShellGlassStyleTests {
    @Test(arguments: [0.0, 0.35, 1.0])
    func systemIgnoresManualTint(_ value: Double) {
        #expect(ShellGlassStyle.system.effectiveTransparency(manualValue: value) == 1)
    }

    @Test(arguments: [ShellGlassStyle.off, .clear, .regular])
    func overridesRetainAndClampManualTint(_ style: ShellGlassStyle) {
        #expect(style.effectiveTransparency(manualValue: 0.35) == 0.35)
        #expect(style.effectiveTransparency(manualValue: -1) == 0)
        #expect(style.effectiveTransparency(manualValue: 2) == 1)
    }
}
