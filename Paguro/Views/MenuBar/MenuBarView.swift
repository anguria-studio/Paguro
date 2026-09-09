import AppKit
import PaguroCore
import SwiftData
import SwiftUI

extension Notification.Name {
    static let menuBarServiceActivated = Notification.Name("menuBarServiceActivated")
}

/// The compact Paguro control surface that macOS presents from the status item.
/// It keeps service navigation available when Paguro runs without a Dock icon.
struct MenuBarView: View {
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            serviceList

            Divider()

            footer
        }
        .frame(width: 340)
        .containerBackground(for: .window) {
            MenuBarWindowSurface(
                glassStyle: appState.liquidGlassStyle,
                transparency: appState.liquidGlassIntensity
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paguro menu bar window")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image("MenuBarIcon")
                .resizable()
                .frame(width: 20, height: 20)
                .foregroundStyle(PaguroColor.Text.primary)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Paguro")
                    .font(.headline)
                Text(MenuBarPresentation.unreadSummary(appState.badgeManager.totalCount))
                    .font(.caption)
                    .foregroundStyle(PaguroColor.Text.secondary)
            }

            Spacer(minLength: 12)

            Button {
                appState.doNotDisturb.toggle()
            } label: {
                Image(systemName: appState.doNotDisturb ? "bell.slash" : "bell")
            }
            .buttonStyle(PaguroToolbarButtonStyle(isSelected: appState.doNotDisturb))
            .toolbarControlSurface(intensity: appState.liquidGlassIntensity)
            .help(appState.doNotDisturb ? "Unmute notifications" : "Mute notifications")
            .accessibilityLabel(
                appState.doNotDisturb
                    ? "Unmute notifications for all services"
                    : "Mute notifications for all services"
            )
            .accessibilityIdentifier("menuBar.notifications.globalMute")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var serviceList: some View {
        if hasServices {
            MenuBarServiceList {
                ForEach(spaces) { space in
                    workspaceSection(space)
                }
            }
        } else {
            ContentUnavailableView(
                "No Services",
                systemImage: "square.grid.2x2",
                description: Text("Open Paguro to add your first service.")
            )
            .frame(height: 180)
        }
    }

    @ViewBuilder
    private func workspaceSection(_ space: Space) -> some View {
        let services = servicesForSpace(space)
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                workspaceHeader(space)

                ForEach(services) { service in
                    serviceRow(service, in: space)
                }
            }
        }
    }

    private func workspaceHeader(_ space: Space) -> some View {
        let muted = NotificationMutePresentation.showsMutedState(
            scopeMuted: space.isMutedEffective,
            manualGlobalMute: appState.doNotDisturb
        )

        return HStack(spacing: 6) {
            if let emoji = space.displayEmoji {
                Text(emoji)
                    .accessibilityHidden(true)
            }

            Text(space.name)
                .lineLimit(1)

            Spacer(minLength: 8)

            if muted {
                Image(systemName: "bell.slash.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(PaguroColor.Text.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(PaguroColor.Text.secondary)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(muted ? "\(space.name), muted" : space.name)
    }

    private func serviceRow(_ service: ServiceInstance, in space: Space) -> some View {
        let isSelected = appState.selectedServiceID == service.id
            && appState.selectedSpaceID == space.id
        let badgeCount = appState.badgeManager.badgeCount(for: service.id)
        let isHibernated = !isSelected && appState.webViewPool.isHibernated(service.id)
        let isMuted = NotificationMutePresentation.showsMutedState(
            scopeMuted: service.isEffectivelyMuted,
            manualGlobalMute: appState.doNotDisturb
        )
        let media = appState.webViewPool.mediaCaptureStates[service.id]
        let health = isHibernated
            ? ServiceHealth.live
            : appState.webViewPool.health(for: service.id)
        let serviceStateLabel = ServiceAccessibility.label(
            name: service.label,
            badgeCount: badgeCount,
            isHibernated: isHibernated,
            isMuted: isMuted,
            cameraActive: media?.cameraActive ?? false,
            micActive: media?.micActive ?? false,
            micMuted: media?.micMuted ?? false,
            health: health
        )

        return Button {
            activateService(service.id, inSpace: space.id)
        } label: {
            HStack(spacing: 10) {
                ServiceIconSquare(instance: service, size: 24, cornerRadius: 5)
                    .accessibilityHidden(true)

                Text(service.label)
                    .lineLimit(1)
                    .foregroundStyle(PaguroColor.Text.primary)

                Spacer(minLength: 8)

                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(PaguroColor.Text.tertiary)
                        .accessibilityHidden(true)
                }

                if badgeCount > 0 && service.showBadge {
                    BadgeCountView(count: badgeCount)
                }

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(MenuBarServiceButtonStyle(isSelected: isSelected))
        .accessibilityLabel(MenuBarPresentation.serviceAccessibilityLabel(
            serviceStateLabel: serviceStateLabel,
            workspaceName: space.name,
            isSelected: isSelected
        ))
        .help("Open \(service.label) in \(space.name)")
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Button {
                showMainWindow()
            } label: {
                Label("Open Paguro", systemImage: "macwindow")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            Button {
                dismiss()
                AppDelegate.prepareToShowWindow()
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(PaguroToolbarButtonStyle())
            .help("Settings")
            .accessibilityLabel("Open Paguro Settings")
        }
        .padding(12)
    }

    private var hasServices: Bool {
        spaces.contains { !servicesForSpace($0).isEmpty }
    }

    private func servicesForSpace(_ space: Space) -> [ServiceInstance] {
        // Route through AppState's fetch so this window uses the same guarded
        // path as the sidebar after a service or workspace deletion.
        appState.servicesForSpace(space.id)
    }

    private func activateService(_ serviceID: UUID, inSpace spaceID: UUID) {
        NotificationCenter.default.post(
            name: .menuBarServiceActivated,
            object: nil,
            userInfo: ["serviceID": serviceID, "spaceID": spaceID]
        )
        showMainWindow()
    }

    /// Uses the shared route, which promotes the activation policy and then
    /// orders the main window forward or asks SwiftUI to build it again.
    private func showMainWindow() {
        dismiss()
        appModel.bringMainWindowForward()
    }
}

/// Vertical limits for the menu-bar service list.
enum MenuBarServiceListMetrics {
    /// The greatest height the list may take. A longer list scrolls inside it.
    static let maximumHeight: CGFloat = 380
}

/// Puts the menu-bar service rows in a bounded scrolling area.
///
/// The vertical size needs care. A scroll view accepts every height that its
/// parent offers, and it accepts zero. The menu-bar window takes its own
/// height from this content, so it offers no height while it measures. A
/// scroll view answers that question with zero. The window then keeps only its
/// header and its footer, and the user sees no row. That result is stable,
/// because the next measurement asks the same question and gets the same
/// answer. `fixedSize` makes the scroll view report the height of its rows
/// instead, and `frame(maxHeight:)` still limits a long list.
struct MenuBarServiceList<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView {
            // A plain stack builds every row. The list holds one row for each
            // service, so laziness saves nothing and would tie the rows to the
            // scroll view's height a second time.
            VStack(alignment: .leading, spacing: 14) {
                content
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
        }
        .frame(maxHeight: MenuBarServiceListMetrics.maximumHeight)
        .fixedSize(horizontal: false, vertical: true)
    }
}

/// Matches the menu-bar window to the main shell's frost, glass, and
/// protective tint. The system still owns the window shape and shadow.
private struct MenuBarWindowSurface: View {
    let glassStyle: ShellGlassStyle
    let transparency: Double

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.regularMaterial)
                .opacity(glassStyle.frostOpacity)

            glassLayer

            Rectangle()
                .fill(PaguroColor.shellTint(intensity: transparency))
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        // Below macOS 26 there is no glass layer to draw. The panel keeps the
        // material behind it, which is the same result the Off style gives.
        if #available(macOS 26, *), glassStyle != .off {
            availableGlassLayer
        } else {
            EmptyView()
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var availableGlassLayer: some View {
        switch glassStyle {
        case .clear:
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: .rect)
        case .off, .regular:
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
        }
    }
}

private struct MenuBarServiceButtonStyle: ButtonStyle {
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: PaguroRadius.control, style: .continuous)
                    .fill(
                        isSelected
                            ? selectedFill
                            : (isHovering ? PaguroColor.Fill.sidebarRowHover : Color.clear)
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { isHovering = $0 }
    }

    private var selectedFill: Color {
        if reduceTransparency {
            return colorScheme == .light ? .white : Color(white: 0.28)
        }
        return Color.white.opacity(colorScheme == .light ? 0.55 : 0.14)
    }
}
