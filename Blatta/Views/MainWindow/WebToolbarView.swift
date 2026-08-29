import BlattaCore
import SwiftUI

/// The native header above web content in the left-sidebar layout.
struct WebContentHeader: View {
    let webViewState: WebViewState
    var title: String
    var reservesSidebarToggleSpace = false
    var sidebarToggleLeadingInset = BlattaMetric.Toolbar.collapsedLeadingInset
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            if reservesSidebarToggleSpace {
                Color.clear
                    .frame(
                        width: BlattaMetric.Toolbar.sidebarToggleSize,
                        height: BlattaMetric.Toolbar.sidebarToggleSize
                    )
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.blattaToolbarTitle)
                .foregroundStyle(BlattaColor.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 24)

            WebContentActions(webViewState: webViewState)
        }
        .padding(
            .leading,
            reservesSidebarToggleSpace
                ? sidebarToggleLeadingInset
                : BlattaMetric.Toolbar.horizontalInset
        )
        .padding(.trailing, BlattaMetric.Toolbar.horizontalInset)
        .frame(height: BlattaMetric.Toolbar.height)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .background(WindowDragHandle())
        .background(
            BlattaColor.shellCanvas(intensity: appState.liquidGlassIntensity)
        )
    }
}

/// The standard sidebar disclosure action.
struct SidebarToggleButton: View {
    let isCollapsed: Bool
    let showsCollapsedChrome: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
        }
        .buttonStyle(BlattaSidebarButtonStyle(isCollapsed: showsCollapsedChrome))
        .keyboardShortcut("s", modifiers: [.command, .control])
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityIdentifier("sidebar.toggle")
    }
}

/// The persistent controls for the active web service.
///
/// The service page owns its own layout and appearance. Blatta keeps only the
/// controls that a page cannot supply: the download report, page history,
/// reload, and the global notification mute. They sit at the trailing end of
/// the header in that order.
struct WebContentActions: View {
    let webViewState: WebViewState

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The indicator state for the service that the header names.
    private var downloadState: DownloadIndicatorState {
        appState.downloadTracker.state(for: appState.selectedServiceID)
    }

