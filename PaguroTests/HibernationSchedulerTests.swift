import SwiftData
import XCTest
import PaguroCore
@testable import Paguro

final class HibernationSchedulerTests: XCTestCase {
    @MainActor
    func testIdleSweepAppliesPolicyAndStopsWhileLocked() async throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let context = fixture.container.mainContext
        let ready = service(label: "Ready", policy: .after, afterMinutes: 1)
        let tooRecent = service(label: "Recent", policy: .after, afterMinutes: 1)
        let followsDisabledGlobal = service(label: "Global", policy: .followGlobal)
        let critical = service(
            label: "Chat",
            policy: .after,
            afterMinutes: 1,
            catalogEntryID: "slack"
        )
        for item in [ready, tooRecent, followsDisabledGlobal, critical] {
            context.insert(item)
        }
        try context.save()

        let isLocked = AtomicBool(false)
        var hibernated: [UUID] = []
        let scheduler = HibernationScheduler(
            context: context,
            webViewPool: fixture.pool,
            idleCandidates: { _ in
                [
                    (ready.id, 61),
                    (tooRecent.id, 59),
                    (followsDisabledGlobal.id, 3_600),
                    (critical.id, 3_600),
                ]
            },
            hibernate: {
                hibernated.append($0)
                return true
            }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { isLocked.value }
        )

        await scheduler.runIdleSweep()
        XCTAssertEqual(hibernated, [ready.id])

