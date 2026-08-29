import BlattaCore
import SwiftUI

extension ServiceHealth {
    /// The reviewed color for the service health mark.
    var dotColor: Color {
        switch self {
        case .loading: return Color(red: 0.557, green: 0.557, blue: 0.576)  // #8E8E93
        case .failed: return Color(red: 1.0, green: 0.624, blue: 0.039)     // #FF9F0A
        case .signedOut: return Color(red: 1.0, green: 0.231, blue: 0.188)  // #FF3B30
        case .live: return .clear
        }
    }
}

/// The health mark on a service icon's bottom-right corner.
struct ServiceHealthDot: View {
    let health: ServiceHealth
    var size: CGFloat = 9

    var body: some View {
        if health.drawsDot {
            shape
                .frame(width: size, height: size)
                // A hairline of the window behind it, so the mark stays readable
                // against a dark service icon.
                .background(
                    Circle()
                        .fill(Color(nsColor: .windowBackgroundColor))
                        .frame(width: size + 2, height: size + 2)
                )
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var shape: some View {
        switch health.dotShape {
        case .ring:
            Circle().strokeBorder(health.dotColor, lineWidth: 2)
        case .disc:
            Circle().fill(health.dotColor)
        case .square:
            RoundedRectangle(cornerRadius: 1.5).fill(health.dotColor)
        }
    }
}
