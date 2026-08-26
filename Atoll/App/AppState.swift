import SwiftUI
import SwiftData
import WebKit
import LocalAuthentication
import AtollCore

@MainActor
@Observable
final class AppState {
    let modelContainer: ModelContainer
    let preferencesStore: PreferencesStore
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
    /// Both window layouts use this state for reload and stop.
    let webViewState = WebViewState()
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

    /// Atoll-wide default page zoom, applied to services without an explicit
    /// per-service zoom. Loaded from `PreferencesStore` at launch.
    var defaultZoom: Double = 1.0

    var railLayout: RailLayout { shellPreferences.railLayout }
    var appearanceMode: AppearanceMode { shellPreferences.appearanceMode }
    var liquidGlassStyle: ShellGlassStyle { shellPreferences.liquidGlassStyle }
    var liquidGlassIntensity: Double { shellPreferences.liquidGlassIntensity }
    var iconRailBaseSize: Double { shellPreferences.iconRailBaseSize }
    var iconRailMagnificationEnabled: Bool {
        shellPreferences.iconRailMagnificationEnabled
    }
    var iconRailMagnifiedSize: Double { shellPreferences.iconRailMagnifiedSize }
    var iconRailPosition: DockRailPosition { shellPreferences.iconRailPosition }
    var workspaceViewMode: WorkspaceViewMode { shellPreferences.workspaceViewMode }

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

    var scheduledDNDEnabled: Bool { notificationRuntime.scheduledDNDEnabled }
    var dndStartMinutes: Int { notificationRuntime.dndStartMinutes }
    var dndEndMinutes: Int { notificationRuntime.dndEndMinutes }
    @ObservationIgnored private var hasShutDown = false

    /// App lock (Touch ID / password), loaded from `PreferencesStore`. `isLocked`
    /// drives an opaque cover over the window content in ContentView.
    var appLockEnabled = false
    var lockOnLaunch = true
    var lockOnSleep = true
    var isLocked = false

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
        // `StoreLoader` opens it through `AtollMigrationPlan`, so an older
        // store migrates through named, tested stages instead of inference. See
        // `Atoll/Models/Schema/AtollSchema.swift`.
        let schema = Schema(versionedSchema: AtollSchemaVCurrent.self)
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
        let debugDir = URL.applicationSupportDirectory.appending(path: "Atoll-debug")
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
        self.badgeManager = badgeManager

        self.userScriptManager.isServiceMuted = { @Sendable serviceID in
            notificationRuntime.isServiceEffectivelyMuted(serviceID)
        }
        self.userScriptManager.isServiceNotifyingOS = { @Sendable serviceID in
            notificationRuntime.isServiceNotifyingOS(serviceID)
        }
        self.userScriptManager.isDoNotDisturbActive = { @Sendable in
            notificationRuntime.isDoNotDisturbActive()
        }
        self.contentBlocker = contentBlocker
        self.webViewPool = webViewPool

        loadAppPreferences()
        startContentBlocker()
        notificationRuntime.start(
            currentSpaceID: { [weak self] in self?.selectedSpaceID },
            selectService: { [weak self] spaceID, serviceID in
                if let spaceID { self?.selectedSpaceID = spaceID }
                self?.selectedServiceID = serviceID
            }
        )
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
        mediaPermissions.start(
            isLocked: { [weak self] in self?.isLocked ?? true },
            onWebViewRebuilt: { [weak self] in self?.webViewRebuildToken &+= 1 }
        )
        let didSeedDefaults = seedDefaultDataIfNeeded()
        backfillPasskeyNoticeIfNeeded(freshInstall: didSeedDefaults)
        websiteDataReclaimer.reapOrphanedServices()
        restoreWindowState()
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

        mediaPermissions.shutdown()
        websiteDataReclaimer.shutdown()
        hibernationScheduler.shutdown()
        notificationRuntime.shutdown()
        contentBlocker.stop()
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
    /// which prefers switching to a matching Atoll service over opening
    /// Safari, but falls back to NSWorkspace when no service matches.
    private func setupExternalLinkRouting() {
        webViewPool.externalLinkHandler = { [weak self] url, sourceServiceID in
            self?.handleExternalLink(url, from: sourceServiceID)
        }
    }

    /// Decides what to do with a link that the user clicked in one service
    /// and which targets a different origin. If any other Atoll service owns
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

        // No Atoll service owns this link. Open it in an in-app window when the
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
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ServiceInstance>()
        guard let services = try? context.fetch(descriptor) else { return nil }

