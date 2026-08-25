import SwiftUI

/// The native header above web content in the left-sidebar layout.
struct WebContentHeader: View {
    let webViewState: WebViewState
    var title: String
    var webAppearanceIsDark = false
    var canToggleWebAppearance = false
    var reservesSidebarToggleSpace = false
    var sidebarToggleLeadingInset = AtollMetric.Toolbar.collapsedLeadingInset
    var onToggleWebAppearance: () -> Void = {}
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 12) {
            if reservesSidebarToggleSpace {
                Color.clear
                    .frame(
                        width: AtollMetric.Toolbar.sidebarToggleSize,
                        height: AtollMetric.Toolbar.sidebarToggleSize
                    )
                    .accessibilityHidden(true)
            }

            Text(title)
                .font(.atollToolbarTitle)
                .foregroundStyle(AtollColor.Text.primary)
                .lineLimit(1)

            Spacer(minLength: 24)

            WebContentActions(
                webViewState: webViewState,
                webAppearanceIsDark: webAppearanceIsDark,
                canToggleWebAppearance: canToggleWebAppearance,
                onToggleWebAppearance: onToggleWebAppearance
            )
        }
        .padding(
            .leading,
            reservesSidebarToggleSpace
                ? sidebarToggleLeadingInset
                : AtollMetric.Toolbar.horizontalInset
        )
        .padding(.trailing, AtollMetric.Toolbar.horizontalInset)
        .frame(height: AtollMetric.Toolbar.height)
        .fixedSize(horizontal: false, vertical: true)
        .layoutPriority(1)
        .background(WindowDragHandle())
        .background(
            AtollColor.shellCanvas(intensity: appState.liquidGlassIntensity)
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
        .buttonStyle(AtollSidebarButtonStyle(isCollapsed: showsCollapsedChrome))
        .keyboardShortcut("s", modifiers: [.command, .control])
        .help(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityLabel(isCollapsed ? "Expand sidebar" : "Collapse sidebar")
        .accessibilityIdentifier("sidebar.toggle")
    }
}

/// The two persistent actions for the active web service.
///
/// Service pages own their navigation. Atoll keeps only recovery from a stale
/// page and the per-service appearance choice in the window header.
struct WebContentActions: View {
    let webViewState: WebViewState
    let webAppearanceIsDark: Bool
    let canToggleWebAppearance: Bool
    let onToggleWebAppearance: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 2) {
            Button {
                if webViewState.isLoading {
                    webViewState.webView?.stopLoading()
                } else {
                    webViewState.webView?.reload()
                }
            } label: {
                Image(systemName: webViewState.isLoading ? "xmark" : "arrow.clockwise")
            }
            .buttonStyle(AtollToolbarButtonStyle())
            .disabled(webViewState.webView == nil)
            .help(webViewState.isLoading ? "Stop" : "Reload")
            .accessibilityLabel(webViewState.isLoading ? "Stop loading" : "Reload page")

            Button(action: onToggleWebAppearance) {
                Image(systemName: webAppearanceIsDark ? "moon.fill" : "moon")
            }
            .buttonStyle(AtollToolbarButtonStyle(isSelected: webAppearanceIsDark))
            .disabled(!canToggleWebAppearance)
            .help(
                webAppearanceIsDark
                    ? "Use a light service appearance"
                    : "Use a dark service appearance"
            )
            .accessibilityLabel(
                webAppearanceIsDark
                    ? "Use a light service appearance"
                    : "Use a dark service appearance"
            )
            .accessibilityValue(webAppearanceIsDark ? "Dark" : "Light")
        }
        .padding(3)
        .glassEffect(
            .regular
                .tint(
                    AtollColor.Fill.glassTint(
                        intensity: appState.liquidGlassIntensity
                    )
                )
                .interactive(),
            in: .capsule
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Service controls")
    }
}
