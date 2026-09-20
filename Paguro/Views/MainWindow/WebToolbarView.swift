import PaguroCore
import SwiftUI

/// The native header above web content in the left-sidebar layout.
struct WebContentHeader: View {
    let webViewState: WebViewState
    var title: String
    var reservesSidebarToggleSpace = false
    var sidebarToggleLeadingInset = PaguroMetric.Toolbar.collapsedLeadingInset
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            if reservesSidebarToggleSpace {
                Color.clear
                    .frame(
                        width: PaguroMetric.Toolbar.sidebarToggleSize,
                        height: PaguroMetric.Toolbar.sidebarToggleSize
                    )
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.paguroToolbarTitle)
                .foregroundStyle(PaguroColor.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 24)

            WebContentActions(webViewState: webViewState)
        }
        .padding(
            .leading,
            reservesSidebarToggleSpace
                ? sidebarToggleLeadingInset
                : PaguroMetric.Toolbar.horizontalInset
        )
        .padding(.trailing, PaguroMetric.Toolbar.horizontalInset)
        .frame(height: PaguroMetric.Toolbar.height)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .background(WindowDragHandle())
        .background(
            PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity)
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
        .buttonStyle(PaguroSidebarButtonStyle(isCollapsed: showsCollapsedChrome))
        .keyboardShortcut("s", modifiers: [.command, .control])
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityIdentifier("sidebar.toggle")
    }
}

/// The persistent controls for the active web service.
///
/// The service page owns its own layout and appearance. Paguro keeps only the
/// controls that a page cannot supply: the download report, page history,
/// reload, and the global notification mute. They sit at the trailing end of
/// the header in that order.
struct WebContentActions: View {
    let webViewState: WebViewState

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The indicator state for every service.
    ///
    /// The download control is the one global control in this group. A user
    /// expects a browser download center, so a switch of service must not hide a
    /// running transfer or the route back to a finished file.
    private var downloadState: DownloadIndicatorState {
        appState.downloadTracker.state()
    }

