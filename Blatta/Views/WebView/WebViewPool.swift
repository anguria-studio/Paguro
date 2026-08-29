import Foundation
import WebKit
import AppKit
import BlattaCore

@MainActor
@Observable
final class WebViewPool {
    private var webViews: [UUID: WKWebView] = [:]
    private var lastAccessTimes: [UUID: Date] = [:]
    private var coordinators: [UUID: WebViewCoordinator] = [:]
    private var suspendedURLs: [UUID: String] = [:]
    private var snapshots: [UUID: NSImage] = [:]
    private let maxLoaded: Int = 15
    private var hasShutDown = false

    /// Guard set: IDs currently being evaluated for eviction.
    private var evictionInFlight: Set<UUID> = []

    /// Services the user has marked as never-hibernate. Exempt from both
    /// soft hibernation (media pause) and full eviction.
    private var neverHibernateIDs: Set<UUID> = []

    /// Services that must stay live for real-time notifications (the Messaging
    /// catalog category). Exempt from FULL hibernation in both sweeps — the idle
    /// timer and the LRU cap sweep — so a chat app is never torn down and can
    /// keep firing instant alerts. The category lives in the catalog, which the
    /// pool doesn't own, so `HibernationScheduler` classifies through
    /// `isNotificationCritical` and the pool caches the result here at load time.
    private var notificationCriticalIDs: Set<UUID> = []

    /// Services pinned by external callers (e.g. the selected service
    /// during initial preload, before WebContentView attaches and sets
    /// `activeServiceID`). Exempt from eviction.
    private var pinnedIDs: Set<UUID> = []

    private let dataStoreManager: DataStoreManager
    private let userScriptManager: UserScriptManager
    private let contentBlocker: ContentBlockerManager

    /// The effective Blatta window appearance. Automatic services follow it.
    private(set) var effectiveShellAppearanceDark = false

    /// The currently active/displayed service
    private(set) var activeServiceID: UUID?

    /// Set of service IDs currently fully hibernated (web view destroyed)
    private(set) var hibernatedServiceIDs: Set<UUID> = []

    /// Per-service camera/microphone capture state, driven by KVO on each web
    /// view. Populated for background services too (a call on a service you're
    /// not viewing), so the rail can show an in-use dot. Absent ⇒ nothing live.
    struct MediaCaptureState: Equatable {
        var cameraActive = false   // camera live (capturing, not paused); a
                                   // paused (.muted) camera shows no dot, matching
                                   // the mic's distinct muted state below
        var micActive = false      // microphone live
        var micMuted = false       // microphone engaged but muted
        var isCapturing: Bool { cameraActive || micActive || micMuted }
    }
    private(set) var mediaCaptureStates: [UUID: MediaCaptureState] = [:]
    private var mediaObservations: [UUID: [NSKeyValueObservation]] = [:]

    var activeMicrophoneCount: Int {
        mediaCaptureStates.values.count(where: \.micActive)
    }

    /// Per-service page health, so the rail can mark a service that is still
    /// coming up or that failed — including one you are not looking at, which is
    /// the whole point. Absent ⇒ `.live`, so a healthy service costs no entry.
    private(set) var serviceHealth: [UUID: ServiceHealth] = [:]

    func health(for instanceID: UUID) -> ServiceHealth {
        serviceHealth[instanceID] ?? .live
    }

    /// Folds a navigation event into a service's health. Called by each
    /// coordinator; `.live` is stored as an absent entry.
    func applyHealthEvent(_ event: ServiceHealth.Event, to instanceID: UUID) {
        let next = health(for: instanceID).next(event)
        if next == .live {
            serviceHealth.removeValue(forKey: instanceID)
        } else {
            serviceHealth[instanceID] = next
        }
    }

    /// Called when a service is fully hibernated (for badge poller tracking)
    var onServiceHibernated: ((UUID) -> Void)?

    /// Called when a service wakes from full hibernation (for badge poller untracking)
    var onServiceWoke: ((UUID) -> Void)?

    /// Called when a service is soft-hibernated (for pausing notification polling)
    var onServiceSoftHibernated: ((UUID) -> Void)?

    /// Called when a service wakes from soft hibernation
    var onServiceSoftWoke: ((UUID) -> Void)?

    /// Called when a service's web view is permanently removed (deletion, not hibernation)
    var onServiceRemoved: ((UUID) -> Void)?

