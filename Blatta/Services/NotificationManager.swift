import Foundation
import WebKit
import UserNotifications
import os
import BlattaCore

@MainActor
@Observable
final class NotificationManager {
    private var pollTasks: [UUID: Task<Void, Never>] = [:]
    private let badgeManager: BadgeManager
    /// Notification taps that arrived before `onServiceRequested` was wired
    /// (a tap can launch the app). Buffered in order and drained once the
    /// handler is set, so a burst of cold-launch taps isn't reduced to just the
    /// last one.
    private var pendingServiceIDs: [UUID] = []

    var onServiceRequested: (@MainActor (UUID) -> Void)?

    /// The macOS notification permission, as Settings reads it.
    ///
    /// A denied permission makes macOS drop every banner while
    /// `UNUserNotificationCenter` still accepts each request, so this value is
    /// the only signal the user can act on.
    private(set) var authorizationState: NotificationAuthorizationState = .unknown

    /// Blatta asks macOS for the permission once for each launch.
    ///
    /// A failed request stays a retry, not a refusal, but the retry belongs to
    /// the next launch. Asking again inside one run would repeat a request
    /// that already failed for a reason no activation changes.
    @ObservationIgnored private var hasRequestedAuthorization = false

    /// The last poll line that each service account wrote to the log, so a
    /// 5 second poll reports a repeated value one time only.
    @ObservationIgnored private var lastLoggedPoll: [UUID: String] = [:]

    /// The page-title observation of each active poll. Held here, next to
    /// `pollTasks`, because both end at the same moment.
    @ObservationIgnored private var titleObservations: [UUID: NSKeyValueObservation] = [:]

    /// Service accounts whose page title changed since the last poll tick. The
    /// active poll loop reads and clears this set on each tick.
    @ObservationIgnored private var pendingPollKicks: Set<UUID> = []

    /// The generation of the poll that runs for each service account, and the
    /// counter that produces it. A generation is never reused, so a title
    /// callback that arrives after its poll stopped or restarted can be told
    /// apart from a live one and dropped.
    @ObservationIgnored private var pollGenerations: [UUID: Int] = [:]
    @ObservationIgnored private var nextPollGeneration = 0

    init(badgeManager: BadgeManager) {
        self.badgeManager = badgeManager
    }

    /// Polling cadence for a service.
    /// - `active`: adaptive 5s→15s polling, plus a page-title kick, for the
    ///   service currently displayed to the user.
    /// - `background`: flat 30s polling for preloaded or soft-hibernated
    ///   services. No title kick, because a hidden view changes its title while
    ///   it preloads or rehydrates.
    enum PollMode {
        case active
        case background
    }

    /// Starts the poll loop of one service account.
    ///
    /// The active loop ticks every second and reads the count at an adaptive
    /// interval. The interval starts at 5s and steps up by 5s, capped at 15s,
    /// after each run of 120 unchanged polls, so a quiet service slows down
    /// while a user who is reading still sees a badge follow the page.
    ///
    /// A change of the page title kicks the loop: the next tick polls at once
    /// and the interval returns to 5s. A title change means the page state
    /// moved, so the back-off restarts whether or not the count itself changed.
    /// The 1 second tick is the debounce, so a burst of title changes costs one
    /// poll.
    ///
    /// Each poll reads the authoritative source: the DOM `badgeJS` selector
    /// when the catalog defines one, else the page title.
    ///
    /// `isMuted` and `showBadge` are passed as closures so live toggles take
    /// effect on the next tick instead of waiting for a restart of the task.
    func startPolling(
        for instanceID: UUID,
        webView: WKWebView,
        isMuted: @escaping @MainActor () -> Bool,
        showBadge: @escaping @MainActor () -> Bool,
        catalogEntry: ServiceCatalogEntry?,
        mode: PollMode = .active
    ) {
        stopPolling(for: instanceID)

        let task = Task { @MainActor [weak self, weak webView] in
            switch mode {
            case .active:
                await Self.runActivePoll(
                    instanceID: instanceID,
                    weakSelf: { [weak self] in self },
                    weakWebView: { [weak webView] in webView },
                    isMuted: isMuted,
                    showBadge: showBadge,
                    catalogEntry: catalogEntry
                )
            case .background:
                await Self.runBackgroundPoll(
                    instanceID: instanceID,
                    weakSelf: { [weak self] in self },
                    weakWebView: { [weak webView] in webView },
                    isMuted: isMuted,
                    showBadge: showBadge,
                    catalogEntry: catalogEntry
                )
            }
        }
        pollTasks[instanceID] = task

        if mode == .active {
            observeTitleChanges(for: instanceID, webView: webView)
        }
    }

