import AppKit
import Foundation
import SwiftData
import WebKit
import AtollCore

/// Coordinates notification polling, unread badges, DND, and click routing.
@MainActor
@Observable
final class NotificationRuntime {
    let notificationManager: NotificationManager
    let networkMonitor: NetworkMonitor

    private let context: ModelContext
    private let preferencesStore: PreferencesStore
    private let badgeManager: BadgeManager
    private let transientBadgeFetcher: TransientBadgeFetcher
    private let webViewPool: WebViewPool
    private let contentBlocker: ContentBlockerManager
    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private nonisolated let doNotDisturbSnapshot: AtomicBool
    private let minuteOfDay: @MainActor () -> Int
    private let quietHoursInterval: Duration

    private var currentSpaceID: @MainActor () -> UUID? = { nil }
    private var selectService: @MainActor (UUID?, UUID) -> Void = { _, _ in }
    private var quietHoursTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?
    private var systemObserverTokens: [NSObjectProtocol] = []
    private var defaultCenterTokens: [NSObjectProtocol] = []
    private var hasStarted = false
    private var isDNDReady = false
    private var hasShutDown = false

    var doNotDisturb = false {
        didSet { if isDNDReady { refreshEffectiveDoNotDisturb() } }
    }
    private(set) var scheduledDNDEnabled: Bool {
        didSet { if isDNDReady { refreshEffectiveDoNotDisturb() } }
    }
    private(set) var dndStartMinutes: Int {
        didSet { if isDNDReady { refreshEffectiveDoNotDisturb() } }
    }
    private(set) var dndEndMinutes: Int {
        didSet { if isDNDReady { refreshEffectiveDoNotDisturb() } }
    }

    init(
        context: ModelContext,
        preferencesStore: PreferencesStore,
        badgeManager: BadgeManager,
        notificationManager: NotificationManager,
        transientBadgeFetcher: TransientBadgeFetcher,
        webViewPool: WebViewPool,
        networkMonitor: NetworkMonitor,
        contentBlocker: ContentBlockerManager,
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        minuteOfDay: @escaping @MainActor () -> Int = {
            let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
            return (components.hour ?? 0) * 60 + (components.minute ?? 0)
        },
        quietHoursInterval: Duration = .seconds(60)
    ) {
        self.context = context
        self.preferencesStore = preferencesStore
        self.badgeManager = badgeManager
        self.notificationManager = notificationManager
        self.transientBadgeFetcher = transientBadgeFetcher
        self.webViewPool = webViewPool
        self.networkMonitor = networkMonitor
        self.contentBlocker = contentBlocker
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.doNotDisturbSnapshot = badgeManager.doNotDisturbSnapshot
        self.minuteOfDay = minuteOfDay
        self.quietHoursInterval = quietHoursInterval
        self.scheduledDNDEnabled = preferencesStore.scheduledDNDEnabled
        self.dndStartMinutes = preferencesStore.dndStartMinutes
        self.dndEndMinutes = preferencesStore.dndEndMinutes
    }

