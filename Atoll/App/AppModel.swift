import AtollCore
import Foundation
import Observation

/// Creates and owns the process-lifetime application services.
@MainActor
@Observable
final class AppModel {
    let appState: AppState
    let presenceController: AppPresenceController
    let screenGeometryProvider: any ScreenGeometryProvider
    let islandPanelController: IslandPanelController
    let notificationRouteSettings: NotificationRouteSettings

    private var shutdownState = ApplicationShutdownState()

    init(
        appState: AppState? = nil,
        presenceController: AppPresenceController = AppPresenceController(),
        screenGeometryProvider: (any ScreenGeometryProvider)? = nil,
        notificationRouteSettings: NotificationRouteSettings? = nil
    ) {
        let resolvedScreenGeometryProvider = screenGeometryProvider
            ?? IslandScreenGeometryConfiguration.makeProvider()
        let islandPanelController = IslandPanelController(
            screenGeometryProvider: resolvedScreenGeometryProvider
        )
        let resolvedNotificationRouteSettings = notificationRouteSettings
            ?? NotificationRouteSettings()
        self.screenGeometryProvider = resolvedScreenGeometryProvider
        self.islandPanelController = islandPanelController
        self.notificationRouteSettings = resolvedNotificationRouteSettings
        self.appState = appState ?? Self.makeAppState(
            islandPanelController: islandPanelController,
            notificationRouteSettings: resolvedNotificationRouteSettings
        )
        self.presenceController = presenceController
    }

    private static func makeAppState(
        islandPanelController: IslandPanelController,
        notificationRouteSettings: NotificationRouteSettings
    ) -> AppState {
        let dataStoreManager = DataStoreManager()
        let userScriptManager = UserScriptManager(
            islandPanelController: islandPanelController
        )
        userScriptManager.isSystemNotificationsEnabled = {
            notificationRouteSettings.isSystemRouteEnabled
        }
        userScriptManager.isIslandNotificationsEnabled = { _ in
            notificationRouteSettings.isIslandRouteEnabled
        }
        let badgeManager = BadgeManager()
        let notificationManager = NotificationManager(badgeManager: badgeManager)
        let transientBadgeFetcher = TransientBadgeFetcher(
            badgeManager: badgeManager,
            dataStoreManager: dataStoreManager
        )
        let contentBlocker = ContentBlockerManager()
        let webViewPool = WebViewPool(
            dataStoreManager: dataStoreManager,
            userScriptManager: userScriptManager,
            contentBlocker: contentBlocker
        )
        let networkMonitor = NetworkMonitor()

        return AppState(
            dataStoreManager: dataStoreManager,
            userScriptManager: userScriptManager,
            badgeManager: badgeManager,
            notificationManager: notificationManager,
            transientBadgeFetcher: transientBadgeFetcher,
            contentBlocker: contentBlocker,
            webViewPool: webViewPool,
            networkMonitor: networkMonitor
        )
    }

    func connect(to delegate: AppDelegate) {
        let mode = appState.preferencesStore.appPresenceMode
        presenceController.connect(to: delegate, initialMode: mode)
        delegate.startAfterLaunch = { [weak self] in
            guard let self else { return }
            self.appState.start()
            if self.notificationRouteSettings.isIslandRouteEnabled {
                self.islandPanelController.showCollapsed()
            }
        }
        delegate.flushBeforeTerminate = { [weak self] in
            await self?.shutdown()
        }
    }

    func setPresenceMode(_ mode: AppPresenceMode) {
        guard appState.preferencesStore.setAppPresenceMode(mode) else { return }
        presenceController.setMode(mode)
    }

    func saveWindowState() {
        appState.saveWindowState()
    }

    func setSystemNotificationRouteEnabled(_ isEnabled: Bool) {
        notificationRouteSettings.setSystemRouteEnabled(isEnabled)
    }

    func setIslandNotificationRouteEnabled(_ isEnabled: Bool) {
        notificationRouteSettings.setIslandRouteEnabled(isEnabled)
        if isEnabled {
            islandPanelController.showCollapsed()
        } else {
            islandPanelController.hide()
        }
    }

    #if DEBUG
    func showIslandPreview(for service: ServiceInstance?) {
        guard notificationRouteSettings.isIslandRouteEnabled else { return }
        guard let event = try? NotificationEvent.normalize(
            id: UUID(),
            serviceID: service?.id ?? UUID(),
            source: .pageNotification,
            title: "Island preview",
            body: "This is how a service notification will appear.",
            receivedAt: Date()
        ) else {
            return
        }

        islandPanelController.present(
            NotificationIslandPanelContent(
                event: event,
                serviceLabel: service?.label ?? "Atoll",
                serviceIconURL: service.flatMap {
                    NotificationAttachmentStore.prepareServiceIcon(for: $0)
                }
            )
        )
    }
    #endif

    func shutdown() async {
        guard shutdownState.begin() else { return }
        islandPanelController.stop()
        await appState.shutdown()
        shutdownState.finish()
    }
}