    /// Watches the page title of an active service account, so the loop can
    /// poll the moment the page reports a different unread count.
    ///
    /// The title is the one push signal that every page gives for free: a mail
    /// service rewrites "(3) Inbox" as soon as the user reads a message, while
    /// a poll alone can wait a full interval for the same fact.
    private func observeTitleChanges(for instanceID: UUID, webView: WKWebView) {
        nextPollGeneration &+= 1
        let generation = nextPollGeneration
        pollGenerations[instanceID] = generation

        // WKWebView fires KVO on the main thread in practice, but this is not
        // contractually guaranteed. Use DispatchQueue.main.async for safety —
        // it's a no-op if already on main, and handles the off-main edge case
        // without the crash risk of MainActor.assumeIsolated. The generation
        // guard then drops a callback that arrives after this poll stopped or
        // restarted, so a stopped service cannot kick a live one.
        titleObservations[instanceID] = webView.observe(\.title, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                guard let self, self.pollGenerations[instanceID] == generation else { return }
                self.kickPoll(for: instanceID)
            }
        }
    }

    /// Marks a service account for an immediate poll on the next loop tick.
    ///
    /// The title observation calls this. It is also the entry point that a test
    /// drives, because a test cannot make WebKit deliver a title change at a
    /// known moment.
    func kickPoll(for instanceID: UUID) {
        pendingPollKicks.insert(instanceID)
    }

    /// Reads and clears the kick of one service account.
    func consumePollKick(for instanceID: UUID) -> Bool {
        pendingPollKicks.remove(instanceID) != nil
    }

    private static func runActivePoll(
        instanceID: UUID,
        weakSelf: @MainActor () -> NotificationManager?,
        weakWebView: @MainActor () -> WKWebView?,
        isMuted: @MainActor () -> Bool,
        showBadge: @MainActor () -> Bool,
        catalogEntry: ServiceCatalogEntry?
    ) async {
        var schedule = ActivePollSchedule()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(1))
            guard let manager = weakSelf(), let webView = weakWebView(), !Task.isCancelled else { break }

            // The kick is read on every tick, so one title change costs one
            // poll however many times the page rewrote its title in that second.
            let kicked = manager.consumePollKick(for: instanceID)
            guard schedule.advance(kicked: kicked) else { continue }

            let previousCount = manager.badgeManager.rawCount(for: instanceID)
            // Authoritative source (DOM selector if defined, else title).
            // resetToZero: true — the user is looking, so an empty inbox
            // clearing to 0 is correct.
            await manager.pollPrimaryCount(webView: webView, instanceID: instanceID, isMuted: isMuted(), showBadge: showBadge(), catalogEntry: catalogEntry, resetToZero: true)
            let newCount = manager.badgeManager.rawCount(for: instanceID)

            schedule.recordResult(countChanged: newCount != previousCount)
        }
    }

    private static func runBackgroundPoll(
        instanceID: UUID,
        weakSelf: @MainActor () -> NotificationManager?,
        weakWebView: @MainActor () -> WKWebView?,
        isMuted: @MainActor () -> Bool,
        showBadge: @MainActor () -> Bool,
        catalogEntry: ServiceCatalogEntry?
    ) async {
        // A DOM selector, when defined, is authoritative — but a hidden view's
        // selector may not have hydrated, so a background read of 0 stays
        // raise-only (won't clear). A title-based service reads its (reliable)
        // title with the normal clearing behavior.
        let hasSelector = catalogEntry?.badgeJS != nil
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            guard let manager = weakSelf(), let webView = weakWebView(), !Task.isCancelled else { break }
            await manager.pollPrimaryCount(webView: webView, instanceID: instanceID, isMuted: isMuted(), showBadge: showBadge(), catalogEntry: catalogEntry, resetToZero: !hasSelector)
        }
    }

    func stopPolling(for instanceID: UUID) {
        pollTasks[instanceID]?.cancel()
        pollTasks.removeValue(forKey: instanceID)
        lastLoggedPoll.removeValue(forKey: instanceID)
        // The observation ends with the task it feeds. Dropping the generation
        // makes a callback that is already in flight a no-op.
        titleObservations.removeValue(forKey: instanceID)?.invalidate()
        pollGenerations.removeValue(forKey: instanceID)
        pendingPollKicks.remove(instanceID)
    }

    func stopAllPolling() {
        for task in pollTasks.values {
            task.cancel()
        }
        pollTasks.removeAll()
        lastLoggedPoll.removeAll()
        for observation in titleObservations.values {
            observation.invalidate()
        }
        titleObservations.removeAll()
        pollGenerations.removeAll()
        pendingPollKicks.removeAll()
    }

    /// Fires a single immediate poll for a service without starting or
    /// disturbing its recurring poll task. Used to fill a badge the moment a
    /// page finishes loading, and to correct one the moment the user opens the
    /// service, instead of waiting for the next poll tick.
    ///
    /// The caller decides how much the poll may do:
    ///
    /// - `resetToZero: false`, the default, only ever *raises* a badge. A poll
    ///   that fires on a login interstitial or an in-app error page then cannot
    ///   wipe a correct count. Load-time polls use this.
    /// - `resetToZero: true` also clears. Activation uses it, because the user
    ///   is looking at a settled page, and a stale count is the visible fault
    ///   there.
    func pollNow(
        for instanceID: UUID,
        webView: WKWebView,
        isMuted: Bool,
        showBadge: Bool,
        catalogEntry: ServiceCatalogEntry?,
        resetToZero: Bool = false
    ) async {
        await pollPrimaryCount(webView: webView, instanceID: instanceID, isMuted: isMuted, showBadge: showBadge, catalogEntry: catalogEntry, resetToZero: resetToZero)
    }

    /// Reads the badge from the service's authoritative source: its DOM `badgeJS`
    /// selector when defined (Gmail Inbox, LinkedIn messaging), otherwise the page
    /// title. A service WITH a selector never falls back to the title — so a title
    /// count for a different view (another Gmail label, or LinkedIn's global
    /// notification count) can't override the intended number.
    private func pollPrimaryCount(webView: WKWebView, instanceID: UUID, isMuted: Bool, showBadge: Bool, catalogEntry: ServiceCatalogEntry?, resetToZero: Bool) async {
        if let entry = catalogEntry, entry.badgeJS != nil {
            await pollBadge(webView: webView, instanceID: instanceID, isMuted: isMuted, showBadge: showBadge, catalogEntry: entry, resetToZero: resetToZero)
        } else {
            await pollTitle(webView: webView, instanceID: instanceID, isMuted: isMuted, showBadge: showBadge, catalogEntry: catalogEntry, resetToZero: resetToZero)
        }
    }

    // MARK: - Poll logging

    /// The name that a poll line uses for a service account.
    ///
    /// A custom service has no catalog entry, so the line falls back to the
    /// first part of the identifier. The identifier is safe for a log.
    private static func pollName(for instanceID: UUID, catalogEntry: ServiceCatalogEntry?) -> String {
        catalogEntry?.name ?? String(instanceID.uuidString.prefix(8))
    }

    /// Records one poll result for a service account.
    ///
    /// A poll runs every 5 seconds, so the line repeats until the result
    /// changes. This method keeps the last line for each service account and
    /// writes a new line only for a change. `raw` is the redacted text from
    /// `BadgeCountExtractor`, which holds digits and a shape only, so no
    /// message subject reaches the log.
    private func recordPoll(
        for instanceID: UUID,
        name: String,
        source: String,
        raw: String,
        count: Int?,
        applied: Bool
    ) {
        let described = count.map(String.init) ?? "none"
        let line = "service=\(name) source=\(source) raw=\(raw) "
            + "count=\(described) applied=\(applied)"
        guard lastLoggedPoll[instanceID] != line else { return }
        lastLoggedPoll[instanceID] = line
        AppLogger.badges.info("Badge poll changed: \(line, privacy: .public)")
    }

    /// Records a poll that WebKit refused. The page may still be loading, so
    /// this is a normal state, but a run of failures explains a missing badge.
    private func recordPollFailure(
        for instanceID: UUID,
        name: String,
        source: String,
        error: any Error
    ) {
        let nsError = error as NSError
        recordPoll(
            for: instanceID,
            name: name,
            source: source,
            raw: "error(\(nsError.domain)/\(nsError.code))",
            count: nil,
            applied: false
        )
    }

    /// Routes a notification tap to the navigation handler, or buffers it if
    /// the handler isn't wired yet (a notification can launch the app before
    /// NotificationRuntime finishes setting `onServiceRequested`). Drained by
    /// the runtime when click routing starts.
    func routeServiceRequest(_ serviceID: UUID) {
        if let handler = onServiceRequested {
            handler(serviceID)
        } else {
            pendingServiceIDs.append(serviceID)
        }
    }

    /// Returns and clears every buffered cold-launch tap, in arrival order.
    func drainPendingNotifications() -> [UUID] {
        let ids = pendingServiceIDs
        pendingServiceIDs = []
        return ids
    }

    // MARK: - Polling

    /// `resetToZero: false` makes a count of 0 a no-op instead of clearing the
    /// badge. The eager post-load poll (`pollNow`) uses this so a login/redirect
    /// interstitial or in-app error page — none of which carry an "(N)" in the
    /// title — can't wipe a correct unread badge. The recurring live poll keeps
    /// the default (true): reading your inbox empty authoritatively clears it.
    private func pollTitle(webView: WKWebView, instanceID: UUID, isMuted: Bool, showBadge: Bool, catalogEntry: ServiceCatalogEntry? = nil, resetToZero: Bool = true) async {
        let name = Self.pollName(for: instanceID, catalogEntry: catalogEntry)
        do {
            let result = try await webView.evaluateJavaScript("document.title")
            // The JS await is a suspension point: the poll task may have been
            // cancelled (service switched away / hibernated) while it ran. Drop
            // the result so a stale tick can't write a badge after cancellation.
            guard !Task.isCancelled else { return }
            guard let title = result as? String else {
                recordPoll(
                    for: instanceID,
                    name: name,
                    source: "title",
                    raw: BadgeCountExtractor.readJSResult(result).raw,
                    count: nil,
                    applied: false
                )
                return
            }
            let reading = BadgeCountExtractor.readTitle(title)
            let count = reading.count ?? 0
            let applied = count > 0 || resetToZero
            recordPoll(
                for: instanceID,
                name: name,
                source: "title",
                raw: reading.raw,
                count: count,
                applied: applied
            )
            guard applied else { return }
            #if DEBUG
            let previousCount = badgeManager.rawCount(for: instanceID)
            if CompatibilityFixture.isEnabled(), count != previousCount {
                AppLogger.badges.info(
                    "Fixture title badge changed previous=\(previousCount, privacy: .public) next=\(count, privacy: .public) resetAllowed=\(resetToZero, privacy: .public)"
                )
            }
            #endif
            badgeManager.updateBadge(for: instanceID, count: count, isMuted: isMuted, showBadge: showBadge)
        } catch {
            guard !Task.isCancelled else { return }
            recordPollFailure(for: instanceID, name: name, source: "title", error: error)
        }
    }

    private func pollBadge(webView: WKWebView, instanceID: UUID, isMuted: Bool, showBadge: Bool, catalogEntry: ServiceCatalogEntry, resetToZero: Bool = true) async {
        guard let badgeJS = catalogEntry.badgeJS else { return }
        let name = Self.pollName(for: instanceID, catalogEntry: catalogEntry)
        do {
            let result = try await webView.evaluateJavaScript(badgeJS)
            // Drop the result if the poll task was cancelled during the JS await,
            // so a stale tick can't write a badge after cancellation.
            guard !Task.isCancelled else { return }
            // `readJSResult` supplies both the count and the log text. WebKit
            // bridges every JavaScript number to an NSNumber built from a
            // double, so `result as? Int` dropped a non-integral value, and a
            // plain `Int(String)` dropped element text such as "9+" or
            // "1,234". The Core rule reads all of them.
            let reading = BadgeCountExtractor.readJSResult(result)
            let raw = reading.raw
            let count = reading.count
            let applied = count.map { $0 > 0 || resetToZero } ?? false
            recordPoll(
                for: instanceID,
                name: name,
                source: "dom",
                raw: raw,
                count: count,
                applied: applied
            )
            guard applied, let count else { return }
            badgeManager.updateBadge(for: instanceID, count: count, isMuted: isMuted, showBadge: showBadge)
        } catch {
            guard !Task.isCancelled else { return }
            recordPollFailure(for: instanceID, name: name, source: "dom", error: error)
        }
    }

    // MARK: - Notifications

    /// Reads the permission that macOS currently reports.
    ///
    /// Tests replace this closure, so the launch and activation paths stay
    /// verifiable without the notification permission of the machine that runs
    /// them.
    @ObservationIgnored
    var readAuthorizationStatus: @MainActor () async -> UNAuthorizationStatus = {
        await UNUserNotificationCenter.current()
            .notificationSettings()
            .authorizationStatus
    }

    /// Asks macOS for the permission. Throws when macOS refuses to ask.
    ///
    /// Tests replace this closure to produce each request outcome without a
    /// system prompt.
    @ObservationIgnored
    var performAuthorizationRequest: @MainActor () async throws -> Bool = {
        try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Reads the permission and asks macOS for it when the state machine says
    /// to. Runs once for each launch.
    ///
    /// A fresh install reaches this with `notDetermined`, so macOS shows its
    /// prompt. An install that macOS never registered reaches it with a
    /// reported `denied` that hides a failed registration, so Blatta asks
    /// again and reads the outcome rather than the reported permission.
    func startAuthorization() {
        guard !hasRequestedAuthorization else { return }
        hasRequestedAuthorization = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            let initialState = Self.state(for: await self.readAuthorizationStatus())
            self.setAuthorizationState(initialState)
            AppLogger.notifications.info(
                "Notification authorization read at launch: state=\(initialState.rawValue, privacy: .public)"
            )
            guard NotificationAuthorizationPolicy.shouldRequest(for: initialState) else {
                return
            }
            await self.requestAuthorization()
        }
    }

    /// Asks macOS for the permission once and classifies what came back.
    ///
    /// macOS returns — with `granted` true or false — whenever it could run
    /// the request. It throws only when it could not run the request at all,
    /// which means it never asked the user. That difference, not the reported
    /// permission, separates a refusal from an unregistered app: both report
    /// `denied` afterwards.
    func requestAuthorization() async {
        do {
            let granted = try await performAuthorizationRequest()
            let reported = Self.state(for: await readAuthorizationStatus())
            AppLogger.notifications.info(
                "Notification authorization completed: granted=\(granted, privacy: .public) state=\(reported.rawValue, privacy: .public)"
            )
            setAuthorizationState(
                NotificationAuthorizationPolicy.state(
                    after: .completed,
                    reportedState: reported
                )
            )
        } catch {
            let nsError = error as NSError
            let reported = Self.state(for: await readAuthorizationStatus())
            AppLogger.notifications.error(
                "Notification authorization request refused by macOS: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) reported=\(reported.rawValue, privacy: .public) description=\(nsError.localizedDescription, privacy: .public)"
            )
            setAuthorizationState(
                NotificationAuthorizationPolicy.state(
                    after: .failed,
                    reportedState: reported
                )
            )
        }
    }

    /// Reads the current permission from macOS and publishes it.
    ///
    /// The user can change the permission in System Settings while Blatta runs,
    /// so the app reads it again on each activation. The merge rule keeps a
    /// failed registration visible: macOS keeps reporting `denied` for it, and
    /// a plain overwrite would show the user a refusal they never made.
    func refreshAuthorizationState() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let reported = Self.state(for: await self.readAuthorizationStatus())
            self.setAuthorizationState(
                NotificationAuthorizationPolicy.merge(
                    current: self.authorizationState,
                    reported: reported
                )
            )
        }
    }

    func setAuthorizationState(_ state: NotificationAuthorizationState) {
        guard state != authorizationState else { return }
        authorizationState = state
        AppLogger.notifications.info(
            "Notification authorization state changed: \(state.rawValue, privacy: .public)"
        )
    }

    /// Maps the platform status into the Core enum at the boundary, so no
    /// `UserNotifications` type reaches `BlattaCore`.
    static func state(
        for status: UNAuthorizationStatus
    ) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .authorized:
            return .authorized
        case .provisional:
            return .provisional
        @unknown default:
            // A future status that permits nothing known stays a warning
            // rather than a silent claim that banners work.
            return .denied
        }
    }

    /// Installs the notification delegate.
    ///
    /// Called from `applicationDidFinishLaunching`, not from `init`. The
    /// first touch of `UNUserNotificationCenter.current()` binds this process
    /// to the notification service; a touch during `App.init` happens before
    /// AppKit finishes the launch, and macOS can then refuse to register the
    /// app for notifications for the rest of the run.
    func configureNotificationDelegate() {
        // Read DND from the thread-safe snapshot, not MainActor.assumeIsolated:
        // willPresent/didReceive aren't contractually delivered on the main
        // thread, and an off-main assumeIsolated would hard-crash.
        let dndSnapshot = badgeManager.doNotDisturbSnapshot
        let delegate = NotificationCenterDelegate(
            onServiceRequested: { [weak self] serviceID in
                Task { @MainActor in
                    self?.routeServiceRequest(serviceID)
                }
            },
            isDoNotDisturb: {
                dndSnapshot.value
            }
        )
        UNUserNotificationCenter.current().delegate = delegate
        NotificationCenterDelegate.retained = delegate
    }
}

