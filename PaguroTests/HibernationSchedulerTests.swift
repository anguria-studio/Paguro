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
        XCTAssertTrue(scheduler.isIdleSweepScheduled)
        XCTAssertTrue(scheduler.hasPendingImmediateHibernation(service.id))

        scheduler.shutdown()

        XCTAssertFalse(scheduler.isIdleSweepScheduled)
        XCTAssertFalse(scheduler.hasPendingImmediateHibernation(service.id))
        XCTAssertNil(fixture.pool.isNotificationCritical)
        XCTAssertNil(fixture.pool.onServiceHibernated)
        XCTAssertNil(fixture.pool.onServiceWoke)
        XCTAssertNil(fixture.pool.onServiceSoftHibernated)
        XCTAssertNil(fixture.pool.onServiceSoftWoke)
        XCTAssertNil(fixture.pool.onServiceRemoved)
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
        catalogEntryID: String? = nil
    ) -> ServiceInstance {
        ServiceInstance(
            label: label,
            url: "https://\(label.lowercased()).example",
            catalogEntryID: catalogEntryID,
            hibernationPolicyRaw: policy.rawValue,
            hibernateAfterMinutes: afterMinutes
        )
    }
}
