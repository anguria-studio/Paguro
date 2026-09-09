import SwiftUI
import SwiftData
import WebKit
import LocalAuthentication
import PaguroCore

@MainActor
@Observable
final class AppState {
    let modelContainer: ModelContainer
    let preferencesStore: PreferencesStore
    let workspaceStore: WorkspaceStore
    private(set) var shellPreferences: ShellPreferences
    let mediaPermissions: MediaPermissionCoordinator
    let storeRecovery: StoreRecoveryCoordinator
    let websiteDataReclaimer: WebsiteDataReclaimer
    let hibernationScheduler: HibernationScheduler
    let notificationRuntime: NotificationRuntime
    let webViewPool: WebViewPool
    let contentBlocker: ContentBlockerManager
    let dataStoreManager: DataStoreManager
    let userScriptManager: UserScriptManager
    let badgeManager: BadgeManager

    /// Loading state and a weak reference for the active service's web view.
    /// Both window layouts use this state for reload, stop, and history.
    let webViewState = WebViewState()

    /// The downloads that the content header shows. `WebDownloadHandler`
    /// reports each transfer here through its coordinator.
    let downloadTracker = DownloadTracker()
    var notificationManager: NotificationManager { notificationRuntime.notificationManager }
    var networkMonitor: NetworkMonitor { notificationRuntime.networkMonitor }

    var selectedSpaceID: UUID?
    var selectedServiceID: UUID?
    var showAddService = false
    var showAddSpace = false
    var showQuickSwitcher = false

    var doNotDisturb: Bool {
        get { notificationRuntime.doNotDisturb }
        set { notificationRuntime.doNotDisturb = newValue }
    }
    /// Drives the Find-in-Page overlay in WebContentView. Toggled by Cmd-F.
    var findInPageVisible = false

    /// Bumped when a service's web view is rebuilt for an edit that only takes
    /// effect at creation time (custom CSS). WebContentView observes this and
    /// re-fetches the active service's web view so the change shows at once.
    var webViewRebuildToken = 0

    /// Paguro-wide default page zoom, applied to services without an explicit
    /// per-service zoom. Loaded from `PreferencesStore` at launch.
    var defaultZoom: Double = 1.0

    var railLayout: RailLayout { shellPreferences.railLayout }
    var appearanceMode: AppearanceMode { shellPreferences.appearanceMode }
    /// The glass style in force.
    ///
    /// Below macOS 26 this is always `.off`, whatever the stored preference
    /// says, so the shell renders one predictable way rather than reading a
    /// setting the user was never offered.
    var liquidGlassStyle: ShellGlassStyle {
        AppCapabilities.liquidGlassSupported ? shellPreferences.liquidGlassStyle : .off
    }
    var liquidGlassIntensity: Double { shellPreferences.liquidGlassIntensity }
    var iconRailBaseSize: Double { shellPreferences.iconRailBaseSize }
    var iconRailMagnificationEnabled: Bool {
        shellPreferences.iconRailMagnificationEnabled
    }
    var iconRailMagnifiedSize: Double { shellPreferences.iconRailMagnifiedSize }
    var iconRailPosition: DockRailPosition { shellPreferences.iconRailPosition }
    var workspaceViewMode: WorkspaceViewMode { shellPreferences.workspaceViewMode }
    var railBarIconsOnly: Bool { shellPreferences.railBarIconsOnly }

    /// What each workspace was last left on. See `WorkspaceServiceMemory`.
    @ObservationIgnored private var workspaceSelection = WorkspaceSelectionStore()
    var sidebarCollapsed: Bool { shellPreferences.sidebarCollapsed }

    @ObservationIgnored private var lastEffectiveShellAppearanceDark: Bool?
    var iconRailMagnification: Double {
        shellPreferences.iconRailMagnification
    }

