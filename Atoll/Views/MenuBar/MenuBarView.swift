import AppKit
import AtollCore
import SwiftData
import SwiftUI

extension Notification.Name {
    static let menuBarServiceActivated = Notification.Name("menuBarServiceActivated")
}

/// The compact Atoll control surface that macOS presents from the status item.
/// It keeps service navigation available when Atoll runs without a Dock icon.
struct MenuBarView: View {
    @Query(sort: \Space.sortOrder) private var spaces: [Space]
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

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
        .accessibilityLabel("Atoll menu bar window")
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("Atoll")
                    .font(.headline)
                Text(MenuBarPresentation.unreadSummary(appState.badgeManager.totalCount))
                    .font(.caption)
                    .foregroundStyle(AtollColor.Text.secondary)
            }

            Spacer(minLength: 12)

            Button {
                appState.doNotDisturb.toggle()
            } label: {
                Image(systemName: appState.doNotDisturb ? "bell.slash" : "bell")
            }
            .buttonStyle(AtollToolbarButtonStyle(isSelected: appState.doNotDisturb))
            .glassEffect(
                .regular
                    .tint(
                        AtollColor.Fill.glassTint(
                            intensity: appState.liquidGlassIntensity
                        )
                    )
                    .interactive(),
                in: .circle
            )
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(spaces) { space in
                        workspaceSection(space)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
            }
            .frame(maxHeight: 380)
        } else {
            ContentUnavailableView(
                "No Services",
                systemImage: "square.grid.2x2",
                description: Text("Open Atoll to add your first service.")
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
                    .foregroundStyle(AtollColor.Text.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(AtollColor.Text.secondary)
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
                    .foregroundStyle(AtollColor.Text.primary)

                Spacer(minLength: 8)

                if isMuted {
                    Image(systemName: "bell.slash.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(AtollColor.Text.tertiary)
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
                Label("Open Atoll", systemImage: "macwindow")
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
            .buttonStyle(AtollToolbarButtonStyle())
            .help("Settings")
            .accessibilityLabel("Open Atoll Settings")
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

    private func showMainWindow() {
        dismiss()
        AppDelegate.prepareToShowWindow()
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == "main" }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
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
                .fill(AtollColor.shellTint(intensity: transparency))
        }
    }

    @ViewBuilder
    private var glassLayer: some View {
        switch glassStyle {
        case .off:
            EmptyView()
        case .clear:
            Rectangle()
                .fill(.clear)
                .glassEffect(.clear, in: .rect)
        case .regular:
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: .rect)
        }
    }
}

private struct MenuBarServiceButtonStyle: ButtonStyle {
    let isSelected: Bool
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: AtollRadius.control, style: .continuous)
                    .fill(
                        isSelected
                            ? AtollColor.Fill.sidebarSelection
                            : (isHovering ? AtollColor.Fill.sidebarRowHover : Color.clear)
                    )
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { isHovering = $0 }
    }
}
