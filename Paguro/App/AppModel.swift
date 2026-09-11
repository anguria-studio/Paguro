import AppKit
import PaguroCore
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
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var screenObserverTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var notchedDisplayTask: Task<Void, Never>?
    #if DEBUG
    @ObservationIgnored private var previewNotifications = IslandPreviewNotifications()
    @ObservationIgnored private let usesDemoNotifications: Bool
    #endif

    /// Whether a connected display has a camera housing.
    ///
    /// Settings offers the island controls only then. On a Mac without such a
    /// display the island cannot appear, so its switch and its test action
    /// would promise a result that no display can show.
    private(set) var hasNotchedDisplay = false
    private(set) var hasRecentNotifications = false

    var canOpenNotifications: Bool {
        !appState.isLocked && hasNotchedDisplay && hasRecentNotifications
            && notificationRouteSettings.isIslandRouteEnabled
    }

    func openNotifications() {
        guard canOpenNotifications else { return }
        islandPanelController.openFromKeyboard()
    }

    /// The AppKit adapter that shows the main window. AppKit owns the delegate,
    /// so this reference stays weak.
    @ObservationIgnored private weak var appDelegate: AppDelegate?

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
        defaults: UserDefaults = .standard,
        notificationCenter: NotificationCenter = .default,
        launchArguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        #if DEBUG
        self.usesDemoNotifications = launchArguments.contains(IslandPreviewNotifications.launchArgument)
        #endif
        let resolvedScreenGeometryProvider = screenGeometryProvider
            ?? IslandScreenGeometryConfiguration.makeProvider(arguments: launchArguments)
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
        self.notificationCenter = notificationCenter
        self.hasSeenWelcome = defaults.bool(forKey: DefaultsKey.hasSeenWelcome)
        self.screenGeometryProvider = resolvedScreenGeometryProvider
        self.islandPanelController = islandPanelController
        self.notificationRouteSettings = resolvedNotificationRouteSettings
        self.appState = appState ?? Self.makeAppState(
            islandPanelController: islandPanelController,
            notificationRouteSettings: resolvedNotificationRouteSettings
        )
        self.presenceController = presenceController
        islandPanelController.onHistoryAvailabilityChanged = { [weak self] hasHistory in
            self?.hasRecentNotifications = hasHistory
        }
        self.appState.onLockChanged = { [weak islandPanelController] isLocked in
            islandPanelController?.setLocked(isLocked)
        }
        islandPanelController.setLocked(self.appState.isLocked)
        observeIslandAppearance()
        observeActiveService()
        observeUnreadCounts()
    }

    /// Follows the active service account.
    ///
    /// The user reads that conversation in Paguro, so the island drops the events
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

    /// Reads the displays again and updates `hasNotchedDisplay`.
    ///
    /// The value follows the current displays, because docking, clamshell
    /// operation, and a display change can add or remove the camera housing
    /// while Paguro runs. The read uses the island geometry provider, so the
    /// Debug launch arguments that simulate a notch also reach this value.
    func refreshNotchedDisplay() {
        notchedDisplayTask?.cancel()
        let provider = screenGeometryProvider
        notchedDisplayTask = Task { @MainActor [weak self] in
            let snapshot = await provider.currentSnapshot()
            guard !Task.isCancelled, let self else { return }
            self.hasNotchedDisplay = snapshot.hasCameraHousingScreen
        }
    }

    private func observeScreenChanges() {
        guard screenObserverTokens.isEmpty else { return }
        screenObserverTokens.append(notificationCenter.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshNotchedDisplay()
            }
        })
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

    /// Activates Paguro and shows the main window, whatever the window state is.
    /// Every route that starts outside the main window uses this one path.
    func bringMainWindowForward() {
        appDelegate?.bringMainWindowForward()
    }

    func connect(to delegate: AppDelegate) {
        let mode = appState.preferencesStore.appPresenceMode
        appDelegate = delegate
        presenceController.connect(to: delegate, initialMode: mode)
        // The closure reaches the delegate through this model, so a route that
        // is wired before or after `AppState.start()` uses the same reference.
        appState.bringMainWindowForward = { [weak self] in
            self?.bringMainWindowForward()
        }
        islandPanelController.onServiceRequested = { [weak self] serviceID in
            self?.appState.notificationManager.routeServiceRequest(serviceID)
            self?.bringMainWindowForward()
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
            self.observeScreenChanges()
            self.refreshNotchedDisplay()
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
        guard !appState.isLocked else { return }
        guard notificationRouteSettings.isIslandRouteEnabled else { return }
        var previewService = service
        var title = "Island preview"
        var body = "This is how a service notification will appear."
        #if DEBUG
        if usesDemoNotifications {
            let services = appState.workspaceStore.allServices()
            let accounts = services.map {
                IslandPreviewNotifications.Account(serviceID: $0.id, catalogID: $0.catalogEntryID, url: $0.url)
            }
            var generator = SystemRandomNumberGenerator()
            if let preview = previewNotifications.next(accounts: accounts, using: &generator),
               let account = services.first(where: { $0.id == preview.serviceID }) {
                previewService = account
                title = preview.message.title
                body = preview.message.body
            }
        }
        #endif
        guard let event = try? NotificationEvent.normalize(
            id: UUID(),
            serviceID: previewService?.id ?? UUID(),
            source: .pageNotification,
            title: title,
            body: body,
            receivedAt: Date()
        ) else {
            return
        }

        islandPanelController.present(
            NotificationIslandPanelContent(
                event: event,
                serviceLabel: previewService?.label ?? "Paguro",
                serviceIconURL: previewService.flatMap {
                    NotificationAttachmentStore.prepareServiceIcon(for: $0)
                }
            )
        )
    }
    #endif

    func shutdown() async {
        guard shutdownState.begin() else { return }
        notchedDisplayTask?.cancel()
        notchedDisplayTask = nil
        for token in screenObserverTokens {
            notificationCenter.removeObserver(token)
        }
        screenObserverTokens.removeAll()
        islandPanelController.stop()
        await appState.shutdown()
        shutdownState.finish()
    }
}

extension AppModel {
    func exportConfigurationData() throws -> Data {
        guard !appState.isLocked else { throw ConfigurationArchiveError.invalid("Unlock Paguro first.") }
        var archive = try appState.workspaceStore.exportConfiguration()
        appState.shellPreferences.addToConfiguration(&archive.preferences)
        archive.preferences.systemNotifications = notificationRouteSettings.isSystemRouteEnabled
        archive.preferences.islandNotifications = notificationRouteSettings.isIslandRouteEnabled
        return try ConfigurationArchiveCodec.encode(archive)
    }

    func importConfiguration(
        _ archive: ConfigurationArchive,
        applyPreferences: Bool,
        mode: ConfigurationImportMode = .add
    ) throws {
        guard !appState.isLocked else { throw ConfigurationArchiveError.invalid("Unlock Paguro first.") }
        let outcome = try appState.workspaceStore.importConfiguration(
            archive, applyPreferences: applyPreferences, mode: mode
        )
        for service in outcome.removedServices {
            dismissIslandEvents(forService: service.serviceID)
        }
        appState.finishConfigurationImport(outcome, mode: mode)
        if applyPreferences {
            appState.applyImportedPreferences(archive.preferences)
            presenceController.setMode(appState.preferencesStore.appPresenceMode)
            setSystemNotificationRouteEnabled(archive.preferences.systemNotifications)
            setIslandNotificationRouteEnabled(archive.preferences.islandNotifications)
        }
        appState.storeRecovery.recordContent()
    }
}
