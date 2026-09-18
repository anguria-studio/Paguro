import SwiftUI
import PaguroCore

/// The overflow indicator of a vertical rail, drawn over its trailing edge.
///
/// A rail hides the system scroll indicator. With the system setting "Show
/// scroll bars" on "Always", or on "Automatically" with a mouse attached, macOS
/// draws a legacy scroller, and a legacy scroller takes its width from the
/// scroll view content. The icons then lose that width and sit left of the rail
/// centerline as soon as the rail overflows. This indicator lives in an overlay,
/// so it changes no icon size and no icon position.
///
/// The indicator takes no pointer event, so the one fixed rail surface keeps
/// every hover, click, and context menu. It carries no accessibility element:
/// the rail already reports its items, and VoiceOver moves through them with
/// the keyboard, which scrolls the rail on its own.
struct RailScrollIndicatorView: View {
    /// The measured scroll values of the rail. The indicator reads them and
    /// reports nothing back, so it cannot change the layout it describes.
    let geometry: RailScrollGeometry

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    @State private var isVisible = false
    /// Counts the scroll changes. The task that hides the indicator restarts on
    /// each change, so one quiet period follows the last movement.
    @State private var scrollTicks = 0

    var body: some View {
        let placement = RailScrollIndicator.placement(
            contentLength: Double(geometry.contentLength),
            viewportLength: Double(geometry.viewportLength),
            offset: Double(geometry.offset)
        )

        return Capsule(style: .continuous)
            .fill(indicatorColor)
            .frame(
                width: CGFloat(RailScrollIndicator.thickness),
                height: CGFloat(placement?.length ?? 0)
            )
            .padding(.top, CGFloat(placement?.offset ?? 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.trailing, trailingInset)
            .opacity(placement == nil || !isVisible ? 0 : 1)
            // Only the fade animates. The indicator follows the scroll offset
            // directly, which leaves no travel for Reduce Motion to remove.
            .animation(
                .easeOut(duration: RailScrollIndicator.fadeSeconds),
                value: isVisible
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: geometry.offset) { _, _ in
                isVisible = true
                scrollTicks += 1
            }
            .task(id: scrollTicks) {
                // The first run is the appearance of the rail, which is not a
                // scroll and shows nothing.
                guard scrollTicks > 0 else { return }
                do {
                    try await Task.sleep(for: .seconds(RailScrollIndicator.idleSeconds))
                } catch {
                    return
                }
                isVisible = false
            }
    }

    /// The rail surface stops one window gutter short of the scroll view edge.
    private var trailingInset: CGFloat {
        PaguroMetric.Sidebar.surfaceInset + CGFloat(RailScrollIndicator.edgeGap)
    }

    /// Increase Contrast and Reduce Transparency both ask for a mark that does
    /// not depend on the rail material behind it.
    private var indicatorColor: Color {
        if colorSchemeContrast == .increased || reduceTransparency {
            PaguroColor.ink(light: 0.85, dark: 0.85)
        } else {
            PaguroColor.ink(light: 0.35, dark: 0.45)
        }
    }
}