// MARK: - Active poll cadence

/// The cadence of one active poll loop.
///
/// The loop ticks every second and asks this value when to read the count. The
/// rule lives apart from the loop so each cadence decision can be tested
/// without a running timer. It stays in the app target because it exists only
/// to serve the WebKit poll loop.
struct ActivePollSchedule {
    /// The fastest cadence, and the cadence after any page change.
    static let minimumInterval = 5
    /// The slowest cadence. A user who reads a message in the window must not
    /// wait longer than this for the badge to follow.
    static let maximumInterval = 15
    /// Unchanged polls needed before the cadence steps down one level. At one
    /// poll every 5 seconds this is 10 minutes of silence for each step.
    static let cyclesPerStep = 120

    private(set) var interval = ActivePollSchedule.minimumInterval
    private(set) var unchangedCycles = 0
    private var tick = 0

    /// Advances the loop by one second. Returns `true` when this tick polls.
    ///
    /// A kick is a page-title change. The page state moved, so the poll happens
    /// on this tick and the back-off starts again at the fastest cadence.
    mutating func advance(kicked: Bool) -> Bool {
        guard !kicked else {
            interval = Self.minimumInterval
            unchangedCycles = 0
            tick = 0
            return true
        }
        tick += 1
        return tick % interval == 0
    }

