import PaguroCore
import SwiftUI
import SwiftData
import WebKit

struct WebContentView: View {
    /// How long a floating notice stays on screen. It matches the capacity
    /// notice, which `HibernationScheduler` removes on the same schedule.
    private static let passkeyNoticeSeconds = 12

    let selectedServiceID: UUID?
    let sidebarIsCollapsed: Bool
    let collapsedSidebarWidth: CGFloat

    @Environment(AppState.self) private var appState
    @Query private var services: [ServiceInstance]
    @State private var currentWebView: WKWebView?
    @State private var transitionSnapshot: NSImage?
    /// The service whose passkey notice is on screen, or nil for none. The
    /// identifier also restarts the auto-hide when another service raises it.
    @State private var passkeyNoticeServiceID: UUID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Shared web state for reload and stop in both window layouts.
    private var webViewState: WebViewState { appState.webViewState }

    private var selectedService: ServiceInstance? {
        guard let id = selectedServiceID else { return nil }
        return services.first { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.railLayout == .sidebar {
                WebContentHeader(
                    webViewState: webViewState,
                    title: selectedService?.label ?? "Paguro",
                    reservesSidebarToggleSpace: sidebarIsCollapsed,
                    sidebarToggleLeadingInset: PaguroMetric.Toolbar.collapsedLeadingInset(
                        sidebarWidth: collapsedSidebarWidth
                    )
                )
            }

            if selectedService != nil, let webView = currentWebView {
                ZStack(alignment: .topTrailing) {
                    WebViewContainer(webView: webView)

                    // Show cached snapshot as instant visual feedback while page loads.
                    // Fades out once the web view finishes loading. It fills the
                    // web view's frame (rather than aspect-fill, which cropped or
                    // stretched it); since the snapshot was taken at this frame it
                    // lines up without distortion.
                    if let snapshot = transitionSnapshot, webViewState.isLoading {
                        Image(nsImage: snapshot)
                            .resizable()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .clipped()
                            .transition(.opacity)
                            .accessibilityHidden(true)
                    }

                    if appState.findInPageVisible {
                        FindInPageBar(
                            isVisible: Binding(
                                get: { appState.findInPageVisible },
                                set: { appState.findInPageVisible = $0 }
                            ),
                            webView: webView
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    // The cards float above the page instead of pushing it
                    // down. The reader gives the stack the web width, so a
                    // narrow window keeps the card inside the content.
                    GeometryReader { proxy in
                        FloatingNoticeStack(
                            notices: floatingNotices,
                            availableWidth: proxy.size.width,
                            findBarIsVisible: appState.findInPageVisible
                        )
                    }
                }
                .background(
                    PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity)
                )
                // The mark that reports a download start leaves from this area,
                // on the vertical line of the header control. It reports the
                // frame only; the layout of the page, the find bar, and the
                // notice cards stays as it is.
                .downloadFlightOrigin()
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: webViewState.isLoading)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: appState.findInPageVisible)
            } else if selectedService != nil {
                ProgressView("Loading service…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity)
                    )
            } else {
                emptyState
            }
        }
        .task(id: passkeyNoticeServiceID) {
            // The passkey notice reports a fixed limit, so it leaves on its
            // own. The "seen" state is already stored, and the card never
            // returns for this service.
            guard passkeyNoticeServiceID != nil else { return }
            try? await Task.sleep(for: .seconds(Self.passkeyNoticeSeconds))
            guard !Task.isCancelled else { return }
            passkeyNoticeServiceID = nil
        }
        .onAppear {
            loadWebViewForSelectedService()
        }
        .onChange(of: selectedServiceID) {
            loadWebViewForSelectedService()
        }
        .onChange(of: appState.webViewRebuildToken) {
            // A service's web view was rebuilt (e.g. custom CSS edit). Re-fetch
            // so the active service picks up the freshly created view.
            loadWebViewForSelectedService()
        }
        .onChange(of: colorScheme) { _, newScheme in
            appState.updateEffectiveShellAppearance(isDark: newScheme == .dark)
        }
        .onChange(of: webViewState.isLoading) { _, loading in
            // Drop the snapshot once the page finishes so it can't linger over a
            // loaded page and to free the bitmap. Delayed past the fade, and
            // re-checked in case another load started in the meantime.
            guard !loading else { return }
            let delay = reduceMotion ? 0 : 0.25
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                if !webViewState.isLoading { transitionSnapshot = nil }
            }
        }
    }

    private func loadWebViewForSelectedService() {
        // Set the native web appearance before Paguro creates a new WKWebView.
        // Existing automatic services update in place.
        appState.updateEffectiveShellAppearance(isDark: colorScheme == .dark)

        guard let service = selectedService else {
            appState.webViewPool.deactivateCurrentService()
            webViewState.detach()
            currentWebView = nil
            transitionSnapshot = nil
            return
        }

        // Grab the snapshot before loading — if the service was soft-hibernated,
        // this gives us an instant preview to show while the web view wakes up.
        transitionSnapshot = appState.webViewPool.snapshot(for: service.id)

        let webView = appState.webViewPool.webView(for: service)
        // Apply the effective zoom (per-service if set, else the Paguro-wide
        // default) so it survives hibernation and relaunch. Setting pageZoom is
        // a no-op when the value matches.
        webView.pageZoom = CGFloat(appState.effectiveZoom(for: service))
        currentWebView = webView
        webViewState.attach(to: webView)

        // Passive one-time notice: WKWebView can't use passkeys for sign-in, so
        // warn the user the first time each service is opened. Gated by the same
        // capability switch as the Add Service notice, and marked seen as soon
        // as it's shown so switching away and back doesn't re-trigger it.
        if !AppCapabilities.passkeysSupported, appState.shouldShowPasskeyNotice(for: service) {
            passkeyNoticeServiceID = service.id
            appState.markPasskeyNoticeSeen(for: service.id)
        } else {
            passkeyNoticeServiceID = nil
        }

        // Once the view is shown its frame settles a render tick later. Some SPAs
        // (Gmail) cache a viewport-height layout and, if it was measured against a
        // stale/transitional frame, leave their fixed header stranded above the
        // visible area with no way to scroll to it. Fire a synthetic resize so the
        // page re-measures against the real frame; it's a no-op for other sites.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            _ = try? await webView.evaluateJavaScript("window.dispatchEvent(new Event('resize'))")
        }

    }

    /// The transient notices for the service on screen.
    ///
    /// Both notices report a fixed Paguro limit, name no action the user must
    /// take now, and leave on their own. That is the card's purpose. An
    /// app-level state keeps the full-width strip in `ContentView`.
    private var floatingNotices: [FloatingNotice] {
        var notices: [FloatingNotice] = []

        // The pool's own size limit can release a background service while
        // idle hibernation is off. Say so one time, so the user does not read
        // the reload as a fault.
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
        if passkeyNoticeServiceID != nil {
            notices.append(
                FloatingNotice(
                    id: .passkeyUnavailable,
                    systemImage: "person.badge.key.fill",
                    title: "Passkeys are not available",
                    message: AppCapabilities.passkeyUnavailableBanner,
                    dismiss: { passkeyNoticeServiceID = nil }
                )
            )
        }

        return notices
    }

    /// Whether the currently selected space contains any services. Only
    /// evaluated when nothing is selected (the empty-state branch), so the
    /// per-render fetch is off the hot path.
    private var selectedSpaceHasServices: Bool {
        guard let spaceID = appState.selectedSpaceID else { return false }
        return !appState.servicesForSpace(spaceID).isEmpty
    }

    @ViewBuilder
    private var emptyState: some View {
        if appState.selectedSpaceID == nil {
            emptyStateContent(
                icon: "square.stack.3d.up",
                message: "Create a workspace to get started",
                actionTitle: nil
            )
        } else if selectedSpaceHasServices {
            emptyStateContent(
                icon: "rectangle.stack",
                message: "Pick a service from the sidebar to get started",
                actionTitle: nil
            )
        } else {
            emptyStateContent(
                icon: "plus.rectangle.on.rectangle",
                message: "No services in this workspace yet",
                actionTitle: "Add Service"
            ) {
                appState.showAddService = true
            }
        }
    }

    private func emptyStateContent(
        icon: String,
        message: String,
        actionTitle: String?,
        action: @escaping () -> Void = {}
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(message)
                .font(.title3)
                .foregroundStyle(.secondary)

            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity)
        )
    }
}
