import BlattaCore
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
    @ObservationIgnored private let defaults: UserDefaults

    /// Whether the first-run welcome has already run for this user.
    private(set) var hasSeenWelcome: Bool

    /// What to ask a new user, or nil when there is nothing worth asking.
    ///
    /// Both offers are things that were otherwise only reachable by finding
    /// System Settings or the Settings window, which a new user has no reason
    /// to look in yet.
    var firstRunWelcome: FirstRunWelcome? {
        FirstRunPolicy.welcome(
            hasSeenWelcome: hasSeenWelcome,
            authorization: appState.notificationManager.authorizationState,
            islandIsAvailable: islandPanelController.canPresentIsland
        )
    }

    /// Records that the welcome ran, so it never runs twice.
    func markWelcomeSeen() {
        hasSeenWelcome = true
        defaults.set(true, forKey: DefaultsKey.hasSeenWelcome)
    }

    init(
        appState: AppState? = nil,
        presenceController: AppPresenceController = AppPresenceController(),
        screenGeometryProvider: (any ScreenGeometryProvider)? = nil,
        notificationRouteSettings: NotificationRouteSettings? = nil,
        defaults: UserDefaults = .standard
    ) {
        let resolvedScreenGeometryProvider = screenGeometryProvider
            ?? IslandScreenGeometryConfiguration.makeProvider()
        let islandPanelController = IslandPanelController(
            screenGeometryProvider: resolvedScreenGeometryProvider,
            // The island panel takes no activation of its own, so it must not
            // reach the screen while AppKit is still bringing the main window
            // forward. `AppDelegate` releases it.
            waitsForLaunchActivation: true
        )
        let resolvedNotificationRouteSettings = notificationRouteSettings
            ?? NotificationRouteSettings()
        self.defaults = defaults
        self.hasSeenWelcome = defaults.bool(forKey: DefaultsKey.hasSeenWelcome)
        self.screenGeometryProvider = resolvedScreenGeometryProvider
        self.islandPanelController = islandPanelController
        self.notificationRouteSettings = resolvedNotificationRouteSettings
        self.appState = appState ?? Self.makeAppState(
            islandPanelController: islandPanelController,
            notificationRouteSettings: resolvedNotificationRouteSettings
        )
        self.presenceController = presenceController
        observeIslandAppearance()
        observeActiveService()
        observeUnreadCounts()
    }

    /// Follows the active service account.
    ///
    /// The user reads that conversation in Blatta, so the island drops the events
    /// of that service account and lowers its unreviewed count.
    private func observeActiveService() {
        // The island change happens after the tracked read. The island renderer
        // holds observable state of its own, and this scope must follow the
        // service selection only.
        let serviceID = withObservationTracking {
            appState.selectedServiceID
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeActiveService()
            }
        }
        dismissIslandEvents(forService: serviceID)
    }

    /// Follows the unread count of each service account.
    ///
    /// A count of zero means that the user read every message of that service
    /// account, so the island drops its events.
    private func observeUnreadCounts() {
        appState.badgeManager.onUnreadCountCleared = { [weak self] serviceID in
            self?.islandPanelController.dismissEvents(forService: serviceID)
        }
    }

    private func dismissIslandEvents(forService serviceID: UUID?) {
        guard let serviceID else { return }
        islandPanelController.dismissEvents(forService: serviceID)
    }

    private func observeIslandAppearance() {
        withObservationTracking {
            islandPanelController.updateAppearance(
                NotificationIslandAppearance(
                    glassStyle: appState.liquidGlassStyle,
                    transparency: appState.liquidGlassIntensity
                )
            )
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeIslandAppearance()
            }
        }
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
        islandPanelController.onServiceRequested = {
            [weak self, weak delegate] serviceID in
            self?.appState.notificationManager.routeServiceRequest(serviceID)
            delegate?.bringMainWindowForward()
        }
        delegate.didBecomeActive = { [weak self] in
            guard let self else { return }
            self.dismissIslandEvents(forService: self.appState.selectedServiceID)
        }
        delegate.launchActivationDidSettle = { [weak self] in
            self?.islandPanelController.launchActivationDidSettle()
        }
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

    // TEST_CONTROLS lets a signed build carry this without carrying the rest
    // of the debug surface. scripts/build_dmg.sh --test-controls sets it.
    #if DEBUG || TEST_CONTROLS
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
                serviceLabel: service?.label ?? "Blatta",
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