        isLocked.value = true
        hibernated.removeAll()
        await scheduler.runIdleSweep()
        XCTAssertTrue(hibernated.isEmpty)
    }

    @MainActor
    func testImmediatePolicyHibernatesAndForwardsLifecycleEvents() async throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let service = service(label: "Immediate", policy: .immediate)
        fixture.container.mainContext.insert(service)
        try fixture.container.mainContext.save()

        var hibernated: [UUID] = []
        var softEvents: [UUID] = []
        var fullEvents: [UUID] = []
        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            immediateDelay: .zero,
            idleCandidates: { _ in [] },
            hibernate: {
                hibernated.append($0)
                return true
            }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false },
            onServiceHibernated: { fullEvents.append($0) },
            onServiceSoftHibernated: { softEvents.append($0) }
        )

        fixture.pool.onServiceSoftHibernated?(service.id)
        await scheduler.waitForImmediateHibernation(service.id)
        fixture.pool.onServiceHibernated?(service.id)

        XCTAssertEqual(softEvents, [service.id])
        XCTAssertEqual(hibernated, [service.id])
        XCTAssertEqual(fullEvents, [service.id])
        XCTAssertFalse(scheduler.hasPendingImmediateHibernation(service.id))
    }

    @MainActor
    func testSoftWakeCancelsImmediateHibernation() throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let service = service(label: "Return", policy: .immediate)
        fixture.container.mainContext.insert(service)
        try fixture.container.mainContext.save()

        var hibernated: [UUID] = []
        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            immediateDelay: .seconds(60),
            idleCandidates: { _ in [] },
            hibernate: {
                hibernated.append($0)
                return true
            }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )

        fixture.pool.onServiceSoftHibernated?(service.id)
        XCTAssertTrue(scheduler.hasPendingImmediateHibernation(service.id))

        fixture.pool.onServiceSoftWoke?(service.id)

        XCTAssertFalse(scheduler.hasPendingImmediateHibernation(service.id))
        XCTAssertTrue(hibernated.isEmpty)
    }

    @MainActor
    func testPolicyChangeRegatesThePeriodicSweep() throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            idleCandidates: { _ in [] },
            hibernate: { _ in false }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )
        XCTAssertFalse(scheduler.isIdleSweepScheduled)

        let service = service(label: "Timed", policy: .after, afterMinutes: 5)
        fixture.container.mainContext.insert(service)
        try fixture.container.mainContext.save()
        scheduler.servicePolicyDidChange(service.id)
        XCTAssertTrue(scheduler.isIdleSweepScheduled)

        service.hibernationPolicyRaw = HibernationPolicy.followGlobal.rawValue
        try fixture.container.mainContext.save()
        scheduler.servicePolicyDidChange(service.id)
        XCTAssertFalse(scheduler.isIdleSweepScheduled)
    }

    @MainActor
    func testShutdownCancelsTasksAndRemovesPoolCallbacks() throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let service = service(label: "Shutdown", policy: .immediate)
        fixture.container.mainContext.insert(service)
        try fixture.container.mainContext.save()
        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            immediateDelay: .seconds(60),
            idleCandidates: { _ in [] },
            hibernate: { _ in true }
        )
        scheduler.start(
            globalEnabled: true,
            globalIdleMinutes: 10,
            isLocked: { false }
        )
        fixture.pool.onServiceSoftHibernated?(service.id)
        fixture.pool.onServiceEvictedForCapacity?(service.id)
        XCTAssertTrue(scheduler.isIdleSweepScheduled)
        XCTAssertTrue(scheduler.hasPendingImmediateHibernation(service.id))
        XCTAssertNotNil(scheduler.capacityEvictionNotice)

        scheduler.shutdown()

        XCTAssertFalse(scheduler.isIdleSweepScheduled)
        XCTAssertFalse(scheduler.hasPendingImmediateHibernation(service.id))
        XCTAssertNil(scheduler.capacityEvictionNotice)
        XCTAssertNil(fixture.pool.isNotificationCritical)
        XCTAssertNil(fixture.pool.onServiceHibernated)
        XCTAssertNil(fixture.pool.onServiceEvictedForCapacity)
        XCTAssertNil(fixture.pool.onServiceWoke)
        XCTAssertNil(fixture.pool.onServiceSoftHibernated)
        XCTAssertNil(fixture.pool.onServiceSoftWoke)
        XCTAssertNil(fixture.pool.onServiceRemoved)
    }

    /// The capacity limit is invisible in the interface, so the first release
    /// must explain itself and name the service. The rule does not change, so a
    /// later release in the same app run must stay silent.
    @MainActor
    func testTheCapacityNoticeAppearsOnceForEachAppRun() throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let first = service(label: "Notion", policy: .followGlobal)
        let second = service(label: "Linear", policy: .followGlobal)
        fixture.container.mainContext.insert(first)
        fixture.container.mainContext.insert(second)
        try fixture.container.mainContext.save()

        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            idleCandidates: { _ in [] },
            hibernate: { _ in true }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )
        XCTAssertNil(scheduler.capacityEvictionNotice)

        fixture.pool.onServiceEvictedForCapacity?(first.id)

        let notice = try XCTUnwrap(scheduler.capacityEvictionNotice)
        XCTAssertTrue(notice.contains("Notion"), notice)
        XCTAssertTrue(notice.contains("\"Keep Loaded\""), notice)

        fixture.pool.onServiceEvictedForCapacity?(second.id)
        XCTAssertEqual(scheduler.capacityEvictionNotice, notice, "the second release repeats no notice")

        scheduler.dismissCapacityEvictionNotice()
        XCTAssertNil(scheduler.capacityEvictionNotice)

        fixture.pool.onServiceEvictedForCapacity?(second.id)
        XCTAssertNil(scheduler.capacityEvictionNotice, "a dismissed notice does not return in the same run")
    }

    /// A released service can be deleted before the notice is built. The notice
    /// must still explain the rule instead of naming nothing.
    @MainActor
    func testTheCapacityNoticeSurvivesAnUnknownService() throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let scheduler = HibernationScheduler(
            context: fixture.container.mainContext,
            webViewPool: fixture.pool,
            idleCandidates: { _ in [] },
            hibernate: { _ in true }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )

        fixture.pool.onServiceEvictedForCapacity?(UUID())

        let notice = try XCTUnwrap(scheduler.capacityEvictionNotice)
        XCTAssertTrue(notice.contains(CapacityEvictionNotice.fallbackServiceName), notice)
    }

    /// A call must survive the idle sweep as well as the capacity sweep. This
    /// test runs the real pool decision instead of an injected one, so it proves
    /// that the idle path honors both guards: a live camera and a call that the
    /// probe reports.
    @MainActor
    func testIdleSweepSparesCaptureAndReportedCalls() async throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let context = fixture.container.mainContext
        let capturing = service(label: "Camera", policy: .after, afterMinutes: 1, url: "about:blank")
        let calling = service(label: "Meeting", policy: .after, afterMinutes: 1, url: "about:blank")
        let idle = service(label: "Notes", policy: .after, afterMinutes: 1, url: "about:blank")
        for item in [capturing, calling, idle] { context.insert(item) }
        try context.save()

        for item in [capturing, calling, idle] { fixture.pool.preload(item) }
        fixture.pool.setMediaCaptureState(
            WebViewPool.MediaCaptureState(cameraActive: true),
            for: capturing.id
        )
        fixture.pool.callDetectionProbe = { $0 == calling.id }

        // No injected `hibernate`, so the sweep calls the pool guard itself.
        let scheduler = HibernationScheduler(
            context: context,
            webViewPool: fixture.pool,
            idleCandidates: { _ in
                [(capturing.id, 61), (calling.id, 61), (idle.id, 61)]
            }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )

        await scheduler.runIdleSweep()

        XCTAssertFalse(
            fixture.pool.isHibernated(capturing.id),
            "a live camera keeps its service loaded"
        )
        XCTAssertTrue(fixture.pool.hasWebView(for: capturing.id))
        XCTAssertFalse(
            fixture.pool.isHibernated(calling.id),
            "a reported call keeps its service loaded"
        )
        XCTAssertTrue(fixture.pool.hasWebView(for: calling.id))
        XCTAssertTrue(
            fixture.pool.isHibernated(idle.id),
            "an idle service without a call still hibernates"
        )
    }

    /// The guard releases the service after the call ends, so the next sweep
    /// hibernates it.
    @MainActor
    func testIdleSweepHibernatesAServiceAfterItsCaptureEnds() async throws {
        let fixture = try makeFixture()
        defer { fixture.pool.shutdown() }
        let context = fixture.container.mainContext
        let capturing = service(label: "Camera", policy: .after, afterMinutes: 1, url: "about:blank")
        context.insert(capturing)
        try context.save()

        fixture.pool.preload(capturing)
        fixture.pool.setMediaCaptureState(
            WebViewPool.MediaCaptureState(micMuted: true),
            for: capturing.id
        )
        fixture.pool.callDetectionProbe = { _ in false }

        let scheduler = HibernationScheduler(
            context: context,
            webViewPool: fixture.pool,
            idleCandidates: { _ in [(capturing.id, 61)] }
        )
        defer { scheduler.shutdown() }
        scheduler.start(
            globalEnabled: false,
            globalIdleMinutes: 10,
            isLocked: { false }
        )

        await scheduler.runIdleSweep()
        XCTAssertFalse(fixture.pool.isHibernated(capturing.id))

        fixture.pool.setMediaCaptureState(nil, for: capturing.id)
        await scheduler.runIdleSweep()
        XCTAssertTrue(fixture.pool.isHibernated(capturing.id))
    }

    @MainActor
    private func makeFixture() throws -> (container: ModelContainer, pool: WebViewPool) {
        let container = try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let pool = WebViewPool(
            dataStoreManager: DataStoreManager(),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
        return (container, pool)
    }

    private func service(
        label: String,
        policy: HibernationPolicy,
        afterMinutes: Int? = nil,
        catalogEntryID: String? = nil,
        url: String? = nil
    ) -> ServiceInstance {
        ServiceInstance(
            label: label,
            url: url ?? "https://\(label.lowercased()).example",
            catalogEntryID: catalogEntryID,
            hibernationPolicyRaw: policy.rawValue,
            hibernateAfterMinutes: afterMinutes
        )
    }
}
