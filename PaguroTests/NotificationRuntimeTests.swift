import AppKit
import PaguroCore
import SwiftData
import UserNotifications
import WebKit
import XCTest
@testable import Paguro

final class NotificationRuntimeTests: XCTestCase {
    @MainActor
    func testDockMuteIndicatorTracksServicesGlobalMuteAndShutdown() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        var written: [Bool] = []
        fixture.runtime.writeDockMuteIndicator = { written.append($0) }
        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()
        XCTAssertEqual(written.last, false)

        let context = fixture.container.mainContext
        let space = Space(name: "Muted", emoji: "", isMuted: true)
        let service = ServiceInstance(label: "Chat", url: "https://chat.example")
        context.insert(space)
        context.insert(service)
        context.insert(SpaceServiceLink(space: space, service: service))
        try context.save()
        fixture.runtime.refreshDockMuteState()
        XCTAssertEqual(written.last, true)

        let unmuted = ServiceInstance(label: "Mail", url: "https://mail.example")
        context.insert(unmuted)
        try context.save()
        fixture.runtime.refreshDockMuteState()
        XCTAssertEqual(written.last, false)

        fixture.badgeManager.updateBadge(for: unmuted.id, count: 3, isMuted: false)
        fixture.runtime.doNotDisturb = true
        XCTAssertEqual(written.last, true)
        XCTAssertNil(fixture.badgeManager.dockBadgeLabel)
        XCTAssertEqual(fixture.badgeManager.rawCount(for: unmuted.id), 3)
        fixture.runtime.doNotDisturb = false
        XCTAssertEqual(written.last, false)
        fixture.runtime.shutdown()
        XCTAssertEqual(written.last, false)
    }

    @MainActor
    func testQuietHoursAndManualDNDStayInSyncAndPersist() async throws {
        let fixture = try makeFixture(
            preferences: AppPreferences(
                showBadgeCountInDock: false,
                scheduledDNDEnabled: true,
                dndStartMinutes: 22 * 60,
                dndEndMinutes: 7 * 60
            ),
            minuteOfDay: { 23 * 60 }
        )
        defer { fixture.shutdown() }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()

        XCTAssertTrue(fixture.runtime.scheduledDNDActive)
        XCTAssertTrue(fixture.badgeManager.doNotDisturb)
        XCTAssertTrue(fixture.runtime.isDoNotDisturbActive())
        XCTAssertFalse(fixture.badgeManager.showBadgeCountInDock)
        XCTAssertTrue(fixture.runtime.isQuietHoursScheduled)

        fixture.runtime.setScheduledDNDEnabled(false)
        XCTAssertFalse(fixture.badgeManager.doNotDisturb)
        XCTAssertFalse(fixture.preferencesStore.scheduledDNDEnabled)

        fixture.runtime.doNotDisturb = true
        XCTAssertTrue(fixture.badgeManager.doNotDisturb)

        fixture.runtime.setDNDStartMinutes(-30)
        fixture.runtime.setDNDEndMinutes(2_000)
        fixture.runtime.setShowBadgeCountInDock(true)
        XCTAssertEqual(fixture.runtime.dndStartMinutes, 0)
        XCTAssertEqual(fixture.runtime.dndEndMinutes, (24 * 60) - 1)
        XCTAssertEqual(fixture.preferencesStore.dndStartMinutes, 0)
        XCTAssertEqual(fixture.preferencesStore.dndEndMinutes, (24 * 60) - 1)
        XCTAssertTrue(fixture.preferencesStore.showBadgeCountInDock)
        XCTAssertTrue(fixture.badgeManager.showBadgeCountInDock)
    }

    /// Covers the whole Dock-badge chain: the stored preference, the runtime
    /// start, a poll result, and the label that reaches the Dock tile.
    @MainActor
    func testStoredPreferenceReachesTheDockBadge() async throws {
        let fixture = try makeFixture(
            preferences: AppPreferences(showBadgeCountInDock: false)
        )
        defer { fixture.shutdown() }
        var written: [String?] = []
        fixture.badgeManager.writeDockBadge = { written.append($0) }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()

        // The stored preference is off, so a poll result makes no badge.
        fixture.badgeManager.updateBadge(
            for: UUID(),
            count: 4,
            isMuted: false,
            showBadge: true
        )
        XCTAssertNil(written.last ?? nil)

        // The Settings toggle persists the preference and shows the badge at
        // once, from the count that the manager already holds.
        fixture.runtime.setShowBadgeCountInDock(true)
        XCTAssertTrue(fixture.preferencesStore.showBadgeCountInDock)
        XCTAssertEqual(written.last ?? nil, "4")

        // The mute indicator replaces the Dock badge without clearing unread state.
        fixture.runtime.doNotDisturb = true
        XCTAssertNil(written.last ?? nil)
        fixture.runtime.doNotDisturb = false
        XCTAssertEqual(written.last ?? nil, "4")
    }

    @MainActor
    func testBadgeRefreshReadsCurrentServicePolicyWithoutLosingRawCount() throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        let context = fixture.container.mainContext
        let space = Space(name: "Muted", emoji: "M")
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        context.insert(space)
        context.insert(service)
        context.insert(SpaceServiceLink(space: space, service: service))
        try context.save()

        fixture.badgeManager.updateBadge(
            for: service.id,
            count: 7,
            isMuted: false,
            showBadge: true
        )
        space.isMuted = true
        try context.save()
        fixture.runtime.refreshBadgeState(for: service.id)

        XCTAssertTrue(fixture.runtime.isServiceEffectivelyMuted(service.id))
        XCTAssertTrue(fixture.runtime.isServiceNotifyingOS(service.id))
        XCTAssertEqual(fixture.badgeManager.rawCount(for: service.id), 7)
        XCTAssertEqual(fixture.badgeManager.badgeCount(for: service.id), 0)

        space.isMuted = false
        service.showBadge = false
        try context.save()
        fixture.runtime.refreshBadgeState(for: service.id)
        XCTAssertEqual(fixture.badgeManager.rawCount(for: service.id), 7)
        XCTAssertEqual(fixture.badgeManager.badgeCount(for: service.id), 0)

        service.showBadge = true
        try context.save()
        fixture.runtime.refreshBadgeState(for: service.id)
        XCTAssertEqual(fixture.badgeManager.badgeCount(for: service.id), 7)
    }

    @MainActor
    func testBufferedNotificationAndMenuSelectionUseRuntimeRouting() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        let context = fixture.container.mainContext
        let currentSpace = Space(name: "Current", emoji: "C")
        let targetSpace = Space(name: "Target", emoji: "T")
        let service = ServiceInstance(label: "Chat", url: "https://chat.example")
        context.insert(currentSpace)
        context.insert(targetSpace)
        context.insert(service)
        context.insert(SpaceServiceLink(space: targetSpace, service: service))
        try context.save()

        fixture.notificationManager.routeServiceRequest(service.id)
        var selectedSpaceID: UUID? = currentSpace.id
        var selections: [(UUID?, UUID)] = []
        fixture.runtime.start(
            currentSpaceID: { selectedSpaceID },
            selectService: { spaceID, serviceID in
                selections.append((spaceID, serviceID))
                if let spaceID { selectedSpaceID = spaceID }
            }
        )

        XCTAssertEqual(selections.count, 1)
        XCTAssertEqual(selections[0].0, targetSpace.id)
        XCTAssertEqual(selections[0].1, service.id)

        fixture.notificationCenter.post(
            name: .menuBarServiceActivated,
            object: nil,
            userInfo: ["spaceID": currentSpace.id, "serviceID": service.id]
        )
        await Task.yield()

        XCTAssertEqual(selections.count, 2)
        XCTAssertEqual(selections[1].0, currentSpace.id)
        XCTAssertEqual(selections[1].1, service.id)
    }

    /// A banner click must select the service account and then show the main
    /// window. Without the second step the selection changes behind a closed
    /// window, and the click has no visible result.
    @MainActor
    func testNotificationRoutingSelectsTheServiceAndThenShowsTheWindow() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        let context = fixture.container.mainContext
        let space = Space(name: "Target", emoji: "T")
        let service = ServiceInstance(label: "Chat", url: "https://chat.example")
        context.insert(space)
        context.insert(service)
        context.insert(SpaceServiceLink(space: space, service: service))
        try context.save()

        enum Step: Equatable {
            case select(UUID)
            case showWindow
        }
        var steps: [Step] = []
        fixture.runtime.start(
            currentSpaceID: { nil },
            selectService: { _, serviceID in steps.append(.select(serviceID)) },
            bringWindowForward: { steps.append(.showWindow) }
        )

        fixture.notificationManager.routeServiceRequest(service.id)
        await Task.yield()

        XCTAssertEqual(steps, [.select(service.id), .showWindow])
    }

    /// A deleted service account has nowhere to go, so the click must show no
    /// window either.
    @MainActor
    func testRoutingAnUnknownServiceShowsNoWindow() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }

        var selections: [UUID] = []
        var windowRequests = 0
        fixture.runtime.start(
            currentSpaceID: { nil },
            selectService: { _, serviceID in selections.append(serviceID) },
            bringWindowForward: { windowRequests += 1 }
        )

        fixture.notificationManager.routeServiceRequest(UUID())
        await Task.yield()

        XCTAssertTrue(selections.isEmpty)
        XCTAssertEqual(windowRequests, 0)
    }

    /// A click that launches Paguro waits in the buffer until the runtime
    /// starts. Each drained click must show the window as a live click does.
    @MainActor
    func testEachDrainedLaunchClickShowsTheWindow() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        let context = fixture.container.mainContext
        let space = Space(name: "Target", emoji: "T")
        let service = ServiceInstance(label: "Chat", url: "https://chat.example")
        context.insert(space)
        context.insert(service)
        context.insert(SpaceServiceLink(space: space, service: service))
        try context.save()

        fixture.notificationManager.routeServiceRequest(service.id)
        var selections: [UUID] = []
        var windowRequests = 0
        fixture.runtime.start(
            currentSpaceID: { nil },
            selectService: { _, serviceID in selections.append(serviceID) },
            bringWindowForward: { windowRequests += 1 }
        )

        XCTAssertEqual(selections, [service.id])
        XCTAssertEqual(windowRequests, 1)
    }

    /// Opening a service must correct its badge at once. Waiting for the first
    /// poll tick left a count the user had already read on the screen for
    /// seconds, which is the moment the user is most sure the badge is wrong.
    @MainActor
    func testActivatingAServiceClearsAStaleBadgeAtOnce() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }
        let context = fixture.container.mainContext
        let service = ServiceInstance(label: "Mail", url: "https://mail.example")
        context.insert(service)
        try context.save()

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        fixture.badgeManager.updateBadge(for: service.id, count: 4, isMuted: false)

        let webView = WKWebView(frame: .zero)
        webView.loadHTMLString(
            "<html><head><title>Inbox</title></head><body>read</body></html>",
            baseURL: URL(string: "https://mail.example")
        )
        for _ in 0..<100 {
            let title = try? await webView.evaluateJavaScript("document.title") as? String
            if title == "Inbox" { break }
            try await Task.sleep(for: .milliseconds(50))
        }

        fixture.pool.onServiceActivated?(service.id, webView)
        // Stop the recurring loop that activation also starts. It clears the
        // same badge about 5 seconds later, so leaving it running would let the
        // test pass without the immediate poll. Cancelling it leaves only the
        // immediate poll, which the callback already started in its own task.
        fixture.notificationManager.stopPolling(for: service.id)

        for _ in 0..<100 where fixture.badgeManager.rawCount(for: service.id) != 0 {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(fixture.badgeManager.rawCount(for: service.id), 0)
    }

    @MainActor
    func testShutdownRemovesEveryOwnedCallbackAndObserver() async throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        var selections: [UUID] = []
        fixture.runtime.start(
            currentSpaceID: { nil },
            selectService: { _, serviceID in selections.append(serviceID) }
        )
        fixture.runtime.startTransientBadgeFetcher()
        await fixture.runtime.waitForActivation()

        XCTAssertNotNil(fixture.notificationManager.onServiceRequested)
        XCTAssertNotNil(fixture.networkMonitor.onChange)
        XCTAssertNotNil(fixture.pool.onNavigationFinished)
        XCTAssertNotNil(fixture.pool.onServicePreloaded)
        XCTAssertNotNil(fixture.pool.onServiceActivated)
        XCTAssertNotNil(fixture.transientBadgeFetcher.targetsProvider)
        XCTAssertTrue(fixture.runtime.isQuietHoursScheduled)

        fixture.runtime.shutdown()

        XCTAssertNil(fixture.notificationManager.onServiceRequested)
        XCTAssertNil(fixture.networkMonitor.onChange)
        XCTAssertNil(fixture.pool.onNavigationFinished)
        XCTAssertNil(fixture.pool.onServicePreloaded)
        XCTAssertNil(fixture.pool.onServiceActivated)
        XCTAssertNil(fixture.transientBadgeFetcher.targetsProvider)
        XCTAssertNil(fixture.transientBadgeFetcher.hasLiveWebView)
        XCTAssertNil(fixture.transientBadgeFetcher.currentBadgeParams)
        XCTAssertNil(fixture.transientBadgeFetcher.enabledContentRuleLists)
        XCTAssertFalse(fixture.runtime.isQuietHoursScheduled)

        fixture.notificationCenter.post(
            name: .menuBarServiceActivated,
            object: nil,
            userInfo: ["spaceID": UUID(), "serviceID": UUID()]
        )
        await Task.yield()
        XCTAssertTrue(selections.isEmpty)
    }

    /// The notification delegate must arrive with the launch, not with
    /// `NotificationManager.init`. `init` runs inside `App.init`, before AppKit
    /// finishes launching, and a notification-center touch there can leave the
    /// app unregistered for the rest of the run.
    @MainActor
    func testStartInstallsTheNotificationDelegateAfterLaunch() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()

        XCTAssertNotNil(UNUserNotificationCenter.current().delegate)
    }

    /// The user grants the permission in System Settings, outside Paguro.
    /// Coming back to Paguro must read the permission again.
    @MainActor
    func testActivationRefreshesTheAuthorizationState() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }

        var reported = UNAuthorizationStatus.denied
        fixture.notificationManager.readAuthorizationStatus = { reported }
        fixture.notificationManager.performAuthorizationRequest = { false }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()
        await drain(fixture.notificationManager, until: .denied)

        XCTAssertEqual(fixture.notificationManager.authorizationState, .denied)

        reported = .authorized
        fixture.notificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        await drain(fixture.notificationManager, until: .authorized)

        XCTAssertEqual(fixture.notificationManager.authorizationState, .authorized)
    }

    /// The permission request used to live in the root view's `.task`. A
    /// login-item launch closes the main window and "Menu bar only" never
    /// builds it, so the request could be missed entirely. The runtime owns it
    /// now, and the runtime starts for every launch.
    @MainActor
    func testStartRequestsThePermissionWithoutAWindow() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }

        var requestCount = 0
        fixture.notificationManager.readAuthorizationStatus = { .notDetermined }
        fixture.notificationManager.performAuthorizationRequest = {
            requestCount += 1
            return true
        }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()
        await drain(fixture.notificationManager, until: .authorized)

        XCTAssertEqual(requestCount, 1)
    }

    /// A refused request must not be recorded as a refusal by the user, and an
    /// activation must not overwrite it with the `denied` that macOS reports.
    @MainActor
    func testAFailedRequestSurvivesAnActivationRefresh() async throws {
        let fixture = try makeFixture()
        defer { fixture.shutdown() }

        fixture.notificationManager.readAuthorizationStatus = { .denied }
        fixture.notificationManager.performAuthorizationRequest = {
            throw NSError(domain: UNErrorDomain, code: 1)
        }

        fixture.runtime.start(currentSpaceID: { nil }, selectService: { _, _ in })
        await fixture.runtime.waitForActivation()
        await drain(fixture.notificationManager, until: .unavailable)

        fixture.notificationCenter.post(
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
        for _ in 0..<30 { await Task.yield() }

        XCTAssertEqual(fixture.notificationManager.authorizationState, .unavailable)
    }

    /// The permission read is asynchronous. Give it the turns that it needs.
    @MainActor
    private func drain(
        _ manager: NotificationManager,
        until state: NotificationAuthorizationState
    ) async {
        for _ in 0..<200 where manager.authorizationState != state {
            await Task.yield()
        }
    }

    @MainActor
    private func makeFixture(
        preferences: AppPreferences = AppPreferences(),
        minuteOfDay: @escaping @MainActor () -> Int = { 12 * 60 }
    ) throws -> Fixture {
        let container = try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(preferences)
        try context.save()

        let preferencesStore = PreferencesStore(context: context)
        let badgeManager = BadgeManager()
        let notificationManager = NotificationManager(badgeManager: badgeManager)
        let dataStoreManager = DataStoreManager()
        let transientBadgeFetcher = TransientBadgeFetcher(
            badgeManager: badgeManager,
            dataStoreManager: dataStoreManager
        )
        let contentBlocker = ContentBlockerManager()
        let pool = WebViewPool(
            dataStoreManager: dataStoreManager,
            userScriptManager: UserScriptManager(),
            contentBlocker: contentBlocker
        )
        let networkMonitor = NetworkMonitor()
        let notificationCenter = NotificationCenter()
        let runtime = NotificationRuntime(
            context: context,
            preferencesStore: preferencesStore,
            badgeManager: badgeManager,
            notificationManager: notificationManager,
            transientBadgeFetcher: transientBadgeFetcher,
            webViewPool: pool,
            networkMonitor: networkMonitor,
            contentBlocker: contentBlocker,
            notificationCenter: notificationCenter,
            workspaceNotificationCenter: NotificationCenter(),
            minuteOfDay: minuteOfDay,
            quietHoursInterval: .seconds(60)
        )
        runtime.writeDockMuteIndicator = { _ in }
        return Fixture(
            container: container,
            preferencesStore: preferencesStore,
            badgeManager: badgeManager,
            notificationManager: notificationManager,
            transientBadgeFetcher: transientBadgeFetcher,
            pool: pool,
            networkMonitor: networkMonitor,
            notificationCenter: notificationCenter,
            runtime: runtime
        )
    }
}

@MainActor
private struct Fixture {
    let container: ModelContainer
    let preferencesStore: PreferencesStore
    let badgeManager: BadgeManager
    let notificationManager: NotificationManager
    let transientBadgeFetcher: TransientBadgeFetcher
    let pool: WebViewPool
    let networkMonitor: NetworkMonitor
    let notificationCenter: NotificationCenter
    let runtime: NotificationRuntime

    func shutdown() {
        runtime.shutdown()
        pool.shutdown()
    }
}
