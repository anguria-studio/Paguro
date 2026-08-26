import SwiftUI
import SwiftData
import AtollCore

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @SceneStorage("Atoll.sidebarCollapsed") private var sidebarCollapsed = false
    @State private var collapsedToggleChromeVisible = false
    @State private var collapsedChromeRevealTask: Task<Void, Never>?

    var body: some View {
        @Bindable var state = appState

        VStack(spacing: 0) {
            // Three notices, one shape. They used to be two raw SwiftUI yellows
            // and a solid red bar, which read as three unrelated designs stacked
            // on each other. `NoticeStrip` carries the severity in the icon and
            // the rule under the strip, and carries the window-drag handle every
            // one of them needs.
            if let error = appState.storeError {
                NoticeStrip(severity: .error) {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    Spacer()
                    if let url = appState.storeFileURL {
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .font(.caption)
                    }
                    if appState.storeRecoveryOffer != nil {
                        Button("Review backups…") {
                            appState.isShowingStoreRecovery = true
                        }
                        .font(.caption)
                    }
                    if appState.storeErrorDismissible {
                        Button {
                            appState.dismissStoreBanner()
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
                .accessibilityLabel("Warning: \(error)")
            }

            if appState.storeError == nil, appState.storeRecoveryOffer != nil {
                NoticeStrip(severity: .info) {
                    Text("Atoll has a backup with more of your spaces and services than it can see now.")
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Review backups…") { appState.isShowingStoreRecovery = true }
                        .font(.caption)
                    Button("Not now") { appState.declineStoreRecovery() }
                        .font(.caption)
                }
                // No .accessibilityLabel override here, unlike the storeError
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
            .frame(minWidth: 800)
            // Extend up into the (hidden) title-bar area so the tab bar sits at
            // the very top of the window; the traffic-light insets keep the
            // top-left clear.
            .ignoresSafeArea(.container, edges: .top)
        }
        // The top-bar and hybrid layouts put draggable tabs in the title-bar
        // drag band, so turn the OS window drag off there (a click-drag on a tab
        // would otherwise move the window instead of reordering) and let the
        // WindowDragHandles move the window instead. The sidebar keeps the
        // normal title-bar drag.
        .background(
            WindowChromeConfigurator(
                isMovable: appState.railLayout == .sidebar,
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
                collapsedToggleChromeVisible = false
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
                    try await Task.sleep(for: AtollMotion.collapsedChromeDelay)
                } catch {
                    return
                }
                guard sidebarCollapsed else { return }
                withAnimation(.easeOut(duration: AtollMotion.collapsedChromeFadeSeconds)) {
                    collapsedToggleChromeVisible = true
                }
            }
        }
        .onDisappear {
            collapsedChromeRevealTask?.cancel()
            collapsedChromeRevealTask = nil
        }
        // Ask for macOS notification permission here, not in AppState.init:
        // requesting during App.init (before the scene exists) can fail with
        // "Notifications are not allowed for this application" and leave the app
        // unregistered. The root view's .task runs after launch, when the
        // request lands correctly. Idempotent, so re-running is harmless.
        .task {
            appState.notificationManager.requestAuthorization()
        }
        .onChange(of: appState.selectedSpaceID) { _, newSpaceID in
            if let spaceID = newSpaceID {
                appState.preloadServicesForSpace(spaceID)
                // Don't overwrite a serviceID that was set in the same
                // render tick by QuickSwitcher or the menu-bar handler
                // (they write spaceID + serviceID together). Only fall
                // back to selectFirstService when the current selection
                // isn't valid for the new space — e.g., the user clicked
                // a space chip in SpaceStripView.
                let validIDs = Set(appState.servicesForSpace(spaceID).map(\.id))
                if let currentID = appState.selectedServiceID, validIDs.contains(currentID) {
                    return
                }
                selectFirstService(in: spaceID)
            }
        }
        .sheet(isPresented: $state.showAddService) {
            if let spaceID = appState.selectedSpaceID {
                AddServiceSheet(spaceID: spaceID)
            } else {
                // Defensive: ⌘N is disabled without a selected space, but if the
                // sheet is ever presented in that state, give it a way out rather
                // than a blank, un-dismissable panel.
                VStack(spacing: 16) {
                    Text("Select or create a space before adding a service.")
                        .multilineTextAlignment(.center)
                    Button("OK") { state.showAddService = false }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(40)
                .frame(minWidth: 320)
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
        .sheet(isPresented: $state.isShowingStoreRecovery, onDismiss: {
            // Only quits when the user actually picked a backup. It has to
            // happen here rather than in the button: a quit requested while
            // this sheet is still attached is refused and dropped.
            appState.quitForScheduledRestore()
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
            Text("\(prompt.serviceLabel) shows you as away when its window isn't focused. Turn this on to stay active even while you work in other apps. You can change it later in the service's settings. It may hold back some of its notifications while Atoll is in the background.")
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
    /// One rail, so two arrangements. The three-way choice this used to make
    /// only existed because there were two rails to arrange, and concept C put
    /// the space on the rail as its header instead of giving it a rail of its
    /// own.
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
            let presentation: SidebarPresentation = sidebarCollapsed ? .collapsed : .expanded
            HStack(spacing: 0) {
                rail(
                    axis: .vertical,
                    spaceSelection: spaceSelection,
                    serviceSelection: serviceSelection,
                    sidebarPresentation: presentation
                )
                .zIndex(1)
                webContent
                    .padding(.trailing, AtollMetric.Sidebar.surfaceInset)
                    .padding(.bottom, AtollMetric.Sidebar.surfaceInset)
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
                    y: AtollMetric.Toolbar.height / 2
                )
                .animation(
                    reduceMotion ? nil : .smooth(duration: AtollMotion.sidebarTransitionSeconds),
                    value: presentation
                )
            }
        case .topBars:
            VStack(spacing: 0) {
                rail(axis: .horizontal, spaceSelection: spaceSelection, serviceSelection: serviceSelection, contentInset: lightsWidth)
                webContent
                    .padding(.horizontal, AtollMetric.Sidebar.surfaceInset)
                    .padding(.bottom, AtollMetric.Sidebar.surfaceInset)
            }
        }
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
        .accessibilityLabel("Space and services")
    }

    private var webContent: some View {
        WebContentView(
            selectedServiceID: appState.selectedServiceID,
            sidebarIsCollapsed: sidebarCollapsed,
            collapsedSidebarWidth: AtollMetric.Sidebar.collapsedWidth(
                iconSize: appState.iconRailBaseSize
            )
        )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Web content")
    }

    private func selectFirstService(in spaceID: UUID) {
        appState.selectedServiceID = appState.servicesForSpace(spaceID).first?.id
    }

    private func toggleSidebar() {
        if reduceMotion {
            sidebarCollapsed.toggle()
        } else {
            withAnimation(.smooth(duration: AtollMotion.sidebarTransitionSeconds)) {
                sidebarCollapsed.toggle()
            }
        }
    }
}

/// The source project that Atoll uses as its base.
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
            Text("Atoll is locked")
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
