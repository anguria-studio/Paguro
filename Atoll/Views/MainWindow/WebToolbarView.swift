import SwiftUI

/// The native header above web content in the left-sidebar layout.
struct WebContentHeader: View {
    let webViewState: WebViewState
    var title: String
    var reservesSidebarToggleSpace = false
    var sidebarToggleLeadingInset = AtollMetric.Toolbar.collapsedLeadingInset
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

            WebContentActions(webViewState: webViewState)
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

/// The persistent recovery action for the active web service.
///
/// Service pages own their navigation and appearance. Atoll keeps reload in
/// the window header so the user can recover from a stale page.
struct WebContentActions: View {
    let webViewState: WebViewState

    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 6) {
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
            .buttonStyle(AtollToolbarButtonStyle(isSelected: appState.doNotDisturb))
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Service controls")
    }

    private var actionGlass: Glass {
        .regular
            .tint(
                AtollColor.Fill.glassTint(
                    intensity: appState.liquidGlassIntensity
                )
            )
            .interactive()
    }
}
