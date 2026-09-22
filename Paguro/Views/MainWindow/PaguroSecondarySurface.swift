import SwiftUI

/// Editing surfaces stay opaque, independently of the main window glass.
struct PaguroSecondarySurface: View {
    var body: some View {
        PaguroColor.Solid.canvas
    }
}

private struct PaguroSheetAppearance: ViewModifier {
    @Environment(AppState.self) private var appState

    func body(content: Content) -> some View {
        content
            .preferredColorScheme(appState.appearanceColorScheme)
            .presentationBackground { PaguroSecondarySurface() }
    }
}

extension View {
    /// Keeps native sheet geometry while following the shell's palette.
    func paguroSheetAppearance() -> some View {
        modifier(PaguroSheetAppearance())
    }
}
