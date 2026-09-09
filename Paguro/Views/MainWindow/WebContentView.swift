import SwiftUI
import SwiftData
import WebKit

struct WebContentView: View {
    let selectedServiceID: UUID?
    let sidebarIsCollapsed: Bool
    let collapsedSidebarWidth: CGFloat

    @Environment(AppState.self) private var appState
    @Query private var services: [ServiceInstance]
    @State private var currentWebView: WKWebView?
    @State private var transitionSnapshot: NSImage?
    @State private var showPasskeyNotice = false
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
                if showPasskeyNotice {
                    passkeyNoticeBanner
                }

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
                }
                .background(
                    PaguroColor.shellCanvas(intensity: appState.liquidGlassIntensity)
                )
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
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: showPasskeyNotice)
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
            showPasskeyNotice = true
            appState.markPasskeyNoticeSeen(for: service.id)
        } else {
            showPasskeyNotice = false
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

    /// A slim, dismissible bar warning that passkey sign-in isn't available in
    /// Paguro's web views. Auto-hides after a short delay; the "seen" state is
    /// already persisted when it appears, so it never returns for this service.
    private var passkeyNoticeBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.key.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(AppCapabilities.passkeyUnavailableBanner)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button {
                showPasskeyNotice = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PaguroColor.Fill.quietSurface)
        .overlay(alignment: .bottom) { Divider() }
        .transition(.move(edge: .top).combined(with: .opacity))
        .task {
            try? await Task.sleep(for: .seconds(12))
            showPasskeyNotice = false
        }
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
