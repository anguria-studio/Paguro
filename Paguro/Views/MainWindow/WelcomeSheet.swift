import AppKit
import PaguroCore
import SwiftUI

/// The first-run welcome.
///
/// It exists because both decisions it carries were otherwise unreachable. The
/// notification permission lives in System Settings, and the island lives in
/// the Settings window, and a new user has no reason to open either before they
/// have seen Paguro miss a message.
struct WelcomeSheet: View {
    let welcome: FirstRunWelcome
    let onFinish: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(AppModel.self) private var appModel

    /// True while macOS is deciding, so the button cannot be pressed twice.
    @State private var isRequestingPermission = false

    private var authorizationState: NotificationAuthorizationState {
        appState.notificationManager.authorizationState
    }

    private var permissionIsGranted: Bool {
        NotificationAuthorizationPresentation.showsSystemBanners(
            for: authorizationState
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Paguro")
                    .font(.title2.weight(.semibold))
                Text("Two things are worth setting up before you start.")
                    .foregroundStyle(.secondary)
            }

            if welcome.asksForNotificationPermission {
                notificationRow
            }

            if welcome.offersIsland {
                islandRow
            }

            HStack {
                Spacer()
                Button("Done", action: onFinish)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 460)
    }

    @ViewBuilder
    private var notificationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notifications", systemImage: "bell.badge")
                .font(.headline)

            if permissionIsGranted {
                Text("macOS lets Paguro show notifications.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else if let warning = NotificationAuthorizationPresentation
                .warning(for: authorizationState) {
                Text(warning.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                // A permission macOS has never been asked about can still be
                // asked for in the app. Once macOS holds a decision it will not
                // ask again, so the only way back is System Settings.
                if authorizationState == .notDetermined {
                    Button("Allow Notifications") {
                        Task {
                            isRequestingPermission = true
                            await appState.notificationManager.requestAuthorization()
                            isRequestingPermission = false
                        }
                    }
                    .disabled(isRequestingPermission)
                } else {
                    Button(warning.actionTitle) {
                        openNotificationSettings()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var islandRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Notch island", systemImage: "rectangle.topthird.inset.filled")
                .font(.headline)
            Toggle(
                "Show alerts in the notch",
                isOn: Binding(
                    get: { appModel.notificationRouteSettings.isIslandRouteEnabled },
                    set: { appModel.setIslandNotificationRouteEnabled($0) }
                )
            )
            Text("Alerts appear beside the camera housing instead of as a macOS banner. You can change this later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(
            string: NotificationAuthorizationPresentation.systemSettingsURLString
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
