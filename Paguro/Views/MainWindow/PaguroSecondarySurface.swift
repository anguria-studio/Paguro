import PaguroCore
import SwiftUI

/// Shared canvas for Paguro's Settings window and modal editors.
struct PaguroSecondarySurface: View {
    // Window backgrounds render outside the content's app environment.
    let glassStyle: ShellGlassStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency || !AppCapabilities.liquidGlassSupported || glassStyle == .off {
            PaguroColor.Solid.canvas
        } else {
            Rectangle()
                .fill(.regularMaterial)
                .overlay {
                    PaguroColor.Fill.shellMaterialTint(intensity: glassStyle.transparency)
                }
        }
    }
}

private struct PaguroSheetAppearance: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appState.appearanceColorScheme)
            .presentationBackground { PaguroSecondarySurface(glassStyle: appState.liquidGlassStyle) }
    }
}

extension View {
    /// Keeps native sheet geometry while following the shell's palette.
    func paguroSheetAppearance() -> some View {
        modifier(PaguroSheetAppearance())
    }
}
