import PaguroCore
import SwiftUI

/// The two frames that one flying download mark needs.
///
/// Both come from the views that own them, so no view guesses where the header
/// control sits. The window root reads them in its own coordinate space.
struct DownloadFlightAnchors {
    /// The header download control. It is nil while the header shows no
    /// control, which is the state of a service before its first download earns
    /// the indicator.
    var control: Anchor<CGRect>?
    /// The web content below the header.
    var content: Anchor<CGRect>?
}

/// Carries the flight frames up to the window root.
struct DownloadFlightAnchorKey: PreferenceKey {
    static let defaultValue = DownloadFlightAnchors()

    static func reduce(
        value: inout DownloadFlightAnchors,
        nextValue: () -> DownloadFlightAnchors
    ) {
        let next = nextValue()
        value.control = next.control ?? value.control
        value.content = next.content ?? value.content
    }
}

extension View {
    /// Reports this view as the destination of a flying download mark.
    func downloadFlightDestination() -> some View {
        anchorPreference(key: DownloadFlightAnchorKey.self, value: .bounds) {
            DownloadFlightAnchors(control: $0, content: nil)
        }
    }

    /// Reports this view as the web content that a download mark leaves from.
    func downloadFlightOrigin() -> some View {
        anchorPreference(key: DownloadFlightAnchorKey.self, value: .bounds) {
            DownloadFlightAnchors(control: nil, content: $0)
        }
    }
}

