import AtollCore
import Observation

/// Creates and owns the process-lifetime application services.
@MainActor
@Observable
final class AppModel {
    let appState: AppState
    let presenceController: AppPresenceController

    private var shutdownState = ApplicationShutdownState()

    init(
        appState: AppState? = nil,
        presenceController: AppPresenceController = AppPresenceController()
    ) {
        self.appState = appState ?? Self.makeAppState()
        self.presenceController = presenceController
    }

    private static func makeAppState() -> AppState {
        let dataStoreManager = DataStoreManager()
        let userScriptManager = UserScriptManager()
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
        let mode = appState.ensurePreferences().appPresenceMode
        presenceController.connect(to: delegate, initialMode: mode)
        delegate.flushBeforeTerminate = { [weak self] in
            await self?.shutdown()
        }
    }

    func setPresenceMode(_ mode: AppPresenceMode) {
        let preferences = appState.ensurePreferences()
        preferences.appPresenceMode = mode
        presenceController.setMode(mode)
        appState.savePreferences(reason: "app presence mode")
    }

    func saveWindowState() {
        appState.saveWindowState()
    }

    func shutdown() async {
        guard shutdownState.begin() else { return }
        await appState.shutdown()
        shutdownState.finish()
    }
}