    /// Classifies whether a service must stay live for real-time notifications
    /// (Messaging category). Set by `HibernationScheduler` and read at load time
    /// to populate `notificationCriticalIDs`. Defaults to "not critical" when
    /// unset, so the pool never over-exempts.
    var isNotificationCritical: ((UUID) -> Bool)?

    /// Called whenever a service's web view is torn down for ANY reason — full
    /// hibernation, rebuild (recreateWebView), LRU eviction, or removal — i.e. the
    /// single `teardownWebView` chokepoint. Distinct from `onServiceRemoved`
    /// (permanent deletion only). `MediaPermissionCoordinator` uses it to deny a
    /// pending request whose web view is going away.
    var onServiceTornDown: ((UUID) -> Void)?

    /// Wired up at AppState init and applied to every coordinator the pool
    /// creates. Routes cross-domain target=_blank links + Cmd-clicks through
    /// service-aware matching before falling back to the system browser. The
    /// second argument is the source service's id, so AppState can honour that
    /// service's "open links in Blatta" choice.
    var externalLinkHandler: ((URL, UUID?) -> Void)?

    /// Set by `MediaPermissionCoordinator` and applied to every web coordinator.
    /// The pool is a pass-through. It owns neither policy nor prompt UI.
    var mediaCapturePolicyProvider: ((UUID, WKMediaCaptureType, WKFrameInfo) async -> WKPermissionDecision)?

    /// The download list that the content header shows. Set by `AppState` and
    /// applied to every coordinator the pool creates. The pool is a
    /// pass-through: it owns neither the transfers nor the indicator rules.
    var downloadTracker: DownloadTracker?

    /// Called after a service has been preloaded (web view created and load
    /// dispatched, but not yet displayed). Allows callers to start background
    /// polling so the service can collect badge counts before the user clicks it.
    var onServicePreloaded: ((UUID, WKWebView) -> Void)?

    /// Called whenever `webView(for:)` makes a service active. The callback
    /// receives the exact live view so lifecycle controllers can attach active
    /// work without making the SwiftUI view own that work.
    var onServiceActivated: ((UUID, WKWebView) -> Void)?

    /// Called when a service's main web view finishes a top-level navigation
    /// (fresh load or login redirect), so callers can fire an immediate badge
    /// poll. Forwarded from each coordinator's `onNavigationFinished`.
    var onNavigationFinished: ((UUID) -> Void)?

    /// Exposes the live `WKWebView` for a service, if one currently exists.
    /// Used by callers that need to attach background polling to a soft-
    /// hibernated or preloaded webview without going through `webView(for:)`,
    /// which has the side-effect of marking the service active.
    func liveWebView(for instanceID: UUID) -> WKWebView? {
        webViews[instanceID]
    }

    /// Snapshot of all service IDs whose WKWebViews are currently alive.
    /// Used after system wake to restart polling for everything that survived
    /// the sleep cycle.
    var liveServiceIDs: [UUID] {
        Array(webViews.keys)
    }

    init(
        dataStoreManager: DataStoreManager,
        userScriptManager: UserScriptManager,
        contentBlocker: ContentBlockerManager
    ) {
        self.dataStoreManager = dataStoreManager
        self.userScriptManager = userScriptManager
        self.contentBlocker = contentBlocker
    }

