import SwiftUI
import SwiftData
import BlattaCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsedToggleChromeVisible = false
    /// The first-run welcome, once there is something to ask.
    @State private var pendingWelcome: FirstRunWelcome?
    @State private var collapsedChromeRevealTask: Task<Void, Never>?

    private var sidebarCollapsed: Bool { appState.sidebarCollapsed }

    var body: some View {
        @Bindable var state = appState
        @Bindable var recovery = appState.storeRecovery

        VStack(spacing: 0) {
            // All notices share one shape. `NoticeStrip` carries severity in the
            // icon and lower rule, plus the window-drag handle each notice needs.
            if let banner = recovery.banner {
                NoticeStrip(severity: .error) {
                    Text(banner.message)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    if let url = banner.folderURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .font(.caption)
                    }
                    if recovery.offer != nil {
                        Button("Review backups…") {
                            recovery.isShowingPicker = true
                        }
                        .font(.caption)
                    }
                    if banner.isDismissible {
                        Button {
                            recovery.dismissBanner()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                        .help("Dismiss")
                        .accessibilityLabel("Dismiss")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Warning: \(banner.message)")
            }

            if recovery.banner == nil, recovery.offer != nil {
                NoticeStrip(severity: .info) {
                    Text("Blatta has a backup with more of your workspaces and services than it can see now.")
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Review backups…") {
                        recovery.isShowingPicker = true
                    }
                    .font(.caption)
                    Button("Not now") { recovery.declineOffer() }
                        .font(.caption)
                }
                // No accessibility-label override here, unlike the warning
                // banner above: an explicit label replaces what `.combine`
                // would otherwise speak, and on this banner the buttons ARE
                // the point — overriding would drop "Review backups…" and
                // "Not now" from VoiceOver's reading, leaving them reachable
                // only as custom actions.
                .accessibilityElement(children: .combine)
            }

            if !appState.networkMonitor.isOnline {
                NoticeStrip(severity: .warning) {
                    Text("You're offline. Services won't load new content until your connection returns.")
                        .font(.caption)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Offline")
            }

            if let feedback = appState.mediaPermissions.microphoneActionFeedback {
                NoticeStrip(severity: .info, systemImage: "mic.slash.fill") {
                    Text(feedback)
                        .font(.caption)
                    Spacer()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(feedback)
            }

            mainLayout(
                spaceSelection: $state.selectedSpaceID,
                serviceSelection: $state.selectedServiceID
            )
            // A minimum height here makes the shell larger than a short
            // window. SwiftUI then centers and clips the complete shell, which
            // removes the header and bottom gutter. Let the web content and
            // sidebar scroll area absorb all vertical compression.
            .frame(minWidth: BlattaMetric.Window.minimumContentWidth)
            // Extend up into the (hidden) title-bar area so the tab bar sits at
            // the very top of the window; the traffic-light insets keep the
            // top-left clear.
            .ignoresSafeArea(.container, edges: .top)
        }
        // The top-bar layout puts draggable tabs in the title-bar drag band, so
        // turn the OS window drag off there (a click-drag on a tab would
        // otherwise move the window instead of reordering) and let the
        // WindowDragHandles move the window instead. The sidebar keeps the
        // normal title-bar drag.
        .background(
            WindowChromeConfigurator(
                isMovable: !appState.railLayout.servicesInBar,
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
                    try await Task.sleep(for: BlattaMotion.collapsedChromeDelay)
                } catch {
                    return
                }
                guard sidebarCollapsed else { return }
                withAnimation(.easeOut(duration: BlattaMotion.collapsedChromeFadeSeconds)) {
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
            if let spaceID = appState.selectedSpaceID {
                AddServiceSheet(spaceID: spaceID)
            } else {
                // Defensive: ⌘N is disabled without a selected space, but if the
                // sheet is ever presented in that state, give it a way out rather
                // than a blank, un-dismissable panel.
                VStack(spacing: 16) {
                    Text("Select or create a workspace before adding a service.")
                        .multilineTextAlignment(.center)
                    Button("OK") { state.showAddService = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(40)
                .frame(minWidth: 320)
            }
        }
        // The welcome waits for the launch read of the notification
        // permission. Deciding at first render would see `unknown` and offer
        // nothing, because Blatta cannot yet tell a refusal from a fresh install.
        .onChange(
            of: appState.notificationManager.authorizationState,
            initial: true
        ) { _, state in
            guard state != .unknown,
                  pendingWelcome == nil,
                  !appModel.hasSeenWelcome else { return }
            pendingWelcome = appModel.firstRunWelcome
        }
        .sheet(
            isPresented: Binding(
                get: { pendingWelcome != nil },
                set: { if !$0 { pendingWelcome = nil } }
            )
        ) {
            if let welcome = pendingWelcome {
                WelcomeSheet(welcome: welcome) {
                    appModel.markWelcomeSeen()
                    pendingWelcome = nil
                }
                .environment(appState)
                .environment(appModel)
            }
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
            Text("\(prompt.serviceLabel) shows you as away when its window isn't focused. Turn this on to stay active even while you work in other apps. You can change it later in the service's settings. It may hold back some of its notifications while Blatta is in the background.")
        }
        .overlay {
            if appState.isLocked {
                LockView()
                    .environment(appState)
                    .transition(.opacity)
            }
        }
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
                    .padding(.trailing, BlattaMetric.Sidebar.surfaceInset)
                    .padding(.bottom, BlattaMetric.Sidebar.surfaceInset)
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
                webContent
                    .padding(.horizontal, BlattaMetric.Sidebar.surfaceInset)
                    .padding(.bottom, BlattaMetric.Sidebar.surfaceInset)
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
                        .padding(.bottom, BlattaMetric.Sidebar.surfaceInset)
                }
                .padding(.trailing, BlattaMetric.Sidebar.surfaceInset)
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
                        .padding(.bottom, BlattaMetric.Sidebar.surfaceInset)
                }
                .padding(.trailing, BlattaMetric.Sidebar.surfaceInset)
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
                y: BlattaMetric.Toolbar.height / 2
            )
            .animation(
                reduceMotion ? nil : .smooth(duration: BlattaMotion.sidebarTransitionSeconds),
                value: presentation
            )
        }
    }

    /// What a bar beside the rail leaves clear at its leading end.
    ///
    /// The expanded rail is wider than the traffic lights and holds the collapse
    /// control itself, so its bar starts at its own edge. The collapsed rail is
    /// narrower than the lights, so the bar clears what the rail does not, the
    /// way the content header does in the one-rail layout.
    private var barLeadingInset: CGFloat {
        guard sidebarCollapsed else { return 0 }
        return BlattaMetric.Toolbar.collapsedLeadingInset(
            sidebarWidth: BlattaMetric.Sidebar.collapsedWidth(
                iconSize: appState.iconRailBaseSize
            )
        ) + BlattaMetric.Toolbar.sidebarToggleSize
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
            collapsedSidebarWidth: BlattaMetric.Sidebar.collapsedWidth(
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
            withAnimation(.smooth(duration: BlattaMotion.sidebarTransitionSeconds)) {
                appState.setSidebarCollapsed(collapsed)
            }
        }
    }
}

/// The source project that Blatta uses as its base.
enum UpstreamProjectLink {
    static let url = URL(string: "https://github.com/nicojan/Chorus")!
}

/// Opaque cover shown while the app is locked, hiding all content until the user
/// authenticates. Prompts for Touch ID on appear; the button retries.
struct LockView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Blatta is locked")
                .font(.title2)
                .bold()
            Button("Unlock") {
                appState.authenticate()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.authenticate()
        }
    }
}