    /// Installs lifecycle adapters and applies saved notification preferences.
    func start(
        currentSpaceID: @escaping @MainActor () -> UUID?,
        selectService: @escaping @MainActor (UUID?, UUID) -> Void
    ) {
        guard !hasStarted, !hasShutDown else { return }
        hasStarted = true
        self.currentSpaceID = currentSpaceID
        self.selectService = selectService

        setupNotificationNavigation()
        setupMenuBarNavigation()
        setupSystemSleepHandling()
        setupNetworkHandling()
        setupPoolCallbacks()

        let showBadgeCountInDock = preferencesStore.showBadgeCountInDock
        activationTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, !self.hasShutDown else { return }
            self.badgeManager.showBadgeCountInDock = showBadgeCountInDock
            self.isDNDReady = true
            self.refreshEffectiveDoNotDisturb()
            self.startQuietHoursTimer()
        }
    }

    /// Stops all polling, timers, observers, and runtime-owned callbacks.
    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        activationTask?.cancel()
        activationTask = nil
        quietHoursTask?.cancel()
        quietHoursTask = nil

        notificationManager.stopAllPolling()
        notificationManager.onServiceRequested = nil
        transientBadgeFetcher.pause()
        transientBadgeFetcher.targetsProvider = nil
        transientBadgeFetcher.hasLiveWebView = nil
        transientBadgeFetcher.currentBadgeParams = nil
        transientBadgeFetcher.enabledContentRuleLists = nil
        networkMonitor.stop()

        webViewPool.onNavigationFinished = nil
        webViewPool.onServicePreloaded = nil
        webViewPool.onServiceActivated = nil

        for token in systemObserverTokens {
            workspaceNotificationCenter.removeObserver(token)
        }
        systemObserverTokens.removeAll()
        for token in defaultCenterTokens {
            notificationCenter.removeObserver(token)
        }
        defaultCenterTokens.removeAll()
    }

    /// Starts badge fetches for services without a live pooled web view.
    func startTransientBadgeFetcher() {
        guard hasStarted, !hasShutDown else { return }
        transientBadgeFetcher.targetsProvider = { [weak self] in
            guard let self else { return [] }
            let services: [ServiceInstance]
            do {
                services = try self.context.fetch(FetchDescriptor<ServiceInstance>())
            } catch {
                AppLogger.badges.error("Badge sweep fetch failed: \(error.localizedDescription)")
                return []
            }
            return services.compactMap { service in
                guard !self.webViewPool.hasWebView(for: service.id),
                      !service.isEffectivelyMuted,
                      service.showBadge
                else { return nil }
                let badgeJS = service.catalogEntryID
                    .flatMap { ServiceCatalog.shared.entry(for: $0) }?.badgeJS
                return TransientBadgeFetcher.Target(
                    id: service.id,
                    url: service.url,
                    dataStoreIdentifier: service.dataStoreIdentifier,
                    userAgent: service.userAgent,
                    badgeJS: badgeJS
                )
            }
        }
        transientBadgeFetcher.hasLiveWebView = { [weak self] in
            self?.webViewPool.hasWebView(for: $0) ?? false
        }
        transientBadgeFetcher.currentBadgeParams = { [weak self] serviceID in
            guard let self, let service = self.service(serviceID) else { return nil }
            return (service.isEffectivelyMuted, service.showBadge)
        }
        transientBadgeFetcher.enabledContentRuleLists = { [weak self] in
            self?.contentBlocker.enabledLists() ?? []
        }
        transientBadgeFetcher.start()
    }

    var scheduledDNDActive: Bool {
        scheduledDNDEnabled && QuietHoursPolicy.contains(
            nowMinutes: minuteOfDay(),
            start: dndStartMinutes,
            end: dndEndMinutes
        )
    }

    func setScheduledDNDEnabled(_ enabled: Bool) {
        guard preferencesStore.setQuietHours(
            enabled: enabled,
            startMinutes: dndStartMinutes,
            endMinutes: dndEndMinutes
        ) else { return }
        scheduledDNDEnabled = enabled
    }

    func setDNDStartMinutes(_ minutes: Int) {
        let resolved = min((24 * 60) - 1, max(0, minutes))
        guard preferencesStore.setQuietHours(
            enabled: scheduledDNDEnabled,
            startMinutes: resolved,
            endMinutes: dndEndMinutes
        ) else { return }
        dndStartMinutes = resolved
    }

    func setDNDEndMinutes(_ minutes: Int) {
        let resolved = min((24 * 60) - 1, max(0, minutes))
        guard preferencesStore.setQuietHours(
            enabled: scheduledDNDEnabled,
            startMinutes: dndStartMinutes,
            endMinutes: resolved
        ) else { return }
        dndEndMinutes = resolved
    }

    func setShowBadgeCountInDock(_ enabled: Bool) {
        guard preferencesStore.setShowBadgeCountInDock(enabled) else { return }
        badgeManager.showBadgeCountInDock = enabled
    }

    /// Reapplies saved unread state after mute or visibility changes.
    func refreshBadgeState(for serviceID: UUID) {
        guard let service = service(serviceID) else { return }
        badgeManager.updateBadge(
            for: serviceID,
            count: badgeManager.rawCount(for: serviceID),
            isMuted: service.isEffectivelyMuted,
            showBadge: service.showBadge
        )
    }

    /// Stops live polling when the transient badge fetcher takes over.
    func serviceHibernated(_ serviceID: UUID) {
        notificationManager.stopPolling(for: serviceID)
    }

    /// Downgrades a background live web view to its background polling cadence.
    func serviceSoftHibernated(_ serviceID: UUID) {
        guard let webView = webViewPool.liveWebView(for: serviceID) else {
            notificationManager.stopPolling(for: serviceID)
            return
        }
        startPolling(for: serviceID, webView: webView, mode: .background)
    }

    /// Removes all unread and polling state for a deleted service.
    func serviceRemoved(_ serviceID: UUID) {
        notificationManager.stopPolling(for: serviceID)
        badgeManager.removeBadge(for: serviceID)
    }

    nonisolated func isServiceEffectivelyMuted(_ serviceID: UUID) -> Bool {
        MainActor.assumeIsolated { service(serviceID)?.isEffectivelyMuted ?? false }
    }

    nonisolated func isServiceNotifyingOS(_ serviceID: UUID) -> Bool {
        MainActor.assumeIsolated { service(serviceID)?.notifiesOSEffective ?? false }
    }

    nonisolated func isDoNotDisturbActive() -> Bool {
        doNotDisturbSnapshot.value
    }

    /// Lets application tests wait for the deferred AppKit-facing setup.
    func waitForActivation() async {
        await activationTask?.value
    }

    var isQuietHoursScheduled: Bool { quietHoursTask != nil }

    private func refreshEffectiveDoNotDisturb() {
        badgeManager.doNotDisturb = doNotDisturb || scheduledDNDActive
        badgeManager.updateDockBadge()
    }

    private func startQuietHoursTimer() {
        quietHoursTask?.cancel()
        quietHoursTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.quietHoursInterval)
                } catch {
                    return
                }
                self.refreshEffectiveDoNotDisturb()
            }
        }
    }

    private func setupSystemSleepHandling() {
        systemObserverTokens.append(workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.suspendPolling(reason: "system sleep")
            }
        })
        systemObserverTokens.append(workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.resumePolling(reason: "system wake")
            }
        })
    }

    private func setupNetworkHandling() {
        networkMonitor.onChange = { [weak self] online in
            guard let self else { return }
            if online {
                self.resumePolling(reason: "network reachable")
            } else {
                self.suspendPolling(reason: "network unreachable")
            }
        }
    }

    private func suspendPolling(reason: String) {
        notificationManager.stopAllPolling()
        transientBadgeFetcher.pause()
        AppLogger.general.info("Paused polling — \(reason)")
    }

    private func resumePolling(reason: String) {
        guard networkMonitor.isOnline else {
            AppLogger.general.info("Not resuming polling — offline (\(reason))")
            return
        }
        AppLogger.general.info("Resuming polling — \(reason)")
        restartPollingAfterResume()
        transientBadgeFetcher.resume()
    }

    private func restartPollingAfterResume() {
        let activeID = webViewPool.activeServiceID
        for serviceID in webViewPool.liveServiceIDs {
            guard let webView = webViewPool.liveWebView(for: serviceID) else { continue }
            startPolling(
                for: serviceID,
                webView: webView,
                mode: serviceID == activeID ? .active : .background
            )
        }
        AppLogger.general.info(
            "Restarted polling after wake or reconnect for \(self.webViewPool.liveServiceIDs.count) service(s)"
        )
    }

    private func setupPoolCallbacks() {
        webViewPool.onNavigationFinished = { [weak self] serviceID in
            guard let self,
                  let webView = self.webViewPool.liveWebView(for: serviceID) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.notificationManager.pollNow(
                    for: serviceID,
                    webView: webView,
                    isMuted: self.isServiceEffectivelyMuted(serviceID),
                    showBadge: self.isServiceShowingBadge(serviceID),
                    catalogEntry: self.catalogEntry(for: serviceID)
                )
            }
        }
        webViewPool.onServicePreloaded = { [weak self] serviceID, webView in
            self?.startPolling(for: serviceID, webView: webView, mode: .background)
        }
        webViewPool.onServiceActivated = { [weak self] serviceID, webView in
            self?.startPolling(for: serviceID, webView: webView, mode: .active)
        }
    }

    private func startPolling(
        for serviceID: UUID,
        webView: WKWebView,
        mode: NotificationManager.PollMode
    ) {
        notificationManager.startPolling(
            for: serviceID,
            webView: webView,
            isMuted: { [weak self] in self?.isServiceEffectivelyMuted(serviceID) ?? false },
            showBadge: { [weak self] in self?.isServiceShowingBadge(serviceID) ?? true },
            catalogEntry: catalogEntry(for: serviceID),
            mode: mode
        )
    }

    private nonisolated func isServiceShowingBadge(_ serviceID: UUID) -> Bool {
        MainActor.assumeIsolated { service(serviceID)?.showBadge ?? true }
    }

    private nonisolated func catalogEntry(for serviceID: UUID) -> ServiceCatalogEntry? {
        MainActor.assumeIsolated {
            guard let entryID = service(serviceID)?.catalogEntryID else { return nil }
            return ServiceCatalog.shared.entry(for: entryID)
        }
    }

    private func setupMenuBarNavigation() {
        let token = notificationCenter.addObserver(
            forName: .menuBarServiceActivated,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let serviceID = notification.userInfo?["serviceID"] as? UUID,
                  let spaceID = notification.userInfo?["spaceID"] as? UUID
            else { return }
            Task { @MainActor [weak self] in
                self?.selectService(spaceID, serviceID)
            }
        }
        defaultCenterTokens.append(token)
    }

    private func setupNotificationNavigation() {
        notificationManager.onServiceRequested = { [weak self] serviceID in
            self?.navigateToService(serviceID)
        }
        for pending in notificationManager.drainPendingNotifications() {
            navigateToService(pending)
        }
    }

    private func navigateToService(_ serviceID: UUID) {
        guard let service = service(serviceID) else { return }
        let links = service.spaceLinks.filter {
            $0.modelContext != nil && $0.space.modelContext != nil
        }
        let current = currentSpaceID()
        let isInCurrentSpace = links.contains { $0.space.id == current }
        let targetSpaceID = isInCurrentSpace ? nil : links.first?.space.id
        selectService(targetSpaceID, serviceID)
    }

    private func service(_ serviceID: UUID) -> ServiceInstance? {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
