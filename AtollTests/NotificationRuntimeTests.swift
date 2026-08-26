import SwiftData
import XCTest
@testable import Atoll

final class NotificationRuntimeTests: XCTestCase {
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
