import SwiftUI
import SwiftData
import PaguroCore

struct ContentView: View {
    /// How long the passkey card stays on screen. It matches the capacity
    /// notice, which `HibernationScheduler` removes on the same schedule.
    private static let passkeyNoticeSeconds = 12

    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsedToggleChromeVisible = false
    @State private var collapsedChromeRevealTask: Task<Void, Never>?

    /// Every service of every workspace.
    ///
    /// First run is "no service anywhere", not "no service in this workspace".
    /// A workspace with nothing in it is still an empty window. The query also
    /// makes the swap to the shell follow the first service, without a second
    /// signal to keep in step.
    @Query private var allServices: [ServiceInstance]

    private var sidebarCollapsed: Bool { appState.sidebarCollapsed }

    /// What the window shows: the first-run home screen, or the shell.
    private var firstRun: FirstRunPresentation {
        appModel.firstRunPresentation(serviceCount: allServices.count)
    }

    var body: some View {
        @Bindable var state = appState
        @Bindable var recovery = appState.storeRecovery

        VStack(spacing: 0) {
            // Store failures and recovery outcomes keep their full-width strip.
            // The other notices float over the window content.
            if let banner = recovery.banner {
                NoticeStrip(severity: .error) {
                    Text(banner.message)
                        .font(.paguroCaption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    if let url = banner.folderURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .font(.paguroCaption)
                    }
                    if recovery.offer != nil {
                        Button("Review backups…") {
                            recovery.isShowingPicker = true
                        }
                        .font(.paguroCaption)
                    }
                    if banner.isDismissible {
                        Button {
                            recovery.dismissBanner()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .font(.paguroCaption)
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: \(banner.message)")
            }

            // The home screen replaces the complete shell, so no rail layout
            // has to answer for it: `mainLayout` builds every rail, and
            // `WebContentView` builds the content header inside it.
            Group {
                if firstRun.showsHome {
                    FirstRunHomeView(
                        setup: firstRun.setup,
                        allowsActions: firstRun.allowsActions
                    )
                    .transition(.opacity)
                } else {
                    mainLayout(
                        spaceSelection: $state.selectedSpaceID,
                        serviceSelection: $state.selectedServiceID
                    )
                    .transition(.opacity)
                }
            }
            // The first service ends first run. The swap is a change the user
            // did not see happen, so it fades; the rail adds a short slide in
            // from its own edge, which Reduce Motion removes.
            .animation(
                .easeInOut(duration: PaguroMotion.firstRunSwapSeconds),
                value: firstRun.showsHome
            )
            // A minimum height here makes the shell larger than a short
            // window. SwiftUI then centers and clips the complete shell, which
            // removes the header and bottom gutter. Let the web content and
            // sidebar scroll area absorb all vertical compression.
            .frame(minWidth: PaguroMetric.Window.minimumContentWidth)
            // Extend up into the (hidden) title-bar area so the tab bar sits at
            // the very top of the window; the traffic-light insets keep the
            // top-left clear.
            .ignoresSafeArea(.container, edges: .top)
            // The mark that reports a download start travels from the web
            // content into the header download control. Its overlay sits here,
            // because this is the first level that holds both of them, in every
            // rail layout. The two frames arrive as anchors from the views that
            // own them, so nothing here knows where the control is.
            .overlayPreferenceValue(DownloadFlightAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    DownloadStartFlightOverlay(
                        controlFrame: anchors.control.map { proxy[$0] },
                        contentFrame: anchors.content.map { proxy[$0] }
                    )
                }
            }
            // The notice cards float over whatever the window shows: a service
            // page, the two empty states, and the first-run screen. The host
            // sits here, at the one level that holds all of them, so a card no
            // longer needs a web view on screen. It stays inside this stack, so
            // the lock overlay draws above it and the locked window takes its
            // clicks and its place in the accessibility tree away.
            .overlay(alignment: .topTrailing) { floatingNoticeHost }
        }
        // Keep service views mounted, but hide their content before revealing
        // the behind-window glass on the lock screen.
        .opacity(appState.isLocked ? 0 : 1)
        .allowsHitTesting(!appState.isLocked)
        .disabled(appState.isLocked)
        .accessibilityHidden(appState.isLocked)
        .animation(nil, value: appState.isLocked)
        // The top-bar layout puts draggable tabs in the title-bar drag band, so
        // turn the OS window drag off there (a click-drag on a tab would
        // otherwise move the window instead of reordering) and let the
        // WindowDragHandles move the window instead. The sidebar keeps the
        // normal title-bar drag.
        //
        // The first-run home screen has no tabs in the band in any layout, so
        // it keeps the normal drag. Its own glass handle carries the rest of
        // the window.
        .background(
            WindowChromeConfigurator(
                isMovable: firstRun.showsHome || !appState.railLayout.servicesInBar,
                glassStyle: appState.liquidGlassStyle,
                glassIntensity: appState.liquidGlassIntensity
            )
        )
        .containerBackground(.clear, for: .window)
        .onAppear {
            collapsedToggleChromeVisible = sidebarCollapsed
        }
        .onChange(of: sidebarCollapsed) { _, isCollapsed in
            collapsedChromeRevealTask?.cancel()
            collapsedChromeRevealTask = nil

            guard isCollapsed else {
                // Already cleared by `toggleSidebar` before the movement
                // started. This covers a change from anywhere else, and it
                // leaves the animation of that change out of the removal.
                var immediate = Transaction()
                immediate.disablesAnimations = true
                withTransaction(immediate) {
                    collapsedToggleChromeVisible = false
                }
                return
            }
            guard !reduceMotion else {
                collapsedToggleChromeVisible = true
                return
            }

            // The button has one identity. Add its compact circle after the
            // movement duration plus one small render margin, so the circle
            // cannot travel across the window from the expanded rail.
            collapsedToggleChromeVisible = false
            collapsedChromeRevealTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: PaguroMotion.collapsedChromeDelay)
                } catch {
                    return
                }
                guard sidebarCollapsed else { return }
                withAnimation(.easeOut(duration: PaguroMotion.collapsedChromeFadeSeconds)) {
                    collapsedToggleChromeVisible = true
                }
            }
        }
        .onDisappear {
            collapsedChromeRevealTask?.cancel()
            collapsedChromeRevealTask = nil
        }
        // The macOS notification permission is NOT requested here. This view
        // never appears for a login-item launch, which closes the main window,
        // nor in "Menu bar only" presence mode — and the request would then
        // never happen at all. NotificationRuntime.start() owns it instead: it
        // runs from applicationDidFinishLaunching for every launch.
        .onChange(of: appState.selectedSpaceID) { _, newSpaceID in
            if let spaceID = newSpaceID {
                appState.preloadServicesForSpace(spaceID)
                // A workspace opens on the service it was left on. A serviceID
                // set in this same render tick wins: QuickSwitcher and the
                // menu-bar handler write a spaceID and a serviceID together,
                // and this must not answer for the service they chose.
                appState.selectedServiceID = appState.serviceToOpen(
                    in: spaceID,
                    currentServiceID: appState.selectedServiceID
                )
            }
        }
        .onChange(of: appState.selectedServiceID) { _, newServiceID in
            guard let spaceID = appState.selectedSpaceID, let newServiceID else { return }
            appState.rememberSelection(serviceID: newServiceID, in: spaceID)
        }
        .sheet(isPresented: $state.showAddService) {
            AddServiceSheet(spaceID: appState.selectedSpaceID)
        }
        .sheet(isPresented: $state.showAddSpace) {
            SpaceEditorSheet(
                editingSpace: nil,
                selectedSpaceID: $state.selectedSpaceID
            )
        }
        .sheet(isPresented: $state.showQuickSwitcher) {
            QuickSwitcherView()
                .environment(appState)
                .modelContainer(appState.modelContainer)
        }
        .sheet(isPresented: $recovery.isShowingPicker, onDismiss: {
            // Only quits when the user actually picked a backup. It has to
            // happen here rather than in the button: a quit requested while
            // this sheet is still attached is refused and dropped.
            recovery.quitForScheduledRestore()
        }) {
            StoreRecoveryView()
        }
        .alert(
            appState.mediaPermissions.pendingRequest?.title ?? "",
            isPresented: Binding(
                get: { appState.mediaPermissions.pendingRequest != nil },
                set: { _ in }   // dismissal always routes through a button below
            ),
            presenting: appState.mediaPermissions.pendingRequest
        ) { request in
            Button("Allow") { appState.mediaPermissions.answerRequest(request.id, allow: true) }
            Button("Don't Allow", role: .cancel) {
                appState.mediaPermissions.answerRequest(request.id, allow: false)
            }
        } message: { request in
            Text(request.message)
        }
        .alert(
            "Always appear active in \(appState.mediaPermissions.presencePrompt?.serviceLabel ?? "")?",
            isPresented: Binding(
                get: { appState.mediaPermissions.presencePrompt != nil },
                set: { _ in }   // dismissal always routes through a button below
            ),
            presenting: appState.mediaPermissions.presencePrompt
        ) { prompt in
            Button("Always Appear Active") {
                appState.mediaPermissions.answerPresencePrompt(prompt.id, enable: true)
            }
            Button("Not Now", role: .cancel) {
                appState.mediaPermissions.answerPresencePrompt(prompt.id, enable: false)
            }
        } message: { prompt in
            Text("\(prompt.serviceLabel) shows you as away when its window isn't focused. Turn this on to stay active even while you work in other apps. You can change it later in the service's settings. It may hold back some of its notifications while Paguro is in the background.")
        }
        .overlay {
            if appState.isLocked {
                LockView(
                    glassIntensity: appState.liquidGlassIntensity,
                    authenticate: appState.authenticate
                )
                .ignoresSafeArea()
                .transition(.identity)
            }
        }
    }

    // MARK: - Floating notices

    /// The window-level host for the notice cards.
    ///
    /// The reader gives the stack the width it may use. The host draws nothing
    /// of its own, so every click outside a card reaches the page, the rail, or
    /// the header below it.
    private var floatingNoticeHost: some View {
        GeometryReader { proxy in
            FloatingNoticeStack(
                notices: floatingNotices,
                availableWidth: proxy.size.width,
                topInset: CGFloat(
                    FloatingNoticeLayout.topInset(
                        chromeHeight: Double(chromeHeightAboveContent),
                        findBarIsVisible: !firstRun.showsHome && appState.selectedServiceID != nil && appState.findInPageVisible
                    )
                )
            )
        }
        .padding(.trailing, contentTrailingInset)
    }

    /// What the window draws above the content at the top trailing corner.
    ///
    /// The stack starts below it, so a card keeps the place it has over the web
    /// content in every layout. The sidebar layout draws the content header
    /// there, and the three layouts with a rail along the top draw a bar of the
    /// same height. The first-run screen draws neither, so its cards clear the
    /// title-bar band alone.
    private var chromeHeightAboveContent: CGFloat {
        guard !firstRun.showsHome else {
            return CGFloat(FloatingNoticeLayout.titleBarBand)
        }
        switch appState.railLayout {
        case .sidebar:
            return PaguroMetric.Toolbar.height
        case .topBars, .workspacesLeft, .servicesLeft:
            return PaguroMetric.Sidebar.topBarHeight
        }
    }

    /// The window gutter that every rail layout keeps beside its content. The
    /// first-run screen fills the window, so it has none.
    private var contentTrailingInset: CGFloat {
        firstRun.showsHome ? 0 : PaguroMetric.Sidebar.surfaceInset
    }

    /// Every notice that the window shows as a card.
    ///
    /// The stack gives the top place to the card that arrived last. Cards that
    /// arrive in one render take their places from this order, so the last entry
    /// here is the top one.
    ///
    /// A locked window shows none of them: the lock screen draws over the host,
    /// and an empty list also keeps the VoiceOver announcement of a card that
    /// arrives while the window is locked. The cards return with the content
    /// when the user unlocks Paguro.
    private var floatingNotices: [FloatingNotice] {
        guard !appState.isLocked else { return [] }

        let recovery = appState.storeRecovery
        var notices: [FloatingNotice] = []

        // The pool's own size limit can release a background service while
        // idle hibernation is off. Say so one time, so the user does not read
        // the reload as a fault. `HibernationScheduler` owns its 12 seconds.
        if let message = appState.hibernationScheduler.capacityEvictionNotice {
            notices.append(
                FloatingNotice(
                    id: .capacityEviction,
                    systemImage: "moon.zzz.fill",
                    title: CapacityEvictionNotice.title,
                    message: message,
                    dismiss: {
                        appState.hibernationScheduler.dismissCapacityEvictionNotice()
                    }
                )
            )
        }

        // WKWebView cannot use passkeys for sign-in, so warn the user the first
        // time each service is opened.
        if let serviceID = appState.passkeyNoticeServiceID {
            notices.append(
                FloatingNotice(
                    id: .passkeyUnavailable(serviceID),
                    systemImage: "person.badge.key.fill",
                    title: "Passkeys are not available",
                    message: AppCapabilities.passkeyUnavailableBanner,
                    dismissal: .transient(seconds: Self.passkeyNoticeSeconds),
                    dismiss: { appState.dismissPasskeyNotice() }
                )
            )
        }

        // The store error states the same problem and carries the same picker,
        // so the offer waits for the strip to go.
        if recovery.banner == nil, recovery.offer != nil {
            notices.append(
                FloatingNotice(
                    id: .backupOffer,
                    systemImage: "clock.arrow.circlepath",
                    title: "A backup has more of your data",
                    message: "Paguro has a backup with more of your workspaces and services than it can see now.",
                    actions: [
                        FloatingNoticeAction(title: "Not now") { recovery.declineOffer() },
                        FloatingNoticeAction(title: "Review backups…") {
                            recovery.isShowingPicker = true
                        }
                    ],
                    // The offer asks a question, so it waits for the answer. The
                    // close button and a drag both mean Not now.
                    dismissal: .untilActed,
                    dismiss: { recovery.declineOffer() }
                )
            )
        }

        if appState.networkMonitor.showsOfflineNotice {
            notices.append(
                FloatingNotice(
                    id: .offline,
                    systemImage: "wifi.slash",
                    severity: .warning,
                    title: "You're offline",
                    message: "Services won't load new content until your connection returns.",
                    dismissal: .untilActed,
                    dismiss: { appState.networkMonitor.dismissOfflineNotice() }
                )
            )
        }

        // The coordinator writes the sentence and clears it after two seconds.
        // The sentence is the complete notice, so the card carries no second
        // line under it.
        if let feedback = appState.mediaPermissions.microphoneActionFeedback {
            notices.append(
                FloatingNotice(
                    id: .microphoneFeedback,
                    systemImage: "mic.slash.fill",
                    title: feedback,
                    dismiss: { appState.mediaPermissions.clearMicrophoneActionFeedback() }
                )
            )
        }

        return notices
    }

    /// Arranges the rail and the web content per the chosen layout: the rail
    /// down the left, or along the top as a bar of tabs.
    ///
    /// The single rail supports two arrangements. The current space is the rail
    /// header instead of having a separate rail.
    @ViewBuilder
    private func mainLayout(
        spaceSelection: Binding<UUID?>,
        serviceSelection: Binding<UUID?>
    ) -> some View {
        // The title bar is hidden, so content runs to the top edge. Reserve the
        // top-left for the traffic lights: push the horizontal rail clear of the
        // complete 79 point native button group and add an 8 point gap.
        let lightsWidth: CGFloat = 80

        switch appState.railLayout {
        case .sidebar:
            sideRailLayout {
                webContent
                    .padding(.trailing, PaguroMetric.Sidebar.surfaceInset)
                    .padding(.bottom, PaguroMetric.Sidebar.surfaceInset)
            } sideRail: {
                rail(
                    axis: .vertical,
                    spaceSelection: spaceSelection,
                    serviceSelection: serviceSelection,
                    sidebarPresentation: sidebarCollapsed ? .collapsed : .expanded
                )
            }
        case .topBars:
            VStack(spacing: 0) {
                rail(axis: .horizontal, spaceSelection: spaceSelection, serviceSelection: serviceSelection, contentInset: lightsWidth)
                    // A tab tooltip hangs below the bar, over the web content.
                    .zIndex(1)
                    .transition(railEntryTransition(from: .top))
                webContent
                    .padding(.horizontal, PaguroMetric.Sidebar.surfaceInset)
                    .padding(.bottom, PaguroMetric.Sidebar.surfaceInset)
            }

        case .workspacesLeft:
            sideRailLayout {
                VStack(spacing: 0) {
                    rail(
                        axis: .horizontal,
                        spaceSelection: spaceSelection,
                        serviceSelection: serviceSelection,
                        contentInset: barLeadingInset
                    )
                    // A tab tooltip hangs below the bar, over the web content.
                    .zIndex(1)

                    webContent
                        .padding(.bottom, PaguroMetric.Sidebar.surfaceInset)
                }
                .padding(.trailing, PaguroMetric.Sidebar.surfaceInset)
            } sideRail: {
                WorkspaceRailView(
                    selectedSpaceID: spaceSelection,
                    sidebarPresentation: sidebarCollapsed ? .collapsed : .expanded
                )
            }

        case .servicesLeft:
            sideRailLayout {
                VStack(spacing: 0) {
                    WorkspaceBarView(
                        selectedSpaceID: spaceSelection,
                        contentInset: barLeadingInset
                    )

                    webContent
                        .padding(.bottom, PaguroMetric.Sidebar.surfaceInset)
                }
                .padding(.trailing, PaguroMetric.Sidebar.surfaceInset)
            } sideRail: {
                rail(
                    axis: .vertical,
                    spaceSelection: spaceSelection,
                    serviceSelection: serviceSelection,
                    sidebarPresentation: sidebarCollapsed ? .collapsed : .expanded
                )
            }
        }
    }

    /// The frame of every layout with a rail down the left.
    ///
    /// The rail owns the complete left column, and the content beside it starts
    /// at the rail's trailing edge. A bar in that content therefore moves with
    /// the rail, which is the whole point of being able to collapse it.
    @ViewBuilder
    private func sideRailLayout<Content: View, SideRail: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder sideRail: () -> SideRail
    ) -> some View {
        let presentation: SidebarPresentation = sidebarCollapsed ? .collapsed : .expanded

        HStack(spacing: 0) {
            sideRail()
                .zIndex(1)
                .transition(railEntryTransition(from: .leading))
            content()
        }
        .overlay(alignment: .topLeading) {
            // Keep one button alive for both sidebar states. The stock
            // NavigationSplitView toggle uses the same ownership model, so
            // its control follows the moving column edge instead of being
            // removed from one header and inserted into another.
            SidebarToggleButton(
                isCollapsed: sidebarCollapsed,
                showsCollapsedChrome: collapsedToggleChromeVisible,
                action: toggleSidebar
            )
            .position(
                x: presentation.toggleCenterX,
                y: PaguroMetric.Toolbar.height / 2
            )
            .animation(
                reduceMotion ? nil : .smooth(duration: PaguroMotion.sidebarTransitionSeconds),
                value: presentation
            )
        }
    }

    /// How a rail arrives when the first service ends first run.
    ///
    /// The rail slides in from the edge it lives on, under the fade of the
    /// swap. Reduce Motion keeps the fade alone, because the movement carries
    /// no information that the fade does not already give.
    private func railEntryTransition(from edge: Edge) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .move(edge: edge).combined(with: .opacity)
    }

    /// What a bar beside the rail leaves clear at its leading end.
    ///
    /// The expanded rail is wider than the traffic lights and holds the collapse
    /// control itself, so its bar starts at its own edge. The collapsed rail is
    /// narrower than the lights, so the bar clears what the rail does not, the
    /// way the content header does in the one-rail layout.
    private var barLeadingInset: CGFloat {
        guard sidebarCollapsed else { return 0 }
        return PaguroMetric.Toolbar.collapsedLeadingInset(
            sidebarWidth: PaguroMetric.Sidebar.collapsedWidth(
                iconSize: appState.iconRailBaseSize
            )
        ) + PaguroMetric.Toolbar.sidebarToggleSize
    }

    private func rail(
        axis: Axis,
        spaceSelection: Binding<UUID?>,
        serviceSelection: Binding<UUID?>,
        contentInset: CGFloat = 0,
        sidebarPresentation: SidebarPresentation = .expanded
    ) -> some View {
        UnifiedRailView(
            selectedSpaceID: spaceSelection,
            selectedServiceID: serviceSelection,
            axis: axis,
            sidebarPresentation: sidebarPresentation,
            contentInset: contentInset
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Workspaces and services")
    }

    private var webContent: some View {
        WebContentView(
            selectedServiceID: appState.selectedServiceID,
            sidebarIsCollapsed: sidebarCollapsed,
            collapsedSidebarWidth: PaguroMetric.Sidebar.collapsedWidth(
                iconSize: appState.iconRailBaseSize
            )
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Web content")
    }

    private func toggleSidebar() {
        let collapsed = !sidebarCollapsed
        if !collapsed {
            // Take the compact circle off the control before the control
            // starts travelling. Left to the change below, the circle is
            // removed inside that animation: it does not travel with the
            // control, so it draws one frame at the far end of the movement
            // and fades from there.
            collapsedChromeRevealTask?.cancel()
            collapsedChromeRevealTask = nil
            collapsedToggleChromeVisible = false
        }
        if reduceMotion {
            appState.setSidebarCollapsed(collapsed)
        } else {
            withAnimation(.smooth(duration: PaguroMotion.sidebarTransitionSeconds)) {
                appState.setSidebarCollapsed(collapsed)
            }
        }
    }
}

/// The source project that Paguro uses as its base.
enum UpstreamProjectLink {
    static let url = URL(string: "https://github.com/nicojan/Chorus")!
}

/// Keeps content hidden until the user chooses Unlock and authenticates.
struct LockView: View {
    var glassIntensity: Double = 1
    let authenticate: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Paguro is locked")
                .font(.title2)
                .bold()
            Button("Unlock", action: authenticate)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaguroColor.shellCanvas(intensity: glassIntensity))
    }
}