    func webView(for instance: ServiceInstance) -> WKWebView {
        // Track the never-hibernate preference. Read the effective policy, not the
        // legacy `neverHibernate` flag, so the exemption can't diverge from what
        // the rest of the app treats as `.never`.
        if instance.hibernationPolicyEffective == .never {
            neverHibernateIDs.insert(instance.id)
        } else {
            neverHibernateIDs.remove(instance.id)
        }

        // Cache whether this service is notification-critical (chat), so both
        // hibernation sweeps can exempt it without consulting the catalog.
        if isNotificationCritical?(instance.id) == true {
            notificationCriticalIDs.insert(instance.id)
        } else {
            notificationCriticalIDs.remove(instance.id)
        }

        // Soft-hibernate the previously active service (suspend media, take snapshot)
        if let previousID = activeServiceID, previousID != instance.id {
            softHibernateService(previousID)
        }
        activeServiceID = instance.id

        // Wake from full hibernation if needed
        if hibernatedServiceIDs.contains(instance.id) {
            hibernatedServiceIDs.remove(instance.id)
            onServiceWoke?(instance.id)
        }

        if let existing = webViews[instance.id] {
            lastAccessTimes[instance.id] = Date()
            wakeService(instance.id)
            onServiceActivated?(instance.id, existing)
            return existing
        }

        let config = makeConfiguration(for: instance)
        let webView = WKWebView(frame: .zero, configuration: config)
        applyWebAppearance(to: webView, for: instance)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = instance.userAgent ?? UserAgentProvider.safariDefault

        let coordinator = makeCoordinator(for: instance)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinators[instance.id] = coordinator

        webViews[instance.id] = webView
        lastAccessTimes[instance.id] = Date()
        observeCaptureState(webView, id: instance.id)

        // Restore the last-visited URL when waking from full hibernation
        // so the user lands back where they left off, not at the home URL.
        // Falls back to the service home URL on first creation or when no
        // suspended URL is recorded.
        let resumeURLString = suspendedURLs.removeValue(forKey: instance.id) ?? instance.url
        if let url = URL(string: resumeURLString), !resumeURLString.isEmpty {
            webView.load(URLRequest(url: url))
        } else if let homeURL = URL(string: instance.url) {
            webView.load(URLRequest(url: homeURL))
        }

        // Check eviction asynchronously (needs to query JS for active calls)
        Task {
            await self.evictIfNeeded()
        }

        onServiceActivated?(instance.id, webView)
        return webView
    }

    /// Clears the active service when the content area has no selection. The
    /// outgoing service follows the normal soft-hibernation path, which pauses
    /// media and lets lifecycle controllers downgrade its active work.
    func deactivateCurrentService() {
        guard let activeServiceID else { return }
        softHibernateService(activeServiceID)
        self.activeServiceID = nil
    }

    /// Preloads a web view for a service in the background without making it active.
    /// The web view is created and starts loading, but no soft-hibernation of other
    /// services is triggered. The preload callback lets lifecycle controllers start
    /// background work. This makes the service feel instant when the user selects it.
    /// Skips services that already have a web view or are fully hibernated-by-user.
    func preload(_ instance: ServiceInstance) {
        guard !hasShutDown else { return }
        guard webViews[instance.id] == nil else { return }
        guard instance.modelContext != nil else { return }

        let config = makeConfiguration(for: instance)
        let webView = WKWebView(frame: .zero, configuration: config)
        applyWebAppearance(to: webView, for: instance)
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = instance.userAgent ?? UserAgentProvider.safariDefault

        let coordinator = makeCoordinator(for: instance)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        coordinators[instance.id] = coordinator

        webViews[instance.id] = webView
        lastAccessTimes[instance.id] = Date()
        observeCaptureState(webView, id: instance.id)

        // Register the hibernation-exemption flags now, not just on first
        // activation. A service preloaded but never clicked would otherwise be
        // missing from these sets, so the idle sweep and the LRU cap could
        // hibernate or evict a "Keep Loaded" or chat service the user was
        // promised would stay live. Mirrors the same block in `webView(for:)`.
        if instance.hibernationPolicyEffective == .never {
            neverHibernateIDs.insert(instance.id)
        } else {
            neverHibernateIDs.remove(instance.id)
        }
        if isNotificationCritical?(instance.id) == true {
            notificationCriticalIDs.insert(instance.id)
        } else {
            notificationCriticalIDs.remove(instance.id)
        }

        if let url = URL(string: instance.url) {
            webView.load(URLRequest(url: url))
        }

        AppLogger.webView.debug("Preloaded service \(instance.label)")
        onServicePreloaded?(instance.id, webView)

        Task {
            await evictIfNeeded()
        }
    }

    /// Preloads web views for multiple services with a staggered delay to avoid
    /// overwhelming the network and CPU on startup.
    ///
    /// A service can be deleted during the stagger, and reading a property of
    /// a deleted `@Model` traps. Each iteration checks that the model is still
    /// in a context before it reads anything from it.
    func preloadAll(_ instances: [ServiceInstance], delayBetween: Duration = .milliseconds(500)) async {
        for instance in instances {
            guard !Task.isCancelled, !hasShutDown else { break }
            guard instance.modelContext != nil else { continue }
            guard webViews[instance.id] == nil else { continue }
            preload(instance)
            try? await Task.sleep(for: delayBetween)
        }
    }

    /// Returns a snapshot of the service's last visible state (captured on switch-away)
    func snapshot(for id: UUID) -> NSImage? {
        snapshots[id]
    }

