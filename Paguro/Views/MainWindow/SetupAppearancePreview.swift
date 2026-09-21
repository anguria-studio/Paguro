import PaguroCore
import SwiftUI

/// Illustrations compare the choices; the full shell previews the actual preference.
struct SetupThemePreview: View {
    let mode: AppearanceMode

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                window
                    .environment(\.colorScheme, mode == .dark ? .dark : .light)
                if mode == .system {
                    window
                        .environment(\.colorScheme, .dark)
                        .mask(alignment: .trailing) {
                            Rectangle().frame(width: geometry.size.width / 2)
                        }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.18)) }
    }

    private var window: some View {
        SetupWindowPreview()
            .background(.background)
    }
}

struct SetupGlassPreview: View {
    let style: ShellGlassStyle
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            // The same small backdrop makes the four material choices comparable.
            LinearGradient(colors: [.indigo.opacity(0.7), .teal.opacity(0.65), .orange.opacity(0.5)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.55))
                RoundedRectangle(cornerRadius: 6).fill(.indigo.opacity(0.6))
            }
            .padding(12)
            .blur(radius: 5)
            SetupWindowPreview()
                .background {
                    if reduceTransparency || style == .off {
                        Rectangle().fill(.background)
                    } else if style == .system {
                        Rectangle().fill(.regularMaterial)
                    } else {
                        Rectangle().fill(.background.opacity(style == .clear ? 0.5 : 0.85))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay { RoundedRectangle(cornerRadius: 6).strokeBorder(.primary.opacity(0.18)) }
                .padding(7)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Shapes suggest a sidebar and content without unreadable miniature text.
private struct SetupWindowPreview: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 3) {
                ForEach(0..<3) { _ in
                    Circle().fill(.primary.opacity(0.3)).frame(width: 4, height: 4)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(0..<3) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index == 0 ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.18))
                            .frame(height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(width: 34)
                .background(.primary.opacity(0.04))
                VStack(alignment: .leading, spacing: 6) {
                    Capsule().fill(.primary.opacity(0.22)).frame(width: 30, height: 4)
                    RoundedRectangle(cornerRadius: 3).fill(.primary.opacity(0.06))
                }
                .padding(7)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.background.opacity(0.8))
                .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4))
            }
        }
    }
}