    /// Records what a poll found. An unchanged count moves the loop towards the
    /// slowest cadence. A changed count returns it to the fastest one.
    mutating func recordResult(countChanged: Bool) {
        guard !countChanged else {
            interval = Self.minimumInterval
            unchangedCycles = 0
            return
        }
        unchangedCycles += 1
        if unchangedCycles >= Self.cyclesPerStep {
            interval = min(interval + Self.minimumInterval, Self.maximumInterval)
            unchangedCycles = 0
        }
    }
}

// MARK: - Notification Center Delegate

private final class NotificationCenterDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    let onServiceRequested: @Sendable (UUID) -> Void
    let isDoNotDisturb: @Sendable () -> Bool
    // Keeps the delegate alive (UNUserNotificationCenter holds it weakly).
    // Written once from the main-actor `configureNotificationDelegate()`, so
    // it's main-actor state rather than free-floating mutable global state.
    @MainActor static var retained: NotificationCenterDelegate?

    init(
        onServiceRequested: @escaping @Sendable (UUID) -> Void,
        isDoNotDisturb: @escaping @Sendable () -> Bool
    ) {
        self.onServiceRequested = onServiceRequested
        self.isDoNotDisturb = isDoNotDisturb
        super.init()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let serviceIDString = response.notification.request.content.userInfo["serviceID"] as? String,
           let serviceID = UUID(uuidString: serviceIDString) {
            onServiceRequested(serviceID)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let traceID = String(notification.request.identifier.prefix(8)).lowercased()
        // Suppress all banners and sounds while Do Not Disturb is active.
        if isDoNotDisturb() {
            AppLogger.notifications.info(
                "Notification trace \(traceID, privacy: .public): foreground presentation suppressed by DND"
            )
            completionHandler([])
        } else {
            AppLogger.notifications.info(
                "Notification trace \(traceID, privacy: .public): foreground presentation requested banner+sound"
            )
            completionHandler([.banner, .sound])
        }
    }
}