    var body: some View {
        HStack(spacing: 6) {
            if downloadState.isVisible {
                DownloadIndicatorButton(
                    state: downloadState,
                    glassIntensity: appState.liquidGlassIntensity
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
            .buttonStyle(PaguroToolbarButtonStyle())
            .toolbarControlSurface(intensity: appState.liquidGlassIntensity)
            .disabled(appState.showAddService || !webViewState.canGoBack)
            .help("Back")
            .accessibilityLabel("Go back")
            .accessibilityIdentifier("web.goBack")

            Button {
                appState.goForwardInActiveService()
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(PaguroToolbarButtonStyle())
            .toolbarControlSurface(intensity: appState.liquidGlassIntensity)
            .disabled(appState.showAddService || !webViewState.canGoForward)
            .help("Forward")
            .accessibilityLabel("Go forward")
            .accessibilityIdentifier("web.goForward")

            Button {
                if webViewState.isLoading {
                    webViewState.webView?.stopLoading()
                } else {
                    appState.reloadActiveService()
                }
            } label: {
                Image(systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(PaguroToolbarButtonStyle())
            .toolbarControlSurface(intensity: appState.liquidGlassIntensity)
            .disabled(appState.showAddService || webViewState.webView == nil)
            .help(webViewState.isLoading ? "Stop" : "Reload")
            .accessibilityLabel(webViewState.isLoading ? "Stop loading" : "Reload page")

            Button {
                appState.doNotDisturb.toggle()
            } label: {
                Image(systemName: appState.doNotDisturb ? "bell.slash" : "bell")
            }
            .buttonStyle(PaguroToolbarButtonStyle(isSelected: appState.doNotDisturb))
            .toolbarControlSurface(intensity: appState.liquidGlassIntensity)
            .help(appState.doNotDisturb ? "Unmute notifications and media" : "Mute notifications and media")
            .accessibilityLabel(
                appState.doNotDisturb
                    ? "Unmute notifications and media for all services"
                    : "Mute notifications and media for all services"
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
}

/// The header download control.
///
/// It appears as soon as the app has one download record and stays until the
/// user removes the last one. This keeps the route to a finished file available
/// after the transfer ends.
///
/// The control is global. It counts the downloads of every service, so its ring,
/// its badge, and its list survive a switch of service.
struct DownloadIndicatorButton: View {
    let state: DownloadIndicatorState
    let glassIntensity: Double

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsList = false

    /// Drives the single pulse that settles a completed download.
    @State private var completionScale: CGFloat = 1
    /// The quieter Reduce Motion form of that pulse.
    @State private var completionOpacity: Double = 1
    /// When this control entered the header.
    ///
    /// The control is created as it becomes visible, so its own appearance is
    /// the moment its entry movement starts.
    @State private var enteredAt: Date?

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
        .buttonStyle(PaguroToolbarButtonStyle(isSelected: showsList))
        .toolbarControlSurface(intensity: glassIntensity)
        .scaleEffect(completionScale)
        .opacity(completionOpacity)
        // The mark that reports a download start lands here, so the window
        // root reads this frame instead of guessing the control position.
        .downloadFlightDestination()
        .help(state.helpText)
        .accessibilityLabel(state.accessibilityLabel)
        .accessibilityIdentifier("web.downloads")
        // The list opens on a click only. A finished download must not steal
        // the pointer or the keyboard from whatever the user is doing.
        .popover(isPresented: $showsList, arrowEdge: .bottom) {
            DownloadListView()
        }
        .onChange(of: state.showsRing) { wasRinging, isRinging in
            guard wasRinging, !isRinging, state.isVisible else { return }
            pulse()
        }
        .onAppear { enteredAt = Date() }
        // A flying mark has reached this control. Reduce Motion sends no mark,
        // and this change is then the complete cue.
        .onChange(of: appState.downloadFlights.arrivalTick) { _, _ in
            land()
        }
        // Opening the list is the user seeing it, so the badge clears here
        // rather than waiting out its window. The list holds every service, so
        // the acknowledgement covers every service too. The control itself stays.
        .onChange(of: showsList) { _, isOpen in
            guard isOpen else { return }
            appState.downloadTracker.acknowledgeAll()
        }
    }

    /// Answers a mark that has arrived from the web content.
    ///
    /// The handoff must read as one movement. A control that entered the header
    /// a moment ago is already growing into place, and that growth is the
    /// landing, so the pulse stays out of its way. This happens for the first
    /// download of a service, where the control appears as the mark arrives.
    private func land() {
        guard state.isVisible else { return }
        guard let enteredAt,
              Date().timeIntervalSince(enteredAt)
                  >= DownloadIndicatorMotion.entryDuration.seconds
        else { return }
        pulse()
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
/// follows the rail badge shape, and it uses the accent color rather than the
/// unread red, because a download is not a message that waits for a reply.
private struct DownloadCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.paguroCaption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 3)
            .frame(minWidth: 15, minHeight: 15)
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
///
/// The mark that flies into the control at the start of a download draws the
/// same view, so the two marks cannot differ.
struct DownloadGlyphView: View {
    let glyph: DownloadIndicatorState.Glyph

    /// The width of the download mark.
    ///
    /// The mark is wider than tall, so this value sets the larger dimension.
    /// It matches the optical size of the SF Symbols beside it in the header,
    /// which the toolbar style draws at `PaguroMetric.Toolbar.glyphSize`.
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
                    .strokeBorder(PaguroColor.Fill.control, lineWidth: Self.lineWidth)

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
/// The list holds the downloads of every service, newest first, so it is one
/// download center for the app. Each line names the service that started it.
///
/// A running download has a stop action. An ended download has a dismiss
/// action. Clicking a finished line shows its file in the Finder and keeps the
/// record. Clear All removes every ended record and keeps the running
/// downloads.
private struct DownloadListView: View {
    @Environment(AppState.self) private var appState

    /// The list stays short. Older files remain in the Downloads folder.
    private static let visibleRowLimit = 8

    private var items: [DownloadTracker.Item] {
        Array(appState.downloadTracker.recentItems.prefix(Self.visibleRowLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if items.isEmpty {
                Text(DownloadIndicatorState.countText(0))
                    .font(.paguroBody)
                    .foregroundStyle(PaguroColor.Text.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ForEach(items) { item in
                    DownloadRow(item: item)
                }
            }

            if appState.downloadTracker.hasDismissibleItems {
                Divider()
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                // The command row of the list. It uses the menu row style, so
                // the pointer and the keyboard highlight it like a menu item.
                Button("Clear All") {
                    appState.downloadTracker.clear()
                }
                .buttonStyle(PaguroMenuRowButtonStyle())
                .padding(.top, 2)
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
///
/// The list holds every service, so each line names its own source on its
/// secondary line: the saved icon of the service and the name the record
/// captured. A secondary click offers a route to that service.
private struct DownloadRow: View {
    let item: DownloadTracker.Item

    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    /// The source icon matches the height of the secondary line beside it.
    private static let sourceIconSize: CGFloat = 12

    private var revealLabel: String { "Show \(item.filename) in Finder" }

    /// The service that started this download, or nil when it left the
    /// workspace. A removed service keeps its record: only its icon is gone.
    private var sourceService: ServiceInstance? {
        item.serviceID.flatMap { appState.service(id: $0) }
    }

    private var source: DownloadSource {
        DownloadSource.resolve(
            serviceID: item.serviceID,
            label: item.serviceLabel,
            serviceExists: sourceService != nil
        )
    }

    /// The line, with the route to its source service on a secondary click.
    ///
    /// The view sends the selection as an intent to `AppState`, the same route
    /// the rail uses, so the list keeps no selection rule of its own. A record of
    /// a service that left the workspace carries no menu at all, instead of an
    /// empty one: there is nothing left to show.
    var body: some View {
        if let sourceService {
            line.contextMenu {
                Button("Go to \(source.label ?? sourceService.label)") {
                    appState.selectService(id: sourceService.id)
                }
            }
        } else {
            line
        }
    }

    private var line: some View {
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
                .accessibilityValue(spokenStatus)
                .accessibilityIdentifier("web.downloads.reveal")
            } else {
                rowContent
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.filename), \(spokenStatus)")
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
                    .font(.paguroBody)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.state.isActive, let fraction = item.fraction {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                }

                secondaryLine
            }

            Spacer(minLength: 4)
        }
        .padding(.leading, 12)
        .padding(.vertical, 6)
    }

    /// The source of the download and its state, on one quiet line.
    ///
    /// The two facts share a line, so a source costs the row no height. A
    /// download that Paguro cannot attribute shows the state alone.
    private var secondaryLine: some View {
        HStack(spacing: 4) {
            if let label = source.label {
                sourceGlyph
                Text(label)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: "·")
            }

            Text(statusText)
                .lineLimit(1)
        }
        .font(.paguroSidebarAccessory)
        .foregroundStyle(PaguroColor.Text.secondary)
        // The row's own label speaks the source and the state together.
        .accessibilityHidden(true)
    }

    /// The saved icon of the source service.
    ///
    /// It resolves through `ServiceIconSquare`, the one icon source that the
    /// rail and the notification attachment also use, so a download row cannot
    /// show a different icon from the rest of the app. A service that left the
    /// workspace has no icon to resolve, so its row keeps a generic mark beside
    /// the name that the record captured.
    @ViewBuilder
    private var sourceGlyph: some View {
        if source.drawsServiceIcon, let sourceService {
            ServiceIconSquare(
                instance: sourceService,
                size: Self.sourceIconSize,
                cornerRadius: 3
            )
        } else {
            Image(systemName: "globe")
        }
    }

    /// The spoken state of this row, with its source service in front of it.
    private var spokenStatus: String {
        guard let phrase = source.spokenPhrase else { return statusText }
        return "\(phrase), \(statusText)"
    }

    /// The quiet fill that marks a line the user can click. Only a finished
    /// line can set `isHovering`, so no other line draws it.
    @ViewBuilder
    private var hoverHighlight: some View {
        if isHovering {
            RoundedRectangle(cornerRadius: PaguroRadius.control, style: .continuous)
                .fill(PaguroColor.Fill.rowHover)
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