        let matches = services.filter { service in
            guard let serviceHost = URL(string: service.url)?.host else { return false }
            return WebRoutingPolicy.belongsToService(host, serviceHost: serviceHost)
        }
        if matches.isEmpty { return nil }
        if matches.count == 1 { return matches.first }

        // Multiple instances of the same site (e.g. personal + work Notion).
        // Prefer one inside the current space; fall back to any match.
        if let spaceID,
           let inCurrentSpace = matches.first(where: { service in
               service.spaceLinks.contains {
                   $0.modelContext != nil && $0.space.modelContext != nil && $0.space.id == spaceID
               }
           }) {
            return inCurrentSpace
        }
        return matches.first
    }

    private func switchToService(_ service: ServiceInstance, navigateTo url: URL) {
        // Make sure we're in a space that contains this service so the
        // sidebar selection becomes visible. If the service lives in
        // multiple spaces, pick the first.
        if let firstSpace = service.spaceLinks.first(where: {
            $0.modelContext != nil && $0.space.modelContext != nil
        })?.space.id {
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
        var descriptor = FetchDescriptor<ServiceInstance>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? modelContainer.mainContext.fetch(descriptor).first
    }

    // MARK: - Active service actions (driven by keyboard shortcuts)

    /// Reload the currently displayed service's web view. Triggered by Cmd-R.
    func reloadActiveService() {
        guard let id = webViewPool.activeServiceID,
              let webView = webViewPool.liveWebView(for: id) else { return }
        webView.reload()
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
        let services = (try? modelContainer.mainContext.fetch(
            FetchDescriptor<ServiceInstance>()
        )) ?? []
        webViewPool.applyShellAppearance(isDark: isDark, services: services)
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
        guard let service = currentServiceInstance(id: serviceID) else { return }
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

        guard modelContainer.mainContext.saveOrRollback(reason: "save service edits") else {
            return
        }
        hibernationScheduler.servicePolicyDidChange(serviceID)
    }

    /// Wipes all website data (cookies, local/session storage, caches) for a
    /// service's data store — effectively logging the user out — then reloads
    /// the live web view so the logged-out state is visible immediately. The
    /// service itself, its links, and its place in every space are preserved.
    func clearSession(for serviceID: UUID) {
        guard let service = currentServiceInstance(id: serviceID) else { return }
        let store = dataStoreManager.dataStore(forIdentifier: service.dataStoreIdentifier)
        let homeURL = URL(string: service.url)
        let pool = webViewPool
        Task { @MainActor in
            let types = WKWebsiteDataStore.allWebsiteDataTypes()
            await store.removeData(ofTypes: types, modifiedSince: .distantPast)
            if let webView = pool.liveWebView(for: serviceID) {
                if let homeURL {
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
        let target = max(0.5, min(3.0, Self.effectiveZoom(pageZoom: service.pageZoom, defaultZoom: defaultZoom) * factor))
        applyZoom(target, to: webView, service: service)
    }

    /// The zoom a service should render at: its own explicit zoom if set,
    /// otherwise the Atoll-wide default. Pure so it can be unit-tested.
    static func effectiveZoom(pageZoom: Double?, defaultZoom: Double) -> Double {
        pageZoom ?? defaultZoom
    }

    /// The effective zoom for a specific service, using the current global default.
    func effectiveZoom(for service: ServiceInstance) -> Double {
        Self.effectiveZoom(pageZoom: service.pageZoom, defaultZoom: defaultZoom)
    }

    /// Saves a new Atoll-wide default zoom and applies it to every open service
    /// that has no explicit per-service zoom.
    func setDefaultZoom(_ zoom: Double) {
        let clamped = max(0.5, min(3.0, zoom))
        guard preferencesStore.setDefaultZoom(clamped) else { return }
        defaultZoom = clamped
        let services = (try? modelContainer.mainContext.fetch(FetchDescriptor<ServiceInstance>())) ?? []
        for service in services where service.pageZoom == nil {
            webViewPool.liveWebView(for: service.id)?.pageZoom = CGFloat(clamped)
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
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock Atoll") { [weak self] success, error in
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
        webView.pageZoom = CGFloat(value)
        service.pageZoom = value
        modelContainer.mainContext.saveOrRollback(reason: "persist zoom")
    }

    private func currentServiceInstance(id: UUID) -> ServiceInstance? {
        fetchService(id: id)
    }

    func refreshBadgeState(for serviceID: UUID) {
        notificationRuntime.refreshBadgeState(for: serviceID)
    }

    struct ServiceMoveOutcome: Equatable {
        let serviceID: UUID
        let sourceSpaceID: UUID
        let targetSpaceID: UUID
    }

    struct ServiceDeletionOutcome: Equatable {
        let serviceID: UUID
        let dataStoreIdentifier: UUID
    }

    /// Inserts one service at the end of a space and saves it.
    static func addService(
        label: String,
        url: String,
        catalogEntryID: String? = nil,
        userAgent: String? = nil,
        customIconData: Data? = nil,
        to spaceID: UUID,
        in context: ModelContext
    ) throws -> UUID? {
        var descriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == spaceID }
        )
        descriptor.fetchLimit = 1
        guard let space = try context.fetch(descriptor).first else { return nil }
        let nextOrder = ((try liveLinks(in: context))
            .filter { $0.space.id == spaceID }
            .map(\.sortOrder)
            .max() ?? -1) + 1

        let service = ServiceInstance(
            label: label,
            url: url,
            customIconData: customIconData,
            catalogEntryID: catalogEntryID,
            userAgent: userAgent
        )
        context.insert(service)
        context.insert(SpaceServiceLink(
            sortOrder: nextOrder,
            space: space,
            service: service
        ))
        guard context.saveOrRollback(reason: "add service") else { return nil }
        return service.id
    }

    /// Relocates one existing link to the end of another space and saves it.
    /// A fresh fetch supplies both membership and target ordering because
    /// SwiftData inverse relationships can lag behind unsaved changes.
    static func moveService(
        linkID: UUID,
        to targetSpaceID: UUID,
        in context: ModelContext
    ) throws -> ServiceMoveOutcome? {
        let links = try liveLinks(in: context)
        guard let link = links.first(where: { $0.id == linkID }) else { return nil }
        let sourceSpaceID = link.space.id
        let serviceID = link.service.id
        guard sourceSpaceID != targetSpaceID else { return nil }

        var targetDescriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == targetSpaceID }
        )
        targetDescriptor.fetchLimit = 1
        guard let targetSpace = try context.fetch(targetDescriptor).first else { return nil }
        guard !links.contains(where: {
            $0.id != linkID
                && $0.service.id == serviceID
                && $0.space.id == targetSpaceID
        }) else { return nil }

        let targetOrders = links
            .filter { $0.space.id == targetSpaceID }
            .map(\.sortOrder)
        link.sortOrder = (targetOrders.max() ?? -1) + 1
        link.space = targetSpace
        guard context.saveOrRollback(reason: "move service") else { return nil }
        return ServiceMoveOutcome(
            serviceID: serviceID,
            sourceSpaceID: sourceSpaceID,
            targetSpaceID: targetSpaceID
        )
    }

    /// Applies a drag or accessibility reorder inside one space and saves it.
    static func reorderService(
        droppedLinkID: UUID,
        relativeTo targetLinkID: UUID,
        placement: ServiceReorderPlacement,
        in context: ModelContext
    ) throws -> Bool {
        let links = try liveLinks(in: context)
        guard let droppedLink = links.first(where: { $0.id == droppedLinkID }),
              let targetLink = links.first(where: { $0.id == targetLinkID }),
              WorkspaceNavigationPolicy.allowsReorder(
                sourceWorkspaceID: droppedLink.space.id,
                targetWorkspaceID: targetLink.space.id
              )
        else { return false }

        let spaceLinks = links
            .filter { $0.space.id == targetLink.space.id }
            .sorted { $0.sortOrder < $1.sortOrder }
        let linksByID = Dictionary(uniqueKeysWithValues: spaceLinks.map { ($0.id, $0) })
        guard let reorderedIDs = ServiceReorder.reorderedIDs(
            spaceLinks.map(\.id),
            moving: droppedLinkID,
            relativeTo: targetLinkID,
            placement: placement
        ) else { return false }

        let reorderedLinks = reorderedIDs.compactMap { linksByID[$0] }
        guard reorderedLinks.count == reorderedIDs.count else { return false }
        for (index, link) in reorderedLinks.enumerated() {
            link.sortOrder = index
        }
        guard context.saveOrRollback(reason: "reorder service") else { return false }
        return true
    }

    /// Deletes one service and its links, then saves.
    /// Runtime and data-store teardown remain with the instance wrapper below
    /// so irreversible work starts only after this method succeeds.
    static func deleteService(
        _ serviceID: UUID,
        in context: ModelContext
    ) throws -> ServiceDeletionOutcome? {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        guard let service = try context.fetch(descriptor).first else { return nil }
        let dataStoreIdentifier = service.dataStoreIdentifier

        // SwiftData owns the cascade from a service to its links. Deleting the
        // links first invalidates objects that the cascade then inspects and
        // produces invalidated-model diagnostics.
        context.delete(service)
        guard context.saveOrRollback(reason: "delete service") else { return nil }
        return ServiceDeletionOutcome(
            serviceID: serviceID,
            dataStoreIdentifier: dataStoreIdentifier
        )
    }

    /// Persists one service's mute setting.
    static func setServiceMuted(
        _ muted: Bool,
        for serviceID: UUID,
        in context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        guard let service = try context.fetch(descriptor).first else { return false }
        service.isMuted = muted
        guard context.saveOrRollback(reason: "toggle service mute") else { return false }
        return true
    }

    /// Persists one space's mute setting and returns the affected services.
    static func setWorkspaceMuted(
        _ muted: Bool,
        for spaceID: UUID,
        in context: ModelContext
    ) throws -> Set<UUID>? {
        var descriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == spaceID }
        )
        descriptor.fetchLimit = 1
        guard let space = try context.fetch(descriptor).first else { return nil }
        let serviceIDs = Set(
            try liveLinks(in: context)
                .filter { $0.space.id == spaceID }
                .map { $0.service.id }
        )
        space.isMuted = muted
        guard context.saveOrRollback(reason: "toggle workspace mute") else { return nil }
        return serviceIDs
    }

    /// Persists normalized custom icon bytes. Nil restores the default source.
    static func setCustomIconData(
        _ data: Data?,
        for serviceID: UUID,
        in context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        guard let service = try context.fetch(descriptor).first else { return false }
        service.customIconData = data
        guard context.saveOrRollback(reason: "set custom icon") else { return false }
        return true
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
        let context = modelContainer.mainContext
        let serviceID: UUID?
        do {
            serviceID = try Self.addService(
                label: label,
                url: url,
                catalogEntryID: catalogEntryID,
                userAgent: userAgent,
                customIconData: customIconData,
                to: spaceID,
                in: context
            )
        } catch {
            context.rollback()
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
        let context = modelContainer.mainContext
        let outcome: ServiceMoveOutcome?
        do {
            outcome = try Self.moveService(
                linkID: linkID,
                to: targetSpaceID,
                in: context
            )
        } catch {
            context.rollback()
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
    func reorderService(
        droppedLinkID: UUID,
        relativeTo targetLinkID: UUID,
        placement: ServiceReorderPlacement
    ) -> Bool {
        let context = modelContainer.mainContext
        do {
            return try Self.reorderService(
                droppedLinkID: droppedLinkID,
                relativeTo: targetLinkID,
                placement: placement,
                in: context
            )
        } catch {
            context.rollback()
            AppLogger.dataStore.error("Failed to reorder services; rolled back: \(error.localizedDescription)")
            return false
        }
    }

    func deleteService(_ serviceID: UUID) {
        let context = modelContainer.mainContext
        let outcome: ServiceDeletionOutcome?
        do {
            outcome = try Self.deleteService(serviceID, in: context)
        } catch {
            context.rollback()
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
        let context = modelContainer.mainContext
        do {
            guard try Self.setServiceMuted(muted, for: serviceID, in: context) else { return }
        } catch {
            context.rollback()
            AppLogger.dataStore.error("Failed to toggle service mute; rolled back: \(error.localizedDescription)")
            return
        }
        refreshBadgeState(for: serviceID)
    }

    func setWorkspaceMuted(_ muted: Bool, for spaceID: UUID) {
        let context = modelContainer.mainContext
        let serviceIDs: Set<UUID>?
        do {
            serviceIDs = try Self.setWorkspaceMuted(muted, for: spaceID, in: context)
        } catch {
            context.rollback()
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
        let context = modelContainer.mainContext
        do {
            guard let data = try ServiceIconFilePicker.pickImageData(
                message: "Choose an icon for \(service.label)"
            ) else { return }
            _ = try Self.setCustomIconData(data, for: serviceID, in: context)
        } catch {
            context.rollback()
            AppLogger.ui.error("Failed to set custom icon: \(error.localizedDescription)")
        }
    }

    func resetIcon(for serviceID: UUID) {
        guard let service = currentServiceInstance(id: serviceID) else { return }
        let shouldFetch = service.fetchedIconData == nil
        let context = modelContainer.mainContext
        do {
            guard try Self.setCustomIconData(nil, for: serviceID, in: context) else { return }
        } catch {
            context.rollback()
            AppLogger.dataStore.error("Failed to reset icon; rolled back: \(error.localizedDescription)")
            return
        }
        guard shouldFetch else { return }

        Task { @MainActor [weak self] in
            await self?.refreshFetchedIcon(for: serviceID)
        }
    }

    /// Records one automatic favicon attempt. A failed refresh keeps an older
    /// icon but still records the attempt time so launch does not retry on every
    /// run.
    static func recordFetchedIconAttempt(
        _ data: Data?,
        at date: Date,
        for serviceID: UUID,
        in context: ModelContext
    ) throws -> Bool {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        guard let service = try context.fetch(descriptor).first,
              service.customIconData == nil
        else { return false }
        if let data {
            service.fetchedIconData = data
        }
        service.faviconFetchedAt = date
        guard context.saveOrRollback(reason: "save fetched favicon") else { return false }
        return true
    }

    /// Refreshes the automatic icon for one saved service. The service is
    /// fetched again after the network wait because it can be deleted or gain a
    /// custom icon while the request is in flight.
    func refreshFetchedIcon(for serviceID: UUID) async {
        guard let service = currentServiceInstance(id: serviceID),
              service.customIconData == nil
        else { return }
        let serviceURL = service.url
        let data = await FaviconFetcher.shared.fetchFavicon(for: serviceURL)
        let context = modelContainer.mainContext
        do {
            _ = try Self.recordFetchedIconAttempt(
                data,
                at: Date(),
                for: serviceID,
                in: context
            )
        } catch {
            context.rollback()
            AppLogger.dataStore.error("Failed to save fetched favicon; rolled back: \(error.localizedDescription)")
        }
    }

    /// Returns every link whose space and service still exist.
    ///
    /// A fetch is the authoritative view of membership. It includes unsaved
    /// inserts and deletes in the context, while the `serviceLinks` and
    /// `spaceLinks` inverse relationships can lag behind them.
    static func liveLinks(in context: ModelContext) throws -> [SpaceServiceLink] {
        try context.fetch(FetchDescriptor<SpaceServiceLink>()).filter {
            $0.modelContext != nil && $0.space.modelContext != nil && $0.service.modelContext != nil
        }
    }

    /// Maps each service ID to the IDs of the spaces that contain it.
    static func memberships(from links: [SpaceServiceLink]) -> [UUID: Set<UUID>] {
        var memberships: [UUID: Set<UUID>] = [:]
        for link in links {
            memberships[link.service.id, default: []].insert(link.space.id)
        }
        return memberships
    }

    /// Counts the services that Atoll deletes together with this space.
    /// The delete confirmation shows this number.
    func orphanedServiceCount(byDeletingSpace spaceID: UUID) -> Int {
        let links = (try? Self.liveLinks(in: modelContainer.mainContext)) ?? []
        return WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: spaceID,
            memberships: Self.memberships(from: links)
        ).count
    }

    /// The result of `removeLink(_:in:)`.
    struct LinkRemovalOutcome: Equatable {
        let serviceID: UUID
        /// The data store to reclaim. Set only when the removed link was the
        /// service's last one and the service is deleted.
        let orphanedDataStoreIdentifier: UUID?

        var deletedService: Bool { orphanedDataStoreIdentifier != nil }
    }

    /// Removes one link and saves. Deletes the service when no other link
    /// remains for it. Membership comes from a fresh fetch, so an unsaved link
    /// in the same context counts.
    ///
    /// Nothing irreversible happens here. The caller tears down the web view
    /// and reclaims the data store after the save succeeds. This method rolls
    /// back a failed save. Returns `nil` when the link does not exist.
    static func removeLink(_ linkID: UUID, in context: ModelContext) throws -> LinkRemovalOutcome? {
        let links = try liveLinks(in: context)
        guard let link = links.first(where: { $0.id == linkID }) else { return nil }
        let service = link.service
        let serviceID = service.id
        // Capture before any delete. Reading a deleted model traps.
        let dataStoreIdentifier = service.dataStoreIdentifier
        let hasOtherLinks = links.contains { $0.id != linkID && $0.service.id == serviceID }

        context.delete(link)
        if !hasOtherLinks {
            context.delete(service)
        }
        guard context.saveOrRollback(reason: "remove service link") else { return nil }
        return LinkRemovalOutcome(
            serviceID: serviceID,
            orphanedDataStoreIdentifier: hasOtherLinks ? nil : dataStoreIdentifier
        )
    }

    /// Removes a service from one space. When the service exists in no other
    /// space, it is deleted and its data store is reclaimed — but only after
    /// the save succeeds. A failed save rolls back and changes nothing.
    func removeLink(_ linkID: UUID) {
        let context = modelContainer.mainContext
        let outcome: LinkRemovalOutcome?
        do {
            outcome = try Self.removeLink(linkID, in: context)
        } catch {
            context.rollback()
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
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == spaceID })
        guard let space = try? context.fetch(descriptor).first else { return }

        // Never delete the last space. With zero spaces the content area is
        // blank and ⌘N would present an Add-Service sheet with no space to add
        // to. The UI hides the delete action when only one space remains; this
        // is the safety net.
        let spaceCount = (try? context.fetchCount(FetchDescriptor<Space>())) ?? 0
        guard spaceCount > 1 else {
            AppLogger.dataStore.warning("Refusing to delete the last remaining space")
            return
        }

        // Read memberships from a fresh link fetch, not from the `serviceLinks`
        // and `spaceLinks` inverse relationships. A fetch includes unsaved
        // inserts and deletes in this context; an inverse can lag behind them.
        guard let liveLinks = try? Self.liveLinks(in: context) else {
            AppLogger.dataStore.error("Failed to fetch links; not deleting space \(spaceID)")
            return
        }
        var linkedServices: [ServiceInstance] = []
        var seenServiceIDs: Set<UUID> = []
        for link in liveLinks where link.space.id == spaceID && seenServiceIDs.insert(link.service.id).inserted {
            linkedServices.append(link.service)
        }
        let memberships = Self.memberships(from: liveLinks)
        let orphanedIDs = WorkspaceDeletionPolicy.servicesOrphaned(
            byDeletingSpace: spaceID,
            memberships: memberships
        )

        // Delete the models and their orphaned services, but hold off on every
        // irreversible side effect (tearing down web views, wiping on-disk data
        // stores) until the save succeeds. Doing them first meant a failed save
        // left the service still in the store yet logged out with its cookies
        // deleted 2s later — data loss the rest of the code is careful to avoid.
        let reclaimed = linkedServices.filter { orphanedIDs.contains($0.id) }
        // Capture the identifiers BEFORE deleting — reading them off the models
        // after they're deleted would fault the freed backing data and trap.
        let reclaimedServiceIDs = reclaimed.map(\.id)
        let orphanedDataStoreIDs = reclaimed.map(\.dataStoreIdentifier)
        for service in reclaimed { context.delete(service) }
        context.delete(space)

        guard context.saveOrRollback(reason: "delete space \(spaceID)") else { return }
        AppLogger.dataStore.info("Deleted space \(spaceID); reclaimed \(reclaimed.count) orphaned service(s)")

        // Save committed — now the destructive cleanup is safe.
        for serviceID in reclaimedServiceIDs { webViewPool.removeWebView(for: serviceID) }
        for dataStoreID in orphanedDataStoreIDs {
            websiteDataReclaimer.markOrphaned(dataStoreID)
        }

        // Fix up selection: clear a selected service that was just reclaimed,
        // and move off the deleted space to the first remaining one.
        if let selected = selectedServiceID, orphanedIDs.contains(selected) {
            selectedServiceID = nil
        }
        if selectedSpaceID == spaceID {
            let remaining = (try? context.fetch(
                FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
            ))?.first
            selectedSpaceID = remaining?.id
            selectedServiceID = nil
        }

        websiteDataReclaimer.cleanUpOrphanedDataStores()
    }

    /// Returns services for a space, safely skipping any links with dangling relationships
    /// (can happen if the previous session crashed mid-delete).
    func servicesForSpace(_ spaceID: UUID) -> [ServiceInstance] {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<SpaceServiceLink>()
        do {
            return try context.fetch(descriptor)
                // Guard both relationships: a link that outlived its deleted
                // service *or* its deleted space (crash mid-delete) would trap
                // when we materialize the non-optional relationship to read its
                // id. Reading `.modelContext` is safe (nil once deleted); read it
                // before `.space.id`.
                .filter {
                    $0.modelContext != nil
                        && $0.service.modelContext != nil
                        && $0.space.modelContext != nil
                        && $0.space.id == spaceID
                }
                .sorted { $0.sortOrder < $1.sortOrder }
                .map(\.service)
        } catch {
            AppLogger.dataStore.error("Failed to fetch links for space \(spaceID): \(error.localizedDescription)")
            return []
        }
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
        // posts notification banners through the `atollNotification` handler on
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

        Task {
            await webViewPool.preloadAll(ordered)
            if let selected {
                webViewPool.unpin(selected)
            }
            if !alsoKeepLive.isEmpty {
                AppLogger.webView.info("Preloading \(alsoKeepLive.count) chat service(s) outside the active space so they can post notifications")
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
        let services = (try? modelContainer.mainContext.fetch(FetchDescriptor<ServiceInstance>())) ?? []
        return Self.criticalServicesToKeepLive(
            among: services,
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
        Task {
            await webViewPool.preloadAll(services)
        }
    }

    private func fetchCatalogIcons(force: Bool = false) {
        let entries = ServiceCatalog.shared.entries
        Task.detached(priority: .utility) {
            await CatalogIconCache.shared.fetchAllIfNeeded(entries: entries, force: force)
        }
    }

    private static let lastRunVersionKey = "atoll.lastRunAppVersion"

    /// Records the current app version and reports whether this launch follows an
    /// update (a different version ran last time). Used to refresh the icon caches
    /// so a release that adds or changes icons shows them at once, instead of
    /// waiting out the weekly staleness timer.
    private static func recordLaunchVersionAndCheckUpdate() -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let previous = UserDefaults.standard.string(forKey: lastRunVersionKey)
        if !current.isEmpty {
            UserDefaults.standard.set(current, forKey: lastRunVersionKey)
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
        _ = preferencesStore.setWindowSelection(
            spaceID: selectedSpaceID,
            serviceID: selectedServiceID
        )
    }

    private func loadAppPreferences() {
        // No AppKit/dockTile/setActivationPolicy access in this scope — it
        // runs inside AppState.init via @State, which fires before the
        // SwiftUI App scene has finished wiring up NSApp. Touching AppKit
        // there can race with NSApplication bootstrap. Defer the
        // AppKit-facing mutations to the next runloop tick.
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

        Task { @MainActor in
            self.setupLockObservers()
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
        let context = modelContainer.mainContext
        do {
            // Apply a saved space only if it still exists. A nil/invalid saved
            // value leaves the seeded selection in place.
            let existingSpaceIDs = Set(try context.fetch(FetchDescriptor<Space>()).map(\.id))
            if let savedSpaceID = preferencesStore.selectedSpaceID,
               existingSpaceIDs.contains(savedSpaceID) {
                selectedSpaceID = savedSpaceID
            }

            // Validate the service selection against the current space. A space
            // or service selected last session may have been deleted (or reaped
            // at launch); ContentView's onChange fix-up doesn't run for the
            // initial value, so a dangling id would strand the app on a blank
            // pane until the user clicked. Fall back to the space's first service.
            guard let spaceID = selectedSpaceID else {
                selectedServiceID = nil
                return
            }
            let servicesInSpace = servicesForSpace(spaceID)
            if let savedServiceID = preferencesStore.selectedServiceID,
               servicesInSpace.contains(where: { $0.id == savedServiceID }) {
                selectedServiceID = savedServiceID
            } else if selectedServiceID == nil
                        || !servicesInSpace.contains(where: { $0.id == selectedServiceID }) {
                selectedServiceID = servicesInSpace.first?.id
            }
        } catch {
            AppLogger.dataStore.error("Failed to restore window state: \(error.localizedDescription)")
        }
    }

    /// Fetches favicons for services that have none cached, and refreshes
    /// stale favicons (older than 7 days). Runs in a background Task to avoid
    /// blocking app launch.
    private func fetchMissingAndStaleFavicons(force: Bool = false) {
        let context = modelContainer.mainContext
        let descriptor = FetchDescriptor<ServiceInstance>()
        let services: [ServiceInstance]
        do {
            services = try context.fetch(descriptor)
        } catch {
            AppLogger.favicon.error("Failed to fetch services for favicon refresh: \(error.localizedDescription)")
            return
        }

        let staleThreshold = Date().addingTimeInterval(-7 * 24 * 60 * 60) // 7 days

        let needsFetch = services.filter { service in
            guard service.customIconData == nil else { return false }
            // After an app update, refresh every service's favicon regardless of
            // age. Otherwise back off on the timestamp for both "never fetched"
            // and "stale": a service whose favicon keeps failing gets stamped on
            // failure (below), so it retries at most weekly instead of every launch.
            if force { return true }
            guard let fetchedAt = service.faviconFetchedAt else { return true }
            return fetchedAt < staleThreshold
        }

        guard !needsFetch.isEmpty else { return }
        AppLogger.favicon.info("Fetching favicons for \(needsFetch.count) service(s)")

        // Capture IDs before the Task. A service can be deleted while a fetch
        // waits on the network.
        let serviceIDs = needsFetch.map(\.id)

        Task { @MainActor [weak self] in
            guard let self else { return }
            for serviceID in serviceIDs {
                await self.refreshFetchedIcon(for: serviceID)
            }
            AppLogger.favicon.info("Favicon refresh complete")
        }
    }

    /// Seeds the default spaces and services on a first launch. Returns `true`
    /// if it seeded (a fresh install), `false` if data already existed or the
    /// fetch failed — the caller uses this to decide whether to backfill the
    /// passkey notice.
    @discardableResult
    private func seedDefaultDataIfNeeded(defaults: UserDefaults = .standard) -> Bool {
        let context = modelContainer.mainContext

        // Sorted so the fallback selection is the top space (sortOrder 0), not a
        // nondeterministic one — matches deleteSpace's remaining-space pick.
        let descriptor = FetchDescriptor<Space>(sortBy: [SortDescriptor(\.sortOrder)])
        let existingSpaces: [Space]
        do {
            existingSpaces = try context.fetch(descriptor)
        } catch {
            AppLogger.dataStore.error("Failed to fetch spaces during seeding: \(error.localizedDescription)")
            return false
        }

        guard existingSpaces.isEmpty else {
            selectedSpaceID = existingSpaces.first?.id
            return false
        }

        // Seed defaults ONLY on a genuine fresh install. An empty store while
        // this install has held data before is data loss, not a first launch —
        // `StoreLoader` already tried to restore it, and writing defaults here
        // would overwrite the very store (or its in-memory stand-in) we want to
        // preserve for recovery. This is the guard that turns the original bug
        // from silent, permanent loss into a recoverable, surfaced condition.
        guard !defaults.bool(forKey: StoreLoader.hasEverHadDataKey) else {
            AppLogger.dataStore.error("Store is empty but this install has had data; skipping seed to avoid overwriting a lost store")
            return false
        }

        let personalSpace = Space(name: DefaultSeed.spaces[0].name, emoji: DefaultSeed.spaces[0].emoji, sortOrder: 0)
        let workSpace = Space(name: DefaultSeed.spaces[1].name, emoji: DefaultSeed.spaces[1].emoji, sortOrder: 1)
        context.insert(personalSpace)
        context.insert(workSpace)

        // Each space gets its own ServiceInstance — even for the same service URL —
        // so cookies, sessions, and login state are fully isolated between spaces.
        for (index, entry) in DefaultSeed.personalServices.enumerated() {
            let service = ServiceInstance(label: entry.label, url: entry.url, catalogEntryID: entry.catalogID)
            context.insert(service)
            context.insert(SpaceServiceLink(sortOrder: index, space: personalSpace, service: service))
        }

        for (index, entry) in DefaultSeed.workServices.enumerated() {
            let service = ServiceInstance(label: entry.label, url: entry.url, catalogEntryID: entry.catalogID)
            context.insert(service)
            context.insert(SpaceServiceLink(sortOrder: index, space: workSpace, service: service))
        }

        guard context.saveOrRollback(reason: "seed default data") else { return false }
        selectedSpaceID = personalSpace.id
        // Record that this install now holds data, so a future empty store is
        // recognized as loss rather than reseeded.
        StoreLoader.recordHasData(defaults)
        AppLogger.dataStore.info("Seeded default spaces: Personal and Work")
        // `fetchMissingAndStaleFavicons` runs next in `init`. It fetches
        // every icon that has no `faviconFetchedAt`, so one pass covers the
        // seeded services. A second task here raced it on the same context.
        return true
    }

    private static let passkeyNoticeBackfilledKey = "passkeyNoticeBackfilled"

    /// Runs once, the first time a build with the passkey notice launches. For a
    /// pre-existing install it marks every current service as having seen the
    /// notice, so the banner only appears for services added afterward rather
    /// than for every service the user already had. On a fresh install
    /// (`freshInstall == true`) it skips the marking, so the notice still shows
    /// the first time each seeded service is opened.
    private func backfillPasskeyNoticeIfNeeded(freshInstall: Bool) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.passkeyNoticeBackfilledKey) else { return }
        // Set the flag first so a failure below doesn't re-run (and re-suppress)
        // the notice on a later launch after the user has added new services.
        defaults.set(true, forKey: Self.passkeyNoticeBackfilledKey)

        guard !freshInstall else { return }

        let context = modelContainer.mainContext
        let services: [ServiceInstance]
        do {
            services = try context.fetch(FetchDescriptor<ServiceInstance>())
        } catch {
            AppLogger.dataStore.error("Failed to fetch services for passkey-notice backfill: \(error.localizedDescription)")
            return
        }

        var changed = false
        for service in services where service.hasSeenPasskeyNotice == nil {
            service.hasSeenPasskeyNotice = true
            changed = true
        }
        guard changed else { return }
        if context.saveOrRollback(reason: "backfill passkey notice") {
            AppLogger.dataStore.info("Backfilled passkey notice for \(services.count) existing service(s)")
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
        let context = modelContainer.mainContext
        var descriptor = FetchDescriptor<ServiceInstance>(predicate: #Predicate { $0.id == serviceID })
        descriptor.fetchLimit = 1
        guard let service = try? context.fetch(descriptor).first, service.needsPasskeyNotice else { return }
        service.hasSeenPasskeyNotice = true
        context.saveOrRollback(reason: "persist passkey notice dismissal")
    }
}