    func removeWebView(for instanceID: UUID) {
        teardownWebView(instanceID)
        suspendedURLs.removeValue(forKey: instanceID)
        hibernatedServiceIDs.remove(instanceID)
        // Permanent removal (deletion, not hibernation): drop every trace of
        // the service so stale IDs can't dangle. The active pointer must be
        // cleared or keyboard shortcuts / eviction would target a ghost; the
        // pin/never-hibernate/in-flight sets and the script message handler
        // would otherwise grow unbounded across create/delete cycles.
        if activeServiceID == instanceID {
            activeServiceID = nil
        }
        pinnedIDs.remove(instanceID)
        neverHibernateIDs.remove(instanceID)
        notificationCriticalIDs.remove(instanceID)
        evictionInFlight.remove(instanceID)
        userScriptManager.removeHandler(for: instanceID)
        onServiceRemoved?(instanceID)
        snapshots.removeValue(forKey: instanceID)
    }

    /// Stops every live page, cancels every download, and releases all WebKit
    /// delegates during process termination. The persistent website data
    /// stores remain on disk.
    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        WebDownloadHandler.cancelAllDownloads()
        let serviceIDs = Array(webViews.keys)
        for serviceID in serviceIDs {
            teardownWebView(serviceID)
            userScriptManager.removeHandler(for: serviceID)
        }
        suspendedURLs.removeAll()
        hibernatedServiceIDs.removeAll()
        pinnedIDs.removeAll()
        neverHibernateIDs.removeAll()
        notificationCriticalIDs.removeAll()
        evictionInFlight.removeAll()
        activeServiceID = nil

