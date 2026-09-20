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
}