    var body: some View {
        HStack(spacing: 6) {
            if downloadState.isVisible {
                DownloadIndicatorButton(
                    state: downloadState,
                    serviceID: appState.selectedServiceID,
                    glass: actionGlass
                )
                // The control grows into place, so a download that finished
                // too fast for a ring still announces itself. Reduce Motion
                // keeps the fade and drops the scale.
                .transition(
                    reduceMotion
                        ? .opacity
                        : .scale(scale: DownloadIndicatorMotion.entryScale)
                            .combined(with: .opacity)
                )
            }

            Button {
                appState.goBackInActiveService()
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(BlattaToolbarButtonStyle())
            .glassEffect(
                actionGlass,
                in: .circle
            )
            .disabled(!webViewState.canGoBack)
            .help("Back")
            .accessibilityLabel("Go back")
            .accessibilityIdentifier("web.goBack")

            Button {
                appState.goForwardInActiveService()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(BlattaToolbarButtonStyle())
            .glassEffect(
                actionGlass,
                in: .circle
            )
            .disabled(!webViewState.canGoForward)
            .help("Forward")
            .accessibilityLabel("Go forward")
            .accessibilityIdentifier("web.goForward")

            Button {
                if webViewState.isLoading {
                    webViewState.webView?.stopLoading()
                } else {
                    webViewState.webView?.reload()
                }
            } label: {
                Image(systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(BlattaToolbarButtonStyle())
            .glassEffect(
                actionGlass,
                in: .circle
            )
            .disabled(webViewState.webView == nil)
            .help(webViewState.isLoading ? "Stop" : "Reload")
            .accessibilityLabel(webViewState.isLoading ? "Stop loading" : "Reload page")

            Button {
                appState.doNotDisturb.toggle()
            } label: {
                Image(systemName: appState.doNotDisturb ? "bell.slash" : "bell")
            }
            .buttonStyle(BlattaToolbarButtonStyle(isSelected: appState.doNotDisturb))
            .glassEffect(
                actionGlass,
                in: .circle
            )
            .help(appState.doNotDisturb ? "Unmute notifications" : "Mute notifications")
            .accessibilityLabel(
                appState.doNotDisturb
                    ? "Unmute notifications for all services"
                    : "Mute notifications for all services"
            )
            .accessibilityIdentifier("notifications.globalMute")
        }
        .animation(
            reduceMotion
                ? .easeOut(duration: DownloadIndicatorMotion.entryDuration.seconds)
                : .spring(duration: DownloadIndicatorMotion.entryDuration.seconds),
            value: downloadState.isVisible
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Service controls")
    }

    private var actionGlass: Glass {
        .regular
            .tint(
                BlattaColor.Fill.glassTint(
                    intensity: appState.liquidGlassIntensity
                )
            )
            .interactive()
    }
}

/// The header download control.
///
/// It appears as soon as the service has one download record and stays until
/// the user removes the last one. This keeps the route to a finished file
/// available after the transfer ends.
struct DownloadIndicatorButton: View {
    let state: DownloadIndicatorState
    let serviceID: UUID?
    let glass: Glass

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsList = false

    /// Drives the single pulse that settles a completed download.
    @State private var completionScale: CGFloat = 1
    /// The quieter Reduce Motion form of that pulse.
    @State private var completionOpacity: Double = 1

    var body: some View {
        Button {
            showsList.toggle()
        } label: {
            ZStack {
                DownloadProgressRing(
                    fraction: state.ringFraction,
                    isActive: state.showsRing
                )
                DownloadGlyphView(glyph: state.glyph)
            }
            .overlay(alignment: .topTrailing) {
                if let badge = state.badgeText {
                    DownloadCountBadge(text: badge)
                }
            }
        }
        .buttonStyle(BlattaToolbarButtonStyle(isSelected: showsList))
        .glassEffect(glass, in: .circle)
        .scaleEffect(completionScale)
        .opacity(completionOpacity)
        .help(state.helpText)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityIdentifier("web.downloads")
        // The list opens on a click only. A finished download must not steal
        // the pointer or the keyboard from whatever the user is doing.
        .popover(isPresented: $showsList, arrowEdge: .bottom) {
            DownloadListView(serviceID: serviceID)
        }
        .onChange(of: state.showsRing) { wasRinging, isRinging in
            guard wasRinging, !isRinging, state.isVisible else { return }
            pulse()
        }
        // Opening the list is the user seeing it, so the badge clears here
        // rather than waiting out its window. The control itself stays.
        .onChange(of: showsList) { _, isOpen in
            guard isOpen else { return }
            appState.downloadTracker.acknowledgeAll(for: serviceID)
        }
    }

    /// Marks the moment a ring reaches its end and the control settles back to
    /// the resting mark.
    private func pulse() {
        let half = DownloadIndicatorMotion.completionPulse / 2
        guard !reduceMotion else {
            withAnimation(.easeOut(duration: half.seconds)) { completionOpacity = 0.55 }
            withAnimation(.easeIn(duration: half.seconds).delay(half.seconds)) {
                completionOpacity = 1
            }
            return
        }
        withAnimation(.easeOut(duration: half.seconds)) {
            completionScale = DownloadIndicatorMotion.completionPulseScale
        }
        withAnimation(.easeIn(duration: half.seconds).delay(half.seconds)) {
            completionScale = 1
        }
    }
}

/// The count of new downloads on the control.
///
/// A fast download never earns a ring, so this badge is what tells the user
/// that something arrived. It counts running downloads and results the user
/// has not seen, so it clears itself and never becomes a list to empty. It
/// follows the rail badge shape at a smaller size, and it uses the accent
/// color rather than the unread red, because a download is not a message that
/// waits for a reply.
private struct DownloadCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 13, minHeight: 13)
            .background(
                Capsule()
                    .fill(Color.accentColor)
                    .overlay(
                        Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.5)
                    )
            )
            .offset(x: 5, y: -4)
            // The control's own label already reports the count.
            .accessibilityHidden(true)
    }
}

extension Duration {
    /// The value in seconds, for the SwiftUI animation API.
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

/// Draws the mark that the indicator rules ask for.
///
/// The download mark is a `DownloadIcon` template asset, not an SF Symbol, so
/// it needs an explicit size. A normal SwiftUI image honors its frame, unlike
/// the menu-bar status item, which reads the intrinsic asset size instead.
private struct DownloadGlyphView: View {
    let glyph: DownloadIndicatorState.Glyph

    /// The width of the download mark.
    ///
    /// The mark is wider than tall, so this value sets the larger dimension.
    /// It matches the optical size of the SF Symbols beside it in the header,
    /// which the toolbar style draws at `BlattaMetric.Toolbar.glyphSize`.
    static let markWidth: CGFloat = 15

    /// The proportions of the artwork, from its 67 by 63 SVG viewBox.
    static let markHeight = markWidth * (63.0 / 67.0)

    var body: some View {
        switch glyph {
        case .downloadMark:
            Image("DownloadIcon")
                .resizable()
                .scaledToFit()
                .frame(width: Self.markWidth, height: Self.markHeight)
        case let .systemSymbol(name):
            Image(systemName: name)
        }
    }
}

/// The ring around the download mark.
///
/// A download without a reported size keeps the quiet track only, because a
/// value would be a guess.
private struct DownloadProgressRing: View {
    let fraction: Double?
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isTurning = false

    /// The ring clears the corners of the download mark.
    ///
    /// The mark is wider than tall, so its width sets the size. Its rounded
    /// corners reach about 9.5 points from the center at this width, and the
    /// inner edge of the ring stays outside that distance. The ring also keeps
    /// 2 points inside the 28 point control, so it cannot clip.
    private static let diameter = DownloadGlyphView.markWidth + 9
    private static let lineWidth: CGFloat = 1.5

    private var stroke: StrokeStyle {
        StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round)
    }