    /// The color scheme to force on the app, or nil to follow the system.
    var appearanceColorScheme: ColorScheme? {
        switch appearanceMode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    /// Tokens for the NSWorkspace app-lock observer, removed in `shutdown()`.
    /// AppState lives for the whole process, so `shutdown()` is its one
    /// teardown; there is no `deinit`. Not observed UI state, so
    /// `@ObservationIgnored`.
    @ObservationIgnored private var systemObserverTokens: [NSObjectProtocol] = []

    /// Tokens for `DistributedNotificationCenter` screen-lock observers,
    /// removed in `shutdown()`.
    @ObservationIgnored private var distributedObserverTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var launchPreloadTask: Task<Void, Never>?
    @ObservationIgnored private var workspacePreloadTask: Task<Void, Never>?

    var scheduledDNDEnabled: Bool { notificationRuntime.scheduledDNDEnabled }
    var dndStartMinutes: Int { notificationRuntime.dndStartMinutes }
    var dndEndMinutes: Int { notificationRuntime.dndEndMinutes }

    /// Shows the main window after a request that arrives from outside it, such
    /// as a click on a macOS notification. `AppModel` fills this callback with
    /// the AppKit route. It is a route out of the app state, not view state, so
    /// it is `@ObservationIgnored`.
    @ObservationIgnored var bringMainWindowForward: @MainActor () -> Void = {}

    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasShutDown = false

    /// App lock (Touch ID / password), loaded from `PreferencesStore`. `isLocked`
    /// drives an opaque cover over the window content in ContentView.
    var appLockEnabled = false
    var lockOnLaunch = true
    var lockOnSleep = true
    @ObservationIgnored var onLockChanged: (@MainActor (Bool) -> Void)?
    var isLocked = false {
        didSet {
            notificationManager.setAppLocked(isLocked)
            onLockChanged?(isLocked)
        }
    }

    /// Global content-blocking toggle, loaded from `PreferencesStore` and changed
    /// through `setContentBlockingEnabled(_:)`.
    var contentBlockingEnabled = true

    /// "Hide annoyances" toggle, loaded from `PreferencesStore` and changed
    /// through `setAnnoyanceBlockingEnabled(_:)`.
    var annoyanceBlockingEnabled = false

    /// Auto-hibernate idle background services. Loaded from `PreferencesStore`.
    var autoHibernateIdleEnabled = false
    /// Idle minutes before auto-hibernation fires. Loaded from `PreferencesStore`.
    var autoHibernateIdleMinutes = 10

    init(
        dataStoreManager: DataStoreManager,
        userScriptManager: UserScriptManager,
        badgeManager: BadgeManager,
        notificationManager: NotificationManager,
        transientBadgeFetcher: TransientBadgeFetcher,
        contentBlocker: ContentBlockerManager,
        webViewPool: WebViewPool,
        networkMonitor: NetworkMonitor
    ) {
        // The current shipping shape, pinned as an explicit `VersionedSchema`.
        // `StoreLoader` opens it through `PaguroMigrationPlan`, so an older
        // store migrates through named, tested stages instead of inference. See
        // `Paguro/Models/Schema/PaguroSchema.swift`.
        let schema = Schema(versionedSchema: PaguroSchemaVCurrent.self)
        // Neither build may use SwiftData's implicit default path. It is
        // `Application Support/default.store` with no bundle id in it, so every
        // non-sandboxed SwiftData app that takes the default opens the same
        // file and migrates it to its own model, dropping the other's tables.
        // Debug builds have sat in their own directory for a while, so a copy
        // run from Xcode never opens the installed release app's data; the
        // release build now moves into one too, for the collision `StoreRelocation`
        // documents. The debug *bundle id* (project.yml) already separates
        // WebKit, Preferences and notifications.
        #if DEBUG
        let debugDir = URL.applicationSupportDirectory.appending(path: "Paguro-debug")
        try? FileManager.default.createDirectory(at: debugDir, withIntermediateDirectories: true)
        let config = ModelConfiguration(schema: schema, url: debugDir.appending(path: "default.store"))
        #else
        let config = ModelConfiguration(schema: schema, url: StoreRelocation.resolveStoreURL())
        #endif
        // A restore the user picked last session, applied before anything opens
        // the store.
        StoreRepair.applyPendingRestore(at: config.url)

        // Snapshot the store before a newly-installed version opens it, so a
        // migration that loses or reshapes data is always recoverable. No-op
        // when the running version is unchanged from the last launch. This runs
        // once here (not inside the open/retry path) so the retry restores from
        // the snapshot it just took rather than overwriting it.
        StoreRepair.backupBeforeMigrationIfNeeded(at: config.url)

        // Note the store's condition BEFORE the open path repairs it — once
        // `tryOpen` has run `repairDanglingLinks`, the damage is gone and the
        // evidence with it. The recovery coordinator keeps this launch state.
        let storeWasDamagedAtLaunch = StoreRepair.hasDanglingLinks(at: config.url)

        // Open the store, self-healing an emptied or unusable store from the
        // newest usable pre-migration snapshot. The outcome drives the banner.
        let (loadedContainer, outcome) = StoreLoader.load(schema: schema, config: config)
        self.modelContainer = loadedContainer
        let preferencesStore = PreferencesStore(context: loadedContainer.mainContext)
        self.preferencesStore = preferencesStore
        self.workspaceStore = WorkspaceStore(
            context: loadedContainer.mainContext,
            preferencesStore: preferencesStore
        )
        self.shellPreferences = ShellPreferences.load(
            preferencesStore: preferencesStore
        )
        self.mediaPermissions = MediaPermissionCoordinator(
            context: loadedContainer.mainContext,
            preferencesStore: preferencesStore,
            webViewPool: webViewPool
        )
        let storeRecovery = StoreRecoveryCoordinator(
            context: loadedContainer.mainContext,
            storeURL: config.url,
            outcome: outcome,
            wasDamagedAtLaunch: storeWasDamagedAtLaunch
        )
        self.storeRecovery = storeRecovery
        self.websiteDataReclaimer = WebsiteDataReclaimer(
            context: loadedContainer.mainContext,
            dataStoreManager: dataStoreManager,
            isSafeToReclaim: storeRecovery.isSafeToReclaim
        )
        self.hibernationScheduler = HibernationScheduler(
            context: loadedContainer.mainContext,
            webViewPool: webViewPool
        )
        let notificationRuntime = NotificationRuntime(
            context: loadedContainer.mainContext,
            preferencesStore: preferencesStore,
            badgeManager: badgeManager,
            notificationManager: notificationManager,
            transientBadgeFetcher: transientBadgeFetcher,
            webViewPool: webViewPool,
            networkMonitor: networkMonitor,
            contentBlocker: contentBlocker
        )
        self.notificationRuntime = notificationRuntime

        self.dataStoreManager = dataStoreManager
        self.userScriptManager = userScriptManager
        self.userScriptManager.notificationLockSnapshot = notificationManager.lockSnapshot
        self.badgeManager = badgeManager

        self.userScriptManager.isServiceMuted = { serviceID in
            notificationRuntime.isServiceEffectivelyMuted(serviceID)
        }
        self.userScriptManager.isServiceNotifyingOS = { serviceID in
            notificationRuntime.isServiceNotifyingOS(serviceID)
        }
        self.userScriptManager.isDoNotDisturbActive = {
            notificationRuntime.isDoNotDisturbActive()
        }
        self.contentBlocker = contentBlocker
        self.webViewPool = webViewPool

        loadAppPreferences()
    }

    /// Connects process-lifetime work after AppKit finishes launching.
    /// Repeated calls and calls after shutdown are no-ops.
    func start() {
        guard !hasStarted, !hasShutDown else { return }
        hasStarted = true

        setupLockObservers()
        startContentBlocker()
        hibernationScheduler.start(
            globalEnabled: autoHibernateIdleEnabled,
            globalIdleMinutes: autoHibernateIdleMinutes,
            isLocked: { [weak self] in self?.isLocked ?? true },
            onServiceHibernated: { [weak notificationRuntime] in
                notificationRuntime?.serviceHibernated($0)
            },
            onServiceSoftHibernated: { [weak notificationRuntime] in
                notificationRuntime?.serviceSoftHibernated($0)
            },
            onServiceRemoved: { [weak notificationRuntime] in
                notificationRuntime?.serviceRemoved($0)
            }
        )
        setupExternalLinkRouting()
        webViewPool.downloadTracker = downloadTracker
        mediaPermissions.start(
            isLocked: { [weak self] in self?.isLocked ?? true },
            onWebViewRebuilt: { [weak self] in self?.webViewRebuildToken &+= 1 }
        )
        let seedOutcome = workspaceStore.seedDefaultDataIfNeeded()
        selectedSpaceID = seedOutcome.selectedSpaceID
        workspaceStore.backfillPasskeyNoticeIfNeeded(freshInstall: seedOutcome.didSeed)
        websiteDataReclaimer.reapOrphanedServices()
        restoreWindowState()
        notificationRuntime.start(
            currentSpaceID: { [weak self] in self?.selectedSpaceID },
            selectService: { [weak self] spaceID, serviceID in
                if let spaceID { self?.selectedSpaceID = spaceID }
                self?.selectedServiceID = serviceID
            },
            bringWindowForward: { [weak self] in
                self?.bringMainWindowForward()
            }
        )
        let didUpdate = Self.recordLaunchVersionAndCheckUpdate()
        fetchMissingAndStaleFavicons(force: didUpdate)
        fetchCatalogIcons(force: didUpdate)
        preloadActiveSpaceServices()
        notificationRuntime.startTransientBadgeFetcher()
        websiteDataReclaimer.reclaimUnreferencedDataStores()
        websiteDataReclaimer.cleanUpOrphanedDataStores()

        // Evaluate before recording. Recording first could hide the shortfall
        // that produces a recovery offer.
        storeRecovery.evaluateOffer()
        storeRecovery.recordContent()
    }

    /// Stops process-lifetime work and saves the final selection before AppKit
    /// completes a requested quit. Calls after the first one are no-ops.
    func shutdown() async {
        guard !hasShutDown else { return }
        hasShutDown = true

        launchPreloadTask?.cancel()
        launchPreloadTask = nil
        workspacePreloadTask?.cancel()
        workspacePreloadTask = nil
        mediaPermissions.shutdown()
        websiteDataReclaimer.shutdown()
        hibernationScheduler.shutdown()
        notificationRuntime.shutdown()
        contentBlocker.stop()
        downloadTracker.stop()
        webViewPool.shutdown()

        for token in systemObserverTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        systemObserverTokens.removeAll()
        for token in distributedObserverTokens {
            DistributedNotificationCenter.default().removeObserver(token)
        }
        distributedObserverTokens.removeAll()
        saveWindowState()
        storeRecovery.recordContent()
        await Task.yield()
    }

    /// Wires the WebViewPool's external-link handler so that cross-domain
    /// target=_blank navigations route through `handleExternalLink(_:)` —
    /// which prefers switching to a matching Paguro service over opening
    /// Safari, but falls back to NSWorkspace when no service matches.
    private func setupExternalLinkRouting() {
        webViewPool.externalLinkHandler = { [weak self] url, sourceServiceID in
            self?.handleExternalLink(url, from: sourceServiceID)
        }
    }

    /// Decides what to do with a link that the user clicked in one service
    /// and which targets a different origin. If any other Paguro service owns
    /// that domain (same registrable domain, or the exact host for
    /// shared-umbrella domains like google.com) we switch to it (preserving
    /// auth/space context) and navigate to the deep URL. Otherwise we hand off
    /// to the system default browser.
    ///
    /// Multi-account aware: when several services match the same host (e.g.
    /// personal + work Notion), we prefer the match in the current space so
    /// "click a Notion link from Work Slack" lands in Work Notion. Only
    /// crosses spaces when the current space has no match.
    private func handleExternalLink(_ url: URL, from sourceServiceID: UUID?) {
        guard let host = url.host else {
            WebViewCoordinator.openExternally(url)
            return
        }

        if let match = findServiceMatching(host: host, preferringSpace: selectedSpaceID) {
            switchToService(match, navigateTo: url)
            return
        }

        // No Paguro service owns this link. Open it in an in-app window when the
        // source service opted into that; otherwise hand it to the browser.
        let optedIn = sourceServiceID
            .flatMap { fetchService(id: $0) }?
            .opensExternalLinksInAppEffective ?? false
        if WebViewCoordinator.shouldOpenInAppBrowser(sourceOptedIn: optedIn, url: url) {
            InAppBrowserWindow.open(url)
        } else {
            WebViewCoordinator.openExternally(url)
        }
    }

    private func findServiceMatching(host: String, preferringSpace spaceID: UUID?) -> ServiceInstance? {
        workspaceStore.findServiceMatching(host: host, preferringSpace: spaceID)
    }

    private func switchToService(_ service: ServiceInstance, navigateTo url: URL) {
        // Make sure we're in a space that contains this service so the
        // sidebar selection becomes visible. If the service lives in
        // multiple spaces, pick the first.
        if let firstSpace = service.spaceLinks.compactMap(\.liveSpace).first?.id {
            selectedSpaceID = firstSpace
        }
        selectedServiceID = service.id

        // Acquire (or wake) the web view and load the deep URL. webView(for:)
        // marks the service active and handles soft-hibernation of whatever
        // was previously displayed.
        let webView = webViewPool.webView(for: service)
        webView.load(URLRequest(url: url))
    }

    /// Fetches one service by its indexed identifier.
    private func fetchService(id: UUID) -> ServiceInstance? {
        workspaceStore.service(id: id)
    }

    // MARK: - Active service actions (driven by keyboard shortcuts)

    /// Reload the currently displayed service's web view. Triggered by Cmd-R.
    func reloadActiveService() {
        guard let id = webViewPool.activeServiceID,
              let webView = webViewPool.liveWebView(for: id) else { return }
        webView.reload()
    }

    /// Go back one page in the displayed service. Triggered by Cmd-[.
    ///
    /// This uses the attached web-view state rather than the pool, so the menu
    /// item and the header button share one enabled value.
    func goBackInActiveService() {
        webViewState.goBack()
    }

    /// Go forward one page in the displayed service. Triggered by Cmd-].
    func goForwardInActiveService() {
        webViewState.goForward()
    }

    /// Changes one service's native web appearance signal. This updates CSS
    /// `prefers-color-scheme`; it does not recolor the page.
    func setWebAppearance(_ mode: ServiceAppearanceMode, for serviceID: UUID) {
        guard let service = currentServiceInstance(id: serviceID) else { return }
        service.darkModeRaw = mode.rawValue
        service.forceDarkMode = nil
        applyServiceEdits(
            serviceID: serviceID,
            urlChanged: false,
            webAppearanceChanged: true
        )
    }

    /// Keeps automatic web services in step with the effective SwiftUI color
    /// scheme. Explicit light and dark service overrides do not change.
    func updateEffectiveShellAppearance(isDark: Bool) {
        guard lastEffectiveShellAppearanceDark != isDark else { return }
        lastEffectiveShellAppearanceDark = isDark
        webViewPool.applyShellAppearance(isDark: isDark, services: workspaceStore.allServices())
    }

    func setLiquidGlassIntensity(_ value: Double) {
        shellPreferences.setLiquidGlassIntensity(value)
    }

    func setLiquidGlassStyle(_ style: ShellGlassStyle) {
        shellPreferences.setLiquidGlassStyle(style)
    }

    func resetGlassLab() {
        shellPreferences.resetGlass()
    }

    func setIconRailBaseSize(_ value: Double) {
        shellPreferences.setIconRailBaseSize(value)
    }

    func setIconRailMagnification(_ value: Double) {
        shellPreferences.setIconRailMagnification(value)
    }

    func setIconRailPosition(_ position: DockRailPosition) {
        shellPreferences.setIconRailPosition(position)
    }

    func setWorkspaceViewMode(_ mode: WorkspaceViewMode) {
        shellPreferences.setWorkspaceViewMode(mode)
    }

    func setRailBarIconsOnly(_ iconsOnly: Bool) {
        shellPreferences.setRailBarIconsOnly(iconsOnly)
    }

    func setSidebarCollapsed(_ collapsed: Bool) {
        shellPreferences.setSidebarCollapsed(collapsed)
    }

    func setShowBadgeCountInDock(_ enabled: Bool) {
        notificationRuntime.setShowBadgeCountInDock(enabled)
    }

    func setAppearanceMode(_ mode: AppearanceMode) {
        shellPreferences.setAppearanceMode(mode, preferencesStore: preferencesStore)
    }

    func setRailLayout(_ layout: RailLayout) {
        shellPreferences.setRailLayout(layout, preferencesStore: preferencesStore)
    }

    func setAutoDismissCookieBanners(_ enabled: Bool) {
        guard preferencesStore.setAutoDismissCookieBanners(enabled) else { return }
        userScriptManager.autoDismissCookieBanners = enabled
    }

    /// Applies user edits to a service, commits them, and then synchronizes the
    /// saved hibernation policy with the runtime scheduler.
    func applyServiceEdits(
        serviceID: UUID,
        urlChanged: Bool,
        cssChanged: Bool = false,
        userAgentChanged: Bool = false,
        webAppearanceChanged: Bool = false,
        presenceChanged: Bool = false
    ) {
        guard let service = workspaceStore.commitServiceEdits(serviceID: serviceID) else { return }
        if cssChanged || presenceChanged {
            // Custom CSS and the focus override are both injected when the web
            // view is built, so rebuild it. The rebuild also re-bakes the
            // web appearance and picks up any user-agent change and the new
            // URL, so those are handled here.
            webViewPool.recreateWebView(for: serviceID, preserveURL: !urlChanged)
            webViewRebuildToken &+= 1
        } else {
            // Web appearance changes live without a rebuild or page recoloring.
            if webAppearanceChanged {
                webViewPool.refreshWebAppearance(for: service)
            }
            if userAgentChanged {
                webViewPool.setUserAgent(service.userAgent, for: serviceID)
            }
            if urlChanged, let url = URL(string: service.url) {
                webViewPool.navigate(serviceID, to: url)
            }
        }

        hibernationScheduler.servicePolicyDidChange(serviceID)
    }

    /// Wipes all website data (cookies, local/session storage, caches) for a
    /// service's data store — effectively logging the user out — then reloads
    /// the live web view so the logged-out state is visible immediately. The
    /// service itself, its links, and its place in every space are preserved.
    func clearSession(for serviceID: UUID) {
        guard let target = workspaceStore.sessionTarget(for: serviceID) else { return }
        let store = dataStoreManager.dataStore(forIdentifier: target.dataStoreIdentifier)
        let pool = webViewPool
        Task { @MainActor in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
            if let webView = pool.liveWebView(for: serviceID) {
                if let homeURL = target.homeURL {
                    webView.load(URLRequest(url: homeURL))
                } else {
                    webView.reload()
                }
            }
            AppLogger.dataStore.info("Cleared session for service \(serviceID)")
        }
    }

    /// Multiply the active service's page zoom by `factor`, clamped to 0.5x–3.0x.
    /// The new zoom is persisted on the ServiceInstance so it survives
    /// hibernation, relaunch, and switching back and forth.
    func adjustActiveServiceZoom(by factor: Double) {
        guard let id = webViewPool.activeServiceID,
              let webView = webViewPool.liveWebView(for: id),
              let service = currentServiceInstance(id: id) else { return }
        let target = max(0.5, min(3.0, WorkspaceStore.effectiveZoom(
            pageZoom: service.pageZoom,
            defaultZoom: defaultZoom
        ) * factor))
        applyZoom(target, to: webView, service: service)
    }

    /// The effective zoom for a specific service, using the current global default.
    func effectiveZoom(for service: ServiceInstance) -> Double {
        WorkspaceStore.effectiveZoom(pageZoom: service.pageZoom, defaultZoom: defaultZoom)
    }

    /// Saves a new Paguro-wide default zoom and applies it to every open service
    /// that has no explicit per-service zoom.
    func setDefaultZoom(_ zoom: Double) {
        guard let outcome = workspaceStore.setDefaultZoom(zoom) else { return }
        defaultZoom = outcome.zoom
        for serviceID in outcome.affectedServiceIDs {
            webViewPool.liveWebView(for: serviceID)?.pageZoom = CGFloat(outcome.zoom)
        }
    }

    func setScheduledDNDEnabled(_ enabled: Bool) {
        notificationRuntime.setScheduledDNDEnabled(enabled)
    }

    func setDNDStartMinutes(_ minutes: Int) {
        notificationRuntime.setDNDStartMinutes(minutes)
    }

    func setDNDEndMinutes(_ minutes: Int) {
        notificationRuntime.setDNDEndMinutes(minutes)
    }

    /// Turns auto-hibernation on/off, persists it, and starts or stops the sweep.
    func setAutoHibernateIdleEnabled(_ enabled: Bool) {
        guard preferencesStore.setAutoHibernateIdleEnabled(enabled) else { return }
        autoHibernateIdleEnabled = enabled
        hibernationScheduler.configure(
            globalEnabled: autoHibernateIdleEnabled,
            globalIdleMinutes: autoHibernateIdleMinutes
        )
    }

    func setAutoHibernateIdleMinutes(_ minutes: Int) {
        let resolvedMinutes = min(120, max(1, minutes))
        guard preferencesStore.setAutoHibernateIdleMinutes(resolvedMinutes) else { return }
        autoHibernateIdleMinutes = resolvedMinutes
        hibernationScheduler.configure(
            globalEnabled: autoHibernateIdleEnabled,
            globalIdleMinutes: autoHibernateIdleMinutes
        )
    }

    // MARK: - App lock

    func setAppLockEnabled(_ enabled: Bool) {
        guard preferencesStore.setAppLockEnabled(enabled) else { return }
        appLockEnabled = enabled
    }

    func setLockOnLaunch(_ enabled: Bool) {
        guard preferencesStore.setLockOnLaunch(enabled) else { return }
        lockOnLaunch = enabled
    }

    func setLockOnSleep(_ enabled: Bool) {
        guard preferencesStore.setLockOnSleep(enabled) else { return }
        lockOnSleep = enabled
    }

    /// Shows the lock screen. No-op unless the lock is enabled, so a stray
    /// "Lock Now" can't trap a user who never set it up.
    func lock() {
        guard appLockEnabled else { return }
        isLocked = true
        // Don't leave a capture prompt hanging over the lock screen.
        mediaPermissions.denyAllRequests()
    }

    /// Prompts for Touch ID (with the login password as fallback) and unlocks on
    /// success. If the device can't evaluate the policy at all (no password set),
    /// unlock rather than trap the user out of their app.
    func authenticate() {
        let context = LAContext()
        context.localizedFallbackTitle = "Enter Password"
        var policyError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &policyError) else {
            AppLogger.general.error("App lock: cannot evaluate policy (\(policyError?.localizedDescription ?? "unknown")); unlocking to avoid lockout")
            isLocked = false
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Paguro") { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success {
                    self.isLocked = false
                } else {
                    AppLogger.general.info("App lock: authentication did not succeed (\(error?.localizedDescription ?? "cancelled"))")
                }
            }
        }
    }

    /// Locks when the Mac sleeps or the screen locks, if the user opted in.
    private func setupLockObservers() {
        let lockOnSleepIfNeeded: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in
                guard let self, self.appLockEnabled, self.lockOnSleep else { return }
                self.lock()
            }
        }
        systemObserverTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main, using: lockOnSleepIfNeeded))
        distributedObserverTokens.append(DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"), object: nil, queue: .main, using: lockOnSleepIfNeeded))
    }



    /// Reset the active service's zoom to 1.0. Triggered by Cmd-0.
    func resetActiveServiceZoom() {
        guard let id = webViewPool.activeServiceID,
              let webView = webViewPool.liveWebView(for: id),
              let service = currentServiceInstance(id: id) else { return }
        applyZoom(1.0, to: webView, service: service)
    }

    private func applyZoom(_ value: Double, to webView: WKWebView, service: ServiceInstance) {
        guard workspaceStore.setPageZoom(value, for: service.id) else { return }
        webView.pageZoom = CGFloat(value)
    }

    private func currentServiceInstance(id: UUID) -> ServiceInstance? {
        fetchService(id: id)
    }

    func refreshBadgeState(for serviceID: UUID) {
        notificationRuntime.refreshBadgeState(for: serviceID)
    }

    /// Adds one service and starts post-save runtime work only after the model
    /// commit succeeds.
    @discardableResult
    func addService(
        label: String,
        url: String,
        catalogEntryID: String? = nil,
        userAgent: String? = nil,
        customIconData: Data? = nil,
        to spaceID: UUID
    ) -> UUID? {
        let serviceID: UUID?
        do {
            serviceID = try workspaceStore.addService(
                label: label,
                url: url,
                catalogEntryID: catalogEntryID,
                userAgent: userAgent,
                customIconData: customIconData,
                to: spaceID
            )
        } catch {
            AppLogger.dataStore.error("Failed to add service; rolled back: \(error.localizedDescription)")
            return nil
        }
        guard let serviceID else { return nil }

        selectedSpaceID = spaceID
        selectedServiceID = serviceID
        mediaPermissions.offerPresenceActivationIfNeeded(
            serviceID: serviceID,
            catalogEntryID: catalogEntryID
        )

        if customIconData == nil {
            Task { @MainActor [weak self] in
                await self?.refreshFetchedIcon(for: serviceID)
            }
        }

        return serviceID
    }

    func moveService(linkID: UUID, to targetSpaceID: UUID, followToSpace: Bool) {
        let outcome: WorkspaceStore.ServiceMoveOutcome?
        do {
            outcome = try workspaceStore.moveService(
                linkID: linkID,
                to: targetSpaceID
            )
        } catch {
            AppLogger.dataStore.error("Failed to move service; rolled back: \(error.localizedDescription)")
            return
        }
        guard let outcome else { return }

        let movedSelectedRow = selectedServiceID == outcome.serviceID
            && selectedSpaceID == outcome.sourceSpaceID
        if followToSpace {
            selectedSpaceID = outcome.targetSpaceID
            selectedServiceID = outcome.serviceID
        } else if movedSelectedRow {
            selectedServiceID = nil
        }
    }

    @discardableResult
    func reorderSpace(
        droppedSpaceID: UUID,
        relativeTo targetSpaceID: UUID,
        placement: ServiceReorderPlacement
    ) -> Bool {
        do {
            return try workspaceStore.reorderSpace(
                droppedSpaceID: droppedSpaceID,
                relativeTo: targetSpaceID,
                placement: placement
            )
        } catch {
            AppLogger.dataStore.error(
                "Failed to reorder workspaces; rolled back: \(error.localizedDescription)"
            )
            return false
        }
    }

    func reorderService(
        droppedLinkID: UUID,
        relativeTo targetLinkID: UUID,
        placement: ServiceReorderPlacement
    ) -> Bool {
        do {
            return try workspaceStore.reorderService(
                droppedLinkID: droppedLinkID,
                relativeTo: targetLinkID,
                placement: placement
            )
        } catch {
            AppLogger.dataStore.error("Failed to reorder services; rolled back: \(error.localizedDescription)")
            return false
        }
    }

    func deleteService(_ serviceID: UUID) {
        let outcome: WorkspaceStore.ServiceDeletionOutcome?
        do {
            outcome = try workspaceStore.deleteService(serviceID)
        } catch {
            AppLogger.dataStore.error("Failed to delete service; rolled back: \(error.localizedDescription)")
            return
        }
        guard let outcome else { return }

        if selectedServiceID == outcome.serviceID {
            selectedServiceID = nil
        }
        webViewPool.removeWebView(for: outcome.serviceID)
        websiteDataReclaimer.markOrphaned(outcome.dataStoreIdentifier)
        websiteDataReclaimer.cleanUpOrphanedDataStores()
    }

    func setServiceMuted(_ muted: Bool, for serviceID: UUID) {
        do {
            guard try workspaceStore.setServiceMuted(muted, for: serviceID) else { return }
        } catch {
            AppLogger.dataStore.error("Failed to toggle service mute; rolled back: \(error.localizedDescription)")
            return
        }
        refreshBadgeState(for: serviceID)
    }

    func setWorkspaceMuted(_ muted: Bool, for spaceID: UUID) {
        let serviceIDs: Set<UUID>?
        do {
            serviceIDs = try workspaceStore.setWorkspaceMuted(muted, for: spaceID)
        } catch {
            AppLogger.dataStore.error("Failed to toggle workspace mute; rolled back: \(error.localizedDescription)")
            return
        }
        guard let serviceIDs else { return }
        for serviceID in serviceIDs {
            refreshBadgeState(for: serviceID)
        }
    }

    func pickCustomIcon(for serviceID: UUID) {
        guard let service = currentServiceInstance(id: serviceID) else { return }
        do {
            guard let data = try ServiceIconFilePicker.pickImageData(
                message: "Choose an icon for \(service.label)"
            ) else { return }
            _ = try workspaceStore.setCustomIconData(data, for: serviceID)
        } catch {
            AppLogger.ui.error("Failed to set custom icon: \(error.localizedDescription)")
        }
    }

    func resetIcon(for serviceID: UUID) {
        guard let service = currentServiceInstance(id: serviceID) else { return }
        let shouldFetch = service.fetchedIconData == nil
        do {
            guard try workspaceStore.setCustomIconData(nil, for: serviceID) else { return }
        } catch {
            AppLogger.dataStore.error("Failed to reset icon; rolled back: \(error.localizedDescription)")
            return
        }
        guard shouldFetch else { return }

        Task { @MainActor [weak self] in
            await self?.refreshFetchedIcon(for: serviceID)
        }
    }

    func refreshFetchedIcon(for serviceID: UUID) async {
        await workspaceStore.refreshFetchedIcon(for: serviceID)
    }

    /// Counts the services that Paguro deletes together with this space.
    /// The delete confirmation shows this number.
    func orphanedServiceCount(byDeletingSpace spaceID: UUID) -> Int {
        workspaceStore.orphanedServiceCount(byDeletingSpace: spaceID)
    }

    /// Removes a service from one space. When the service exists in no other
    /// space, it is deleted and its data store is reclaimed — but only after
    /// the save succeeds. A failed save rolls back and changes nothing.
    func removeLink(_ linkID: UUID) {
        let outcome: WorkspaceStore.LinkRemovalOutcome?
        do {
            outcome = try workspaceStore.removeLink(linkID)
        } catch {
            AppLogger.dataStore.error("Failed to remove service from space; rolled back: \(error.localizedDescription)")
            return
        }
        guard let outcome, let dataStoreIdentifier = outcome.orphanedDataStoreIdentifier else { return }
        webViewPool.removeWebView(for: outcome.serviceID)
        websiteDataReclaimer.markOrphaned(dataStoreIdentifier)
        websiteDataReclaimer.cleanUpOrphanedDataStores()
    }

    /// Deletes a space and reclaims any services that lived *only* in it.
    /// A service linked to other spaces is preserved (the delete-confirmation
    /// dialog promises this); a service orphaned by the deletion has its web
    /// view torn down and its on-disk `WKWebsiteDataStore` scheduled for
    /// removal, so deleting a space never leaves invisible orphan records or
    /// leaks per-service storage. Selection is moved off the deleted space.
    func deleteSpace(_ spaceID: UUID) {
        let outcome: WorkspaceStore.SpaceDeletionOutcome?
        do {
            outcome = try workspaceStore.deleteSpace(spaceID)
        } catch {
            AppLogger.dataStore.error(
                "Failed to delete space; rolled back: \(error.localizedDescription)"
            )
            return
        }
        guard let outcome else { return }

        // Save committed — now the destructive cleanup is safe.
        for serviceID in outcome.reclaimedServiceIDs {
            webViewPool.removeWebView(for: serviceID)
        }
        for dataStoreID in outcome.orphanedDataStoreIdentifiers {
            websiteDataReclaimer.markOrphaned(dataStoreID)
        }

        // Fix up selection: clear a selected service that was just reclaimed,
        // and move off the deleted space to the first remaining one.
        if let selected = selectedServiceID,
           outcome.reclaimedServiceIDs.contains(selected) {
            selectedServiceID = nil
        }
        if selectedSpaceID == spaceID {
            selectedSpaceID = outcome.remainingSpaceID
            selectedServiceID = nil
        }
        workspaceSelection.forget(workspaceID: spaceID)

        websiteDataReclaimer.cleanUpOrphanedDataStores()
    }

    func servicesForSpace(_ spaceID: UUID) -> [ServiceInstance] {
        workspaceStore.servicesForSpace(spaceID)
    }

    /// Records what a workspace is left on, so returning to it returns to the
    /// work in it rather than to its first service.
    func rememberSelection(serviceID: UUID, in spaceID: UUID) {
        workspaceSelection.remember(serviceID: serviceID, in: spaceID)
    }

    /// The service a workspace opens on: the one already chosen for it in this
    /// same step, else the one it was left on, else its first.
    func serviceToOpen(in spaceID: UUID, currentServiceID: UUID?) -> UUID? {
        workspaceSelection.serviceToOpen(
            in: spaceID,
            memberServiceIDs: servicesForSpace(spaceID).map(\.id),
            currentServiceID: currentServiceID
        )
    }

    /// Preloads web views for all services in the currently selected space.
    /// Runs after window state is restored so `selectedSpaceID` is already set.
    /// The selected service (if any) loads first, then the rest stagger at 500ms intervals.
    private func preloadActiveSpaceServices() {
        guard let spaceID = selectedSpaceID else { return }
        let services = servicesForSpace(spaceID)
        guard !services.isEmpty else { return }

        // Move the selected service to the front so it preloads first.
        // We can't use sorted { a,_ in a.id == selected } — that violates
        // Swift's strict-weak-ordering and the sort is undefined.
        let selected = selectedServiceID
        var ordered = services
        if let selected, let idx = ordered.firstIndex(where: { $0.id == selected }) {
            let item = ordered.remove(at: idx)
            ordered.insert(item, at: 0)
        }

        // Pin the selected service so the LRU sweep that fires after each
        // preload can't evict it before WebContentView attaches and sets
        // `activeServiceID` (which would otherwise protect it).
        if let selected {
            webViewPool.pin(selected)
        }

        // Chat services in OTHER spaces have to come up too. A service only
        // posts notification banners through the `paguroNotification` handler on
        // a live web view; the transient badge fetcher deliberately omits that
        // handler, so a service with no web view is silent — its badge moves on
        // the 180s sweep and nothing else. Preloading only the selected space
        // therefore made "chat apps stay live so their messages arrive at once"
        // true only inside the space you happened to be looking at, which is why
        // Slack in another space went quiet until it was visited.
        //
        // The pool exempts these from both hibernation sweeps, so once up they
        // stay up.
        let alsoKeepLive = crossSpaceCriticalServices(excluding: Set(services.map(\.id)))

        launchPreloadTask?.cancel()
        launchPreloadTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if let selected {
                    webViewPool.unpin(selected)
                }
            }
            await webViewPool.preloadAll(ordered)
            guard !Task.isCancelled else { return }
            if !alsoKeepLive.isEmpty {
                // Read the count before the logger does. `Logger` builds its
                // message through a Sendable autoclosure, so interpolating
                // `alsoKeepLive.count` directly captures the array itself and
                // defers the read, which sends a non-Sendable SwiftData model
                // out of this isolation. An Int carries no such problem.
                let keepLiveCount = alsoKeepLive.count
                AppLogger.webView.info("Preloading \(keepLiveCount) chat service(s) outside the active space so they can post notifications")
                await webViewPool.preloadAll(alsoKeepLive)
            }
        }
    }

    /// Notification-critical services that the active-space preload won't cover,
    /// capped so they cannot fill the pool.
    ///
    /// The cap matters because these are exempt from eviction: without one, a
    /// user with more chat services than `WebViewPool.maxLoaded` would pin every
    /// slot permanently and the LRU sweep would have nothing left to reclaim.
    /// The order is the fetch's, made deterministic by sorting on id so the same
    /// services win the cap on every launch rather than a different set each time.
    private func crossSpaceCriticalServices(excluding covered: Set<UUID>) -> [ServiceInstance] {
        return Self.criticalServicesToKeepLive(
            among: workspaceStore.allServices(),
            covered: covered,
            limit: Self.maxCrossSpaceCriticalServices
        )
    }

    /// The selection rule behind `crossSpaceCriticalServices`, split out so the
    /// exclusion, the critical test, the deterministic order and the cap are
    /// testable without a running pool.
    static func criticalServicesToKeepLive(
        among services: [ServiceInstance],
        covered: Set<UUID>,
        limit: Int
    ) -> [ServiceInstance] {
        guard limit > 0 else { return [] }
        return services
            .filter { !covered.contains($0.id) && $0.isNotificationCritical }
            .sorted { $0.id.uuidString < $1.id.uuidString }
            .prefix(limit)
            .map { $0 }
    }

    /// How many chat services outside the active space are kept live. Held well
    /// below `WebViewPool.maxLoaded` so the active space and the LRU sweep keep
    /// room to work.
    static let maxCrossSpaceCriticalServices = 5

    /// Preloads services when the user switches to a different space.
    func preloadServicesForSpace(_ spaceID: UUID) {
        let services = servicesForSpace(spaceID)
        workspacePreloadTask?.cancel()
        workspacePreloadTask = Task {
            await webViewPool.preloadAll(services)
        }
    }

    private func fetchCatalogIcons(force: Bool = false) {
        let entries = ServiceCatalog.shared.entries
        Task.detached(priority: .utility) {
            await CatalogIconCache.shared.fetchAllIfNeeded(entries: entries, force: force)
        }
    }

    /// Records the current app version and reports whether this launch follows an
    /// update (a different version ran last time). Used to refresh the icon caches
    /// so a release that adds or changes icons shows them at once, instead of
    /// waiting out the weekly staleness timer.
    private static func recordLaunchVersionAndCheckUpdate() -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let previous = UserDefaults.standard.string(forKey: DefaultsKey.lastRunAppVersion)
        if !current.isEmpty {
            UserDefaults.standard.set(current, forKey: DefaultsKey.lastRunAppVersion)
        }
        return shouldBustCachesOnLaunch(previousVersion: previous, currentVersion: current)
    }

    /// Pure launch-vs-update decision: bust caches only when a real, different
    /// prior version is known. A fresh install (no previous) has no stale cache,
    /// and an unknown current version can't be compared, so both leave caches be.
    static func shouldBustCachesOnLaunch(previousVersion: String?, currentVersion: String) -> Bool {
        guard !currentVersion.isEmpty, let previousVersion, !previousVersion.isEmpty else { return false }
        return previousVersion != currentVersion
    }

    func saveWindowState() {
        workspaceStore.saveWindowSelection(
            spaceID: selectedSpaceID,
            serviceID: selectedServiceID
        )
    }

    private func loadAppPreferences() {
        // This runs during construction, before AppKit finishes launching.
        // Only load values here. `start()` applies platform side effects.
        userScriptManager.autoDismissCookieBanners = preferencesStore.autoDismissCookieBanners
        defaultZoom = preferencesStore.defaultZoom
        appLockEnabled = preferencesStore.appLockEnabled
        lockOnLaunch = preferencesStore.lockOnLaunch
        lockOnSleep = preferencesStore.lockOnSleep
        contentBlockingEnabled = preferencesStore.contentBlockingEnabled
        annoyanceBlockingEnabled = preferencesStore.annoyanceBlockingEnabled
        let googleFallback = preferencesStore.googleFaviconFallbackEnabled
        Task { await FaviconFetcher.shared.setGoogleFallbackEnabled(googleFallback) }
        autoHibernateIdleEnabled = preferencesStore.autoHibernateIdleEnabled
        autoHibernateIdleMinutes = preferencesStore.autoHibernateIdleMinutes
        // Start locked at launch when opted in; ContentView's lock overlay
        // prompts for Touch ID on appear.
        if appLockEnabled && lockOnLaunch {
            isLocked = true
        }

    }

    /// Kicks off content-blocklist compilation at launch (before preload, so it
    /// usually finishes before the first web view is built). Syncs the enabled
    /// state from prefs and, once the lists are ready, re-attaches them to any
    /// web views that were built first.
    private func startContentBlocker() {
        contentBlocker.isEnabled = contentBlockingEnabled
        contentBlocker.annoyanceEnabled = annoyanceBlockingEnabled
        contentBlocker.onReady = { [weak self] in
            // Lists finished compiling after some web views were already built —
            // attach them in place (no teardown, no reload, no lost polling).
            self?.webViewPool.reattachContentBlocker()
        }
        contentBlocker.start()
    }

    /// Flips the global content blocker, persists it, and rebuilds live web
    /// views so the change takes effect immediately.
    func setContentBlockingEnabled(_ enabled: Bool) {
        guard preferencesStore.setContentBlockingEnabled(enabled) else { return }
        contentBlockingEnabled = enabled
        contentBlocker.isEnabled = enabled
        webViewPool.reattachContentBlocker()
    }

    /// Opts in or out of the Google favicon fallback and persists the choice.
    /// Pushes the flag into the fetcher actor so later fetches pick it up.
    func setGoogleFaviconFallbackEnabled(_ enabled: Bool) {
        guard preferencesStore.setGoogleFaviconFallbackEnabled(enabled) else { return }
        Task { await FaviconFetcher.shared.setGoogleFallbackEnabled(enabled) }
    }

    /// Flips annoyance hiding, persists it, and re-attaches lists to live views.
    func setAnnoyanceBlockingEnabled(_ enabled: Bool) {
        guard preferencesStore.setAnnoyanceBlockingEnabled(enabled) else { return }
        annoyanceBlockingEnabled = enabled
        contentBlocker.annoyanceEnabled = enabled
        webViewPool.reattachContentBlocker()
    }

    private func restoreWindowState() {
        let selection = workspaceStore.restoredWindowSelection(
            fallbackSpaceID: selectedSpaceID,
            fallbackServiceID: selectedServiceID
        )
        selectedSpaceID = selection.spaceID
        selectedServiceID = selection.serviceID
    }

    /// Fetches favicons for services that have none cached, and refreshes
    /// stale favicons (older than 7 days). Runs in a background Task to avoid
    /// blocking app launch.
    private func fetchMissingAndStaleFavicons(force: Bool = false) {
        let serviceIDs = workspaceStore.serviceIDsNeedingFaviconRefresh(force: force)
        guard !serviceIDs.isEmpty else { return }
        AppLogger.favicon.info("Fetching favicons for \(serviceIDs.count) service(s)")

        Task { @MainActor [weak self] in
            guard let self else { return }
            for serviceID in serviceIDs {
                await self.refreshFetchedIcon(for: serviceID)
            }
            AppLogger.favicon.info("Favicon refresh complete")
        }
    }

    /// Whether the passkey-limitation banner should show for `service` — true
    /// until the notice has been seen once for that service.
    func shouldShowPasskeyNotice(for service: ServiceInstance) -> Bool {
        service.needsPasskeyNotice
    }

    /// Records that the passkey notice has been shown for the given service so
    /// it never appears again for it.
    func markPasskeyNoticeSeen(for serviceID: UUID) {
        workspaceStore.markPasskeyNoticeSeen(for: serviceID)
    }
}