        onServiceHibernated = nil
        onServiceWoke = nil
        onServiceSoftHibernated = nil
        onServiceSoftWoke = nil
        onServiceRemoved = nil
        onServiceTornDown = nil
        onServicePreloaded = nil
        onServiceActivated = nil
        onNavigationFinished = nil
        externalLinkHandler = nil
        mediaCapturePolicyProvider = nil
    }

    func hasWebView(for instanceID: UUID) -> Bool {
        webViews[instanceID] != nil
    }

    func isHibernated(_ instanceID: UUID) -> Bool {
        hibernatedServiceIDs.contains(instanceID)
    }

    /// The URL a service resumes at after full hibernation, or `nil` to resume
    /// at its home URL.
    ///
    /// Only a web page is worth resuming. The error and recovery pages load
    /// with `loadHTMLString`, so the web view's URL is `about:blank` while one
    /// is shown; resuming there would show a blank page reported as live.
    nonisolated static func resumeURLString(from url: URL?) -> String? {
        guard let url, let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url.absoluteString
    }

    private func rememberResumeURL(for instanceID: UUID, of webView: WKWebView) {
        if let resumeURL = Self.resumeURLString(from: webView.url) {
            suspendedURLs[instanceID] = resumeURL
        } else {
            suspendedURLs.removeValue(forKey: instanceID)
        }
    }

    /// Manually hibernate a service — fully destroys the web view to reclaim all memory.
    /// The service resumes at its last web page, or at its home URL when it
    /// showed an error page.
    func hibernate(_ instanceID: UUID) {
        guard let webView = webViews[instanceID] else { return }
        rememberResumeURL(for: instanceID, of: webView)
        teardownWebView(instanceID)
        hibernatedServiceIDs.insert(instanceID)
        onServiceHibernated?(instanceID)
        AppLogger.webView.info("Fully hibernated service \(instanceID)")
    }

    /// Check if a service currently has an active WebRTC call.
    func hasActiveCall(for instanceID: UUID) async -> Bool {
        guard webViews[instanceID] != nil else { return false }
        // Bound the JS check. A wedged WebContent process can leave
        // evaluateJavaScript's continuation pending forever; without a real
        // timeout the id would stay in `evictionInFlight` and be excluded from
        // every future eviction pass, so the pool would grow past maxLoaded.
        // Treat "no answer within the window" as "no call" so eviction proceeds
        // (a process that can't answer a one-property read in 2s is wedged and
        // should be reclaimed anyway).
        //
        // A structured `withTaskGroup` can't deliver this: it implicitly awaits
        // every child before returning, and evaluateJavaScript isn't
        // cancellation-aware, so `cancelAll()` wouldn't unstick the wedged probe
        // and the group would hang. So race two unstructured main-actor tasks —
        // the probe and a 2s timer — and resume the continuation with whichever
        // answers first, abandoning (not awaiting) the loser. A leaked wedged
        // probe just lingers until the OS reaps the process.
        return await withCheckedContinuation { continuation in
            let gate = CallProbeGate()
            Task { @MainActor in
                let hasCall = await self.probeCallDetection(instanceID)
                if gate.claim() { continuation.resume(returning: hasCall) }
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if gate.claim() { continuation.resume(returning: false) }
            }
        }
    }

    /// Runs the call-detection JS for a service on the main actor, returning
    /// false if the service has no live web view or the query fails. Re-fetches
    /// the web view by id (rather than capturing it) so `hasActiveCall`'s race
    /// tasks carry only Sendable values.
    private func probeCallDetection(_ instanceID: UUID) async -> Bool {
        guard let webView = webViews[instanceID] else { return false }
        let result = try? await webView.evaluateJavaScript(UserScriptManager.callDetectionQueryJS)
        return (result as? Bool) == true
    }

    /// Memory usage estimate: count of loaded web views
    var loadedCount: Int {
        webViews.count
    }

    /// Mark a service as un-evictable. Used by callers that know a service
    /// will become active soon (e.g. preload of the selected service) but
    /// can't set `activeServiceID` themselves.
    func pin(_ id: UUID) {
        pinnedIDs.insert(id)
    }

    /// Remove the pin set by `pin(_:)`. Safe to call for an unpinned id.
    func unpin(_ id: UUID) {
        pinnedIDs.remove(id)
    }

    /// Sync the never-hibernate flag for a service after the user toggles it
    /// in the editor. The flag is otherwise only read when a web view is
    /// created, so a live service wouldn't pick up the change until next load.
    func setNeverHibernate(_ value: Bool, for id: UUID) {
        if value {
            neverHibernateIDs.insert(id)
        } else {
            neverHibernateIDs.remove(id)
        }
    }

    /// Navigate a service's live web view to a URL. Used when the user edits a
    /// service's URL so the open page follows the change. No-op if the service
    /// has no live web view (it will load the new URL when next opened).
    func navigate(_ id: UUID, to url: URL) {
        webViews[id]?.load(URLRequest(url: url))
    }

    /// Update a live web view's user agent (e.g. the Mobile view toggle) and
    /// reload so the site re-renders for the new agent. No-op without a live
    /// view — the new agent applies when the view is next created.
    func setUserAgent(_ userAgent: String?, for id: UUID) {
        guard let webView = webViews[id] else { return }
        webView.customUserAgent = userAgent ?? UserAgentProvider.safariDefault
        webView.reload()
    }

    /// Rebuilds a service's web view so configuration-time settings — the
    /// injected user scripts, including custom CSS — pick up an edit. The view
    /// is torn down here and recreated on next access; the active pointer and
    /// never-hibernate state are left intact (this is a refresh, not a removal).
    /// With `preserveURL` false the open URL is dropped so the rebuild loads the
    /// service's (possibly just-edited) home URL instead.
    func recreateWebView(for instanceID: UUID, preserveURL: Bool = true) {
        guard let webView = webViews[instanceID] else { return }
        if preserveURL {
            rememberResumeURL(for: instanceID, of: webView)
        } else {
            suspendedURLs.removeValue(forKey: instanceID)
        }
        teardownWebView(instanceID)
    }

    // MARK: - Soft Hibernate (resource offloading without destroying the web view)

    /// Suspends media playback and captures a snapshot.
    /// The WKWebView stays alive so JS continues running (notifications, WebRTC, etc.)
    /// but WebKit releases GPU textures and compositor resources when the view has no superview.
    private func softHibernateService(_ id: UUID) {
        guard let webView = webViews[id] else { return }
        guard !neverHibernateIDs.contains(id) else { return }
        webView.setAllMediaPlaybackSuspended(true)
        webView.takeSnapshot(with: nil) { [weak self] image, _ in
            guard let image else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                // The snapshot completes asynchronously; if the service was
                // removed (deleted) meanwhile, don't re-insert a snapshot for a
                // dead id — that would be a small permanent leak.
                guard self.webViews[id] != nil else { return }
                self.snapshots[id] = image
            }
        }
        AppLogger.webView.debug("Soft-hibernated service \(id)")
        onServiceSoftHibernated?(id)
    }

    /// Resumes media playback when a service becomes active again.
    private func wakeService(_ id: UUID) {
        guard let webView = webViews[id] else { return }
        webView.setAllMediaPlaybackSuspended(false)
        AppLogger.webView.debug("Woke service \(id)")
        onServiceSoftWoke?(id)
    }

    // MARK: - Private

    /// Observes a web view's camera/mic capture state so the rail shows an in-use
    /// dot even for a background service. Mirrors WebViewState's KVO discipline:
    /// the callback captures only Sendable values (the id + an object-identity
    /// token), hops to main, and re-fetches the live view — re-checking identity
    /// so a torn-down view's late callback can't light a dot for a recycled id.
    private func observeCaptureState(_ webView: WKWebView, id: UUID) {
        let token = ObjectIdentifier(webView)
        // Inlined (not a shared local) so each closure literal is inferred
        // @Sendable — a stored non-Sendable function value trips Swift 6's
        // data-race check when handed to `observe`'s @Sendable changeHandler.
        mediaObservations[id] = [
            webView.observe(\.cameraCaptureState, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, let live = self.webViews[id],
                          ObjectIdentifier(live) == token else { return }
                    self.refreshMediaCaptureState(id: id, webView: live)
                }
            },
            webView.observe(\.microphoneCaptureState, options: [.new]) { [weak self] _, _ in
                DispatchQueue.main.async {
                    guard let self, let live = self.webViews[id],
                          ObjectIdentifier(live) == token else { return }
                    self.refreshMediaCaptureState(id: id, webView: live)
                }
            },
            // Only the rising edge is reported. A load ending is left to the
            // coordinator's didFinish/didFail, which are the two callbacks that
            // know whether it ended well — `isLoading` going false says only
            // that it stopped, and treating that as success would clear a
            // failure the instant it happened.
            webView.observe(\.isLoading, options: [.new]) { [weak self] _, change in
                guard change.newValue == true else { return }
                DispatchQueue.main.async {
                    guard let self, let live = self.webViews[id],
                          ObjectIdentifier(live) == token else { return }
                    self.applyHealthEvent(.startedLoading, to: id)
                }
            },
        ]
    }

    /// Recomputes and stores a service's capture state from its live web view,
    /// dropping the entry entirely when nothing is live.
    private func refreshMediaCaptureState(id: UUID, webView: WKWebView) {
        var state = MediaCaptureState()
        // Only .active counts as "live" — a .muted (paused) camera shouldn't show
        // a green in-use dot. Mic tracks active vs. muted separately so the glyph
        // can distinguish "live" from "muted".
        state.cameraActive = (webView.cameraCaptureState == .active)
        state.micActive = (webView.microphoneCaptureState == .active)
        state.micMuted = (webView.microphoneCaptureState == .muted)
        if state.isCapturing {
            mediaCaptureStates[id] = state
        } else {
            mediaCaptureStates.removeValue(forKey: id)
        }
    }

    /// Mutes or unmutes a service's live microphone (host-side, so the far end
    /// sees it). No-op without a live capturing web view.
    func setMicrophoneMuted(_ muted: Bool, for id: UUID) {
        guard let webView = webViews[id],
              webView.microphoneCaptureState != WKMediaCaptureState.none else { return }
        webView.setMicrophoneCaptureState(muted ? .muted : .active, completionHandler: nil)
        recordRequestedMicrophoneState(muted: muted, id: id, webView: webView)
    }

    /// Mutes every service whose microphone is currently live. Returns how many
    /// were muted, so a caller can tell when nothing was live.
    @discardableResult
    func muteActiveMicrophones() -> Int {
        let activeIDs = webViews.compactMap { id, webView in
            webView.microphoneCaptureState == .active ? id : nil
        }
        for id in activeIDs {
            setMicrophoneMuted(true, for: id)
        }
        return activeIDs.count
    }

    /// Shows the requested state immediately. WebKit KVO reconciles this value
    /// with the capture device after it applies the host-side change.
    private func recordRequestedMicrophoneState(
        muted: Bool,
        id: UUID,
        webView: WKWebView
    ) {
        var state = mediaCaptureStates[id] ?? MediaCaptureState()
        state.cameraActive = webView.cameraCaptureState == .active
        state.micActive = !muted
        state.micMuted = muted
        mediaCaptureStates[id] = state
    }

    private func teardownWebView(_ instanceID: UUID) {
        if let webView = webViews[instanceID] {
            webView.configuration.userContentController.removeAllScriptMessageHandlers()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
        mediaObservations[instanceID]?.forEach { $0.invalidate() }
        mediaObservations.removeValue(forKey: instanceID)
        mediaCaptureStates.removeValue(forKey: instanceID)
        // A hibernated service has no page, so it has no health to report; the
        // rail draws the moon for it instead. Leaving a stale failed dot on a
        // service that was torn down would outlive the failure.
        serviceHealth.removeValue(forKey: instanceID)
        webViews.removeValue(forKey: instanceID)
        lastAccessTimes.removeValue(forKey: instanceID)
        coordinators.removeValue(forKey: instanceID)
        snapshots.removeValue(forKey: instanceID)
        onServiceTornDown?(instanceID)
    }

    /// Builds a navigation/UI coordinator wired to this service. Shared by
    /// `webView(for:)` and `preload(_:)` so the instance id, fallback URL,
    /// external-link routing, and navigation-finished callback stay in sync.
    private func makeCoordinator(for instance: ServiceInstance) -> WebViewCoordinator {
        let coordinator = WebViewCoordinator()
        coordinator.instanceID = instance.id
        coordinator.downloadTracker = downloadTracker
        coordinator.fallbackURL = URL(string: instance.url)
        coordinator.externalLinkHandler = externalLinkHandler
        coordinator.mediaCapturePolicyProvider = mediaCapturePolicyProvider
        coordinator.onNavigationFinished = { [weak self] id in
            self?.onNavigationFinished?(id)
        }
        coordinator.onHealthEvent = { [weak self] id, event in
            self?.applyHealthEvent(event, to: id)
        }
        return coordinator
    }

    private func makeConfiguration(for instance: ServiceInstance) -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = dataStoreManager.dataStore(for: instance)
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        // Enable back-forward cache so swiping back loads instantly from cache
        config.preferences.isElementFullscreenEnabled = true

        // NOTE: no picture-in-picture config flag here. That flag
        // (allowsPictureInPictureMediaPlayback) is iOS-only; on macOS WebKit
        // exposes video PiP through the native media controls automatically.

        let controller = WKUserContentController()
        userScriptManager.configureScripts(
            for: instance,
            customCSS: effectiveCSS(for: instance),
            stayActiveInBackground: instance.staysActiveInBackgroundEffective,
            on: controller
        )
        // Attach the compiled content-blocking rule lists (ad/tracker domains)
        // when blocking is enabled. Returns empty — a no-op — until the lists
        // finish compiling at launch; those web views pick the lists up via
        // reattachContentBlocker().
        for ruleList in contentBlocker.enabledLists() {
            controller.add(ruleList)
        }

        config.userContentController = controller

        return config
    }

    /// Updates the content-blocking rule lists on every live web view *in place*
    /// — no teardown — so it takes effect without reloading the page, dropping
    /// background badge polls, or discarding preloaded views. Called when the
    /// blocklist finishes compiling after launch and when the global toggle
    /// flips; views built afterward already carry the right lists via
    /// `makeConfiguration`.
    func reattachContentBlocker() {
        let lists = contentBlocker.enabledLists()
        for webView in webViews.values {
            let controller = webView.configuration.userContentController
            controller.removeAllContentRuleLists()
            for ruleList in lists {
                controller.add(ruleList)
            }
        }
    }

    /// The effective per-service CSS (service defaults + any custom CSS), or nil
    /// when there is none.
    private func effectiveCSS(for instance: ServiceInstance) -> String? {
        let css = ServiceCSSDefaults.effectiveCSS(
            instanceCSS: instance.customCSS,
            catalogID: instance.catalogEntryID
        )
        guard let css, !css.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return css
    }

    /// Applies a Blatta appearance change to every live service. Automatic
    /// services follow it. Explicit service overrides keep their value.
    func applyShellAppearance(isDark: Bool, services: [ServiceInstance]) {
        effectiveShellAppearanceDark = isDark
        let byID = Dictionary(
            services.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (id, webView) in webViews {
            guard let service = byID[id] else { continue }
            applyWebAppearance(to: webView, for: service)
        }
    }

    /// Applies one service override without rebuilding or reloading its web view.
    func refreshWebAppearance(for instance: ServiceInstance) {
        guard let webView = webViews[instance.id] else { return }
        applyWebAppearance(to: webView, for: instance)
    }

    /// Returns the AppKit appearance name that drives CSS
    /// `prefers-color-scheme` in the web view.
    nonisolated static func webAppearanceName(
        mode: ServiceAppearanceMode,
        shellIsDark: Bool
    ) -> NSAppearance.Name {
        mode.usesDarkAppearance(shellIsDark: shellIsDark) ? .darkAqua : .aqua
    }

    private func applyWebAppearance(to webView: WKWebView, for instance: ServiceInstance) {
        let name = Self.webAppearanceName(
            mode: instance.webAppearance,
            shellIsDark: effectiveShellAppearanceDark
        )
        webView.appearance = NSAppearance(named: name)
    }

    /// Live services eligible for auto-hibernation, each paired with how long it
    /// has been idle: not the active service, not "Keep Loaded", not chat, not
    /// pinned, and actually loaded. The caller resolves each service's own idle
    /// threshold (its per-service policy, or the global one) and the active-call
    /// exemption — this only does the flag-and-liveness selection the pool can
    /// answer on its own.
    func idleCandidates(now: Date) -> [(id: UUID, idle: TimeInterval)] {
        lastAccessTimes.compactMap { id, accessed in
            guard id != activeServiceID,
                  !neverHibernateIDs.contains(id),
                  !notificationCriticalIDs.contains(id),
                  !pinnedIDs.contains(id),
                  webViews[id] != nil
            else { return nil }
            return (id, now.timeIntervalSince(accessed))
        }
    }

    /// Fully hibernates `id` iff it is still eligible after the async call check.
    ///
    /// `hasActiveCall` is a suspension point (up to its own 2s timeout), and the
    /// user can switch to this service — or pin it, mark it never-hibernate, or
    /// close it — while it's suspended. So the guards are re-checked AFTER the
    /// await, with no further suspension before `hibernate`, so a service the
    /// user is now viewing is never torn down under them. `evictionInFlight`
    /// keeps two passes (the cap sweep and the idle sweep) from racing the same
    /// id. Shared by both callers so the re-validation lives in one place.
    /// Returns true iff it hibernated.
    @discardableResult
    func hibernateIfStillIdle(_ id: UUID) async -> Bool {
        guard webViews[id] != nil,
              id != activeServiceID,
              !pinnedIDs.contains(id),
              !neverHibernateIDs.contains(id),
              !notificationCriticalIDs.contains(id),
              !evictionInFlight.contains(id)
        else { return false }

        evictionInFlight.insert(id)
        let hasCall = await hasActiveCall(for: id)
        evictionInFlight.remove(id)

        // Re-validate every guard across the suspension.
        guard webViews[id] != nil,
              id != activeServiceID,
              !pinnedIDs.contains(id),
              !neverHibernateIDs.contains(id),
              !notificationCriticalIDs.contains(id)
        else { return false }

        if hasCall {
            AppLogger.webView.info("Skipping hibernation of \(id) — active call detected")
            return false
        }
        // The JS probe sees only WebRTC calls. A live camera or microphone
        // outside a call (a voice memo, a video preview) must keep the page too.
        if let capture = mediaCaptureStates[id], capture.isCapturing {
            AppLogger.webView.info("Skipping hibernation of \(id) — camera or microphone in use")
            return false
        }

        hibernate(id)
        return true
    }

    /// When exceeding maxLoaded web views, fully hibernate the least recently used ones.
    /// Skips services that have an active WebRTC call, via `hibernateIfStillIdle`.
    private func evictIfNeeded() async {
        guard webViews.count > maxLoaded else { return }

        let sorted = lastAccessTimes
            .filter { $0.key != activeServiceID
                   && !evictionInFlight.contains($0.key)
                   && !neverHibernateIDs.contains($0.key)
                   && !notificationCriticalIDs.contains($0.key)
                   && !pinnedIDs.contains($0.key) }
            .sorted { $0.value < $1.value }

        for (id, _) in sorted {
            // Re-check the live count each pass, not a count captured up front:
            // a concurrent pass (they interleave at the await inside
            // hibernateIfStillIdle) may have already hibernated views, and a
            // stale target would evict past the cap, dropping below maxLoaded.
            guard webViews.count > maxLoaded else { break }
            await hibernateIfStillIdle(id)
        }
    }
}

/// One-shot guard that lets exactly one of `hasActiveCall`'s two racing tasks
/// resume the continuation. Both racers are `@MainActor`, so the plain flag is
/// only ever touched on the main actor and needs no lock.
@MainActor
private final class CallProbeGate {
    private var used = false
    func claim() -> Bool {
        if used { return false }
        used = true
        return true
    }
}