    var body: some View {
        ZStack {
            if isActive {
                Circle()
                    .strokeBorder(BlattaColor.Fill.control, lineWidth: Self.lineWidth)

                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.02, min(1, fraction)))
                        .stroke(Color.accentColor, style: stroke)
                        .padding(Self.lineWidth / 2)
                        .rotationEffect(.degrees(-90))
                } else {
                    indeterminateArc
                }
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }

    /// The mark for a download whose size the server did not report.
    ///
    /// A static track would read as a stalled transfer, so the arc turns
    /// instead. Reduce Motion keeps the same arc and stops the turn.
    @ViewBuilder
    private var indeterminateArc: some View {
        Circle()
            .trim(from: 0, to: DownloadIndicatorMotion.indeterminateArcFraction)
            .stroke(Color.accentColor, style: stroke)
            .padding(Self.lineWidth / 2)
            .rotationEffect(.degrees(isTurning ? 360 : 0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    .linear(duration: DownloadIndicatorMotion.indeterminateTurn.seconds)
                        .repeatForever(autoreverses: false)
                ) {
                    isTurning = true
                }
            }
            .onDisappear { isTurning = false }
    }
}

/// The list behind the download control.
///
/// A running download has a stop action. An ended download has a dismiss
/// action. Clicking a finished line shows its file in the Finder and keeps the
/// record. Clear All removes every ended record and keeps the running
/// downloads.
private struct DownloadListView: View {
    let serviceID: UUID?

    @Environment(AppState.self) private var appState

    /// The list stays short. Older files remain in the Downloads folder.
    private static let visibleRowLimit = 8

    private var items: [DownloadTracker.Item] {
        Array(appState.downloadTracker.items(for: serviceID).prefix(Self.visibleRowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                Text(DownloadIndicatorState.countText(0))
                    .font(.blattaBody)
                    .foregroundStyle(BlattaColor.Text.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(items) { item in
                    DownloadRow(item: item)
                }
            }

            if appState.downloadTracker.hasDismissibleItems(for: serviceID) {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                Button("Clear All") {
                    appState.downloadTracker.clear(for: serviceID)
                }
                .buttonStyle(.borderless)
                .font(.blattaBody)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .help("Remove every finished and failed download from this list")
                .accessibilityLabel("Clear the download list")
                .accessibilityIdentifier("web.downloads.clearAll")
            }
        }
        .padding(.vertical, 6)
        .frame(width: 272)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Downloads")
    }
}

/// One line of the download list.
///
/// A finished line is a button that shows its file in the Finder. Its dismiss
/// control is a sibling of that button, not a child of it, so the two hit
/// areas cannot overlap and each one takes its own click. The button comes
/// first in the view tree, so keyboard focus reaches the row before its
/// dismiss control.
///
/// An active line and a failed line have no row action. An active line has no
/// file yet, and a failed line has none at all. Neither one draws the hover
/// highlight, so a line without a target never looks clickable.
private struct DownloadRow: View {
    let item: DownloadTracker.Item

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var revealLabel: String { "Show \(item.filename) in Finder" }

    var body: some View {
        HStack(spacing: 8) {
            if item.state == .finished {
                Button {
                    appState.downloadTracker.revealInFinder(item)
                } label: {
                    // The shape covers the padded area, including the spacer,
                    // so the whole line answers a click.
                    rowContent.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { isHovering = $0 }
                .help(revealLabel)
                .accessibilityLabel(revealLabel)
                .accessibilityValue(statusText)
                .accessibilityIdentifier("web.downloads.reveal")
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.filename), \(statusText)")
            }

            trailingAction
                .padding(.trailing, 12)
        }
        .background(hoverHighlight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: isHovering)
    }

    private var rowContent: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.filename)
                    .font(.blattaBody)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.state.isActive, let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                Text(statusText)
                    .font(.blattaSidebarAccessory)
                    .foregroundStyle(BlattaColor.Text.secondary)
            }

            Spacer(minLength: 4)
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
    }

    /// The quiet fill that marks a line the user can click. Only a finished
    /// line can set `isHovering`, so no other line draws it.
    @ViewBuilder
    private var hoverHighlight: some View {
        if isHovering {
            RoundedRectangle(cornerRadius: BlattaRadius.control, style: .continuous)
                .fill(BlattaColor.Fill.rowHover)
                .padding(.horizontal, 6)
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if item.state.isActive {
            Button {
                appState.downloadTracker.cancel(id: item.id)
            } label: {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Stop download")
            .accessibilityLabel("Stop downloading \(item.filename)")
        } else {
            Button {
                appState.downloadTracker.dismiss(id: item.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help("Remove from this list")
            .accessibilityLabel("Remove \(item.filename) from the download list")
            .accessibilityIdentifier("web.downloads.dismiss")
        }
    }

    private var statusText: String {
        switch item.state {
        case .active:
            guard let fraction = item.fraction else { return "Downloading" }
            return "\(DownloadIndicatorState.percentText(fraction))% of \(sizeText)"
        case .finished:
            return "Finished"
        case .failed:
            return "Failed"
        }
    }

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: item.expectedBytes, countStyle: .file)
    }
}