extension AppState {
    /// Synchronizes runtime adapters after the configuration transaction commits.
    func applyImportedPreferences(_ value: ConfigurationPreferences) {
        shellPreferences = ShellPreferences.load(preferencesStore: preferencesStore)
        shellPreferences.applyConfiguration(value)
        userScriptManager.autoDismissCookieBanners = preferencesStore.autoDismissCookieBanners
        defaultZoom = preferencesStore.defaultZoom
        for service in workspaceStore.allServices() where service.pageZoom == nil {
            webViewPool.liveWebView(for: service.id)?.pageZoom = CGFloat(defaultZoom)
        }
        appLockEnabled = preferencesStore.appLockEnabled
        lockOnLaunch = preferencesStore.lockOnLaunch
        lockOnSleep = preferencesStore.lockOnSleep
        contentBlockingEnabled = preferencesStore.contentBlockingEnabled
        annoyanceBlockingEnabled = preferencesStore.annoyanceBlockingEnabled
        contentBlocker.isEnabled = contentBlockingEnabled
        contentBlocker.annoyanceEnabled = annoyanceBlockingEnabled
        webViewPool.reattachContentBlocker()
        let googleFallback = preferencesStore.googleFaviconFallbackEnabled
        Task { await FaviconFetcher.shared.setGoogleFallbackEnabled(googleFallback) }
        autoHibernateIdleEnabled = preferencesStore.autoHibernateIdleEnabled
        autoHibernateIdleMinutes = preferencesStore.autoHibernateIdleMinutes
        hibernationScheduler.configure(globalEnabled: autoHibernateIdleEnabled,
                                       globalIdleMinutes: autoHibernateIdleMinutes)
        notificationRuntime.reloadConfigurationPreferences()
        mediaPermissions.reloadConfigurationPreferences()
    }
}

extension AppState {
    /// Session removal starts only after the replacement transaction commits.
    func finishConfigurationImport(
        _ outcome: WorkspaceStore.ConfigurationImportOutcome,
        mode: ConfigurationImportMode
    ) {
        if mode == .replace {
            launchPreloadTask?.cancel()
            workspacePreloadTask?.cancel()
            selectedServiceID = nil
            selectedSpaceID = outcome.firstWorkspaceID
            for id in outcome.removedWorkspaceIDs { workspaceSelection.forget(workspaceID: id) }
            for service in outcome.removedServices {
                webViewPool.removeWebView(for: service.serviceID)
                websiteDataReclaimer.markOrphaned(service.dataStoreIdentifier)
            }
            websiteDataReclaimer.cleanUpOrphanedDataStores()
            saveWindowState()
        } else if selectedSpaceID == nil {
            selectedSpaceID = outcome.firstWorkspaceID
        }
    }
}