/// The marks that report a download start, above the whole window content.
///
/// A mark appears on the vertical line of the header download control, partway
/// down the web content, and travels straight up into that control. The overlay
/// covers the rails and the content together, so the mark crosses from one into
/// the other without a clip, whichever rail layout draws the control.
///
/// The overlay takes no pointer input, keeps no keyboard focus, and holds no
/// accessibility element: the page below must not lose a click or a key while a
/// download starts. `DownloadFlightState` posts the spoken announcement instead.
struct DownloadStartFlightOverlay: View {
    /// The header control, in the coordinate space of this overlay.
    let controlFrame: CGRect?
    /// The web content, in the same space.
    let contentFrame: CGRect?

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let controlFrame, let contentFrame {
                ForEach(appState.downloadFlights.flights) { flight in
                    DownloadFlightMark(
                        flight: flight,
                        start: CGPoint(
                            x: controlFrame.midX,
                            y: startY(in: contentFrame)
                        ),
                        destination: CGPoint(x: controlFrame.midX, y: controlFrame.midY),
                        arrive: { appState.downloadFlights.arrive(flightID: flight.id) }
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        // A mark answers one new download of the service on screen. The value
        // changes for a start only, so a progress report, a result, and a
        // service switch send nothing. A window that is closed has no overlay,
        // so a start while it is closed also sends nothing.
        .onChange(of: appState.downloadTracker.lastStart) { _, event in
            guard let event, belongsToTheServiceOnScreen(event) else { return }
            appState.downloadFlights.start(event, reduceMotion: reduceMotion)
        }
    }

    /// The height the mark starts at inside the web content.
    private func startY(in content: CGRect) -> CGFloat {
        content.minY + content.height * CGFloat(DownloadIndicatorMotion.flightStartFraction)
    }

    /// Whether the header on screen is the one this download belongs to.
    ///
    /// A download without a service belongs to every header, the same rule the
    /// tracker uses for the list and the count.
    private func belongsToTheServiceOnScreen(_ event: DownloadTracker.StartEvent) -> Bool {
        event.serviceID == nil || event.serviceID == appState.selectedServiceID
    }
}

/// One mark on its way from the web content to the header control.
///
/// The movement has three parts. The mark fades in and grows a little at its
/// start place. It then rises on an ease-in curve, so it leaves slowly and
/// arrives with speed. It shrinks and fades over the last part of that rise, so
/// the control takes over the report instead of two marks sitting on each other.
private struct DownloadFlightMark: View {
    let flight: DownloadFlightState.Flight
    let start: CGPoint
    let destination: CGPoint
    /// Reports the landing, so the control can play its part of the handoff.
    let arrive: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The mark has faded in at its start place.
    @State private var hasEntered = false
    /// The mark has reached the control.
    @State private var hasArrived = false
    /// The mark has given its place to the control.
    @State private var hasFaded = false

    /// The mark matches the size of the control it lands on, so the landing
    /// reads as one object arriving instead of two shapes meeting.
    private static var size: CGFloat { PaguroMetric.Toolbar.controlSize }

    var body: some View {
        tile
            .scaleEffect(scale)
            .opacity(opacity)
            .position(hasArrived ? destination : start)
            .onAppear(perform: launch)
    }

    private var tile: some View {
        DownloadGlyphView(glyph: .downloadMark)
            .foregroundStyle(PaguroColor.Text.primary)
            .frame(width: Self.size, height: Self.size)
            .background { surface }
            .overlay { Circle().strokeBorder(borderColor, lineWidth: borderWidth) }
            .clipShape(Circle())
            .shadow(color: shadowColor, radius: 6, y: 2)
    }

    private var scale: CGFloat {
        if hasArrived { return CGFloat(DownloadIndicatorMotion.flightArrivalScale) }
        return hasEntered ? 1 : CGFloat(DownloadIndicatorMotion.flightEntryScale)
    }

    private var opacity: Double {
        if hasFaded { return 0 }
        return hasEntered ? 1 : 0
    }

    /// Starts the three parts of the movement.
    ///
    /// Each part is one animation with its own delay, so the view keeps no timer
    /// and the landing arrives with the animation that produced it.
    private func launch() {
        let wait = flight.delay.seconds
        let entry = DownloadIndicatorMotion.flightEntry.seconds
        let travel = DownloadIndicatorMotion.flightTravel.seconds
        let exit = DownloadIndicatorMotion.flightExit.seconds

        withAnimation(.easeOut(duration: entry).delay(wait)) {
            hasEntered = true
        }
        withAnimation(.easeIn(duration: exit).delay(wait + entry + travel - exit)) {
            hasFaded = true
        }
        withAnimation(
            .easeIn(duration: travel).delay(wait + entry),
            { hasArrived = true },
            completion: arrive
        )
    }

    /// The surface for the running system and the user's settings.
    ///
    /// It follows the floating notice card: Reduce Transparency wins over every
    /// glass form, because the mark crosses a web page that Paguro does not
    /// control.
    @ViewBuilder
    private var surface: some View {
        if reduceTransparency {
            Circle().fill(Color(nsColor: .windowBackgroundColor))
        } else if #available(macOS 26, *), appState.liquidGlassStyle != .off {
            glassSurface
        } else {
            materialSurface
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var glassSurface: some View {
        let tint = PaguroColor.Fill.glassTint(intensity: appState.liquidGlassIntensity)
        switch appState.liquidGlassStyle {
        case .clear:
            Circle().fill(.clear).glassEffect(.clear.tint(tint), in: .circle)
        case .off, .regular:
            Circle().fill(.clear).glassEffect(.regular.tint(tint), in: .circle)
        }
    }

    private var materialSurface: some View {
        ZStack {
            Circle().fill(.regularMaterial)
            Circle().fill(
                PaguroColor.Fill.shellMaterialTint(intensity: appState.liquidGlassIntensity)
            )
        }
    }

    /// A hairline separates the mark from a bright page. Increase Contrast makes
    /// it a full border, because the shadow alone can disappear over a busy page.
    private var borderColor: Color {
        colorSchemeContrast == .increased ? PaguroColor.shellBorder : PaguroColor.hairline
    }

    private var borderWidth: CGFloat {
        colorSchemeContrast == .increased ? 1 : 0.5
    }

    private var shadowColor: Color {
        .black.opacity(colorScheme == .dark ? 0.44 : 0.18)
    }
}
