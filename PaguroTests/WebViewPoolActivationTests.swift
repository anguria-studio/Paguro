import SwiftData
import WebKit
import XCTest
import PaguroCore
@testable import Paguro

final class WebViewPoolActivationTests: XCTestCase {
    private enum Event: Equatable {
        case softHibernated(UUID)
        case activated(UUID)
    }

    @MainActor
    func testActivationCallbackReceivesTheRegisteredLiveWebView() {
        let pool = makePool()
        defer { pool.shutdown() }
        let service = ServiceInstance(label: "Mail", url: "about:blank")
        var callbackValues: [(UUID, WKWebView)] = []
        pool.onServiceActivated = { callbackValues.append(($0, $1)) }

        let webView = pool.webView(for: service)

        XCTAssertEqual(callbackValues.count, 1)
        XCTAssertEqual(callbackValues.first?.0, service.id)
        XCTAssertTrue(callbackValues.first?.1 === webView)
        XCTAssertTrue(pool.liveWebView(for: service.id) === webView)
        XCTAssertEqual(pool.activeServiceID, service.id)

        let sameWebView = pool.webView(for: service)
        XCTAssertTrue(sameWebView === webView)
        XCTAssertEqual(callbackValues.count, 2)
        XCTAssertTrue(callbackValues.last?.1 === webView)
    }

    @MainActor
    func testSwitchAndDeactivationReportLifecycleInOrder() {
        let pool = makePool()
        defer { pool.shutdown() }
        let first = ServiceInstance(label: "First", url: "about:blank")
        let second = ServiceInstance(label: "Second", url: "about:blank")
        var events: [Event] = []
        pool.onServiceSoftHibernated = { serviceID in
            events.append(Event.softHibernated(serviceID))
        }
        pool.onServiceActivated = { serviceID, _ in
            events.append(Event.activated(serviceID))
        }

        _ = pool.webView(for: first)
        events.removeAll()
        _ = pool.webView(for: second)

        XCTAssertEqual(events, [
            .softHibernated(first.id),
            .activated(second.id),
        ])

        events.removeAll()
        pool.deactivateCurrentService()
        XCTAssertEqual(events, [.softHibernated(second.id)])
        XCTAssertNil(pool.activeServiceID)
    }

    @MainActor
    func testShutdownRejectsLaterPreloads() async throws {
        let container = try ModelFixtures.groupingContainer()
        let service = ServiceInstance(label: "Mail", url: "about:blank")
        container.mainContext.insert(service)
        try container.mainContext.save()
        let pool = makePool()

        pool.shutdown()
        pool.preload(service)
        await pool.preloadAll([service], delayBetween: .zero)

        XCTAssertEqual(pool.loadedCount, 0)
    }

    /// The pool limit is separate from idle hibernation, so a full pool must
    /// release the least recently used service on its own. Every exemption must
    /// survive that sweep, and the capacity callback must name the one service
    /// that the sweep released.
    @MainActor
    func testCapacitySweepReleasesTheLeastRecentUnprotectedService() async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        // Twelve ordinary services plus four protected ones is one over the
        // limit, so the sweep must release exactly one of them.
        let store = UUID()
        let ordinary = (0..<(WebViewPoolCapacity.maxLoaded - 3)).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        let keepLoaded = Self.poolService(
            label: "Keep Loaded",
            store: store,
            hibernationPolicyRaw: HibernationPolicy.never.rawValue
        )
        let chat = Self.poolService(label: "Chat", store: store, catalogEntryID: "slack")
        let pinned = Self.poolService(label: "Pinned", store: store)
        let active = Self.poolService(label: "Active", store: store)
        for item in ordinary + [keepLoaded, chat, pinned, active] {
            context.insert(item)
        }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }
        pool.isNotificationCritical = { $0 == chat.id }
        pool.pin(pinned.id)

        // Least recent first, so the expected victim is the oldest ordinary one.
        for item in ordinary + [keepLoaded, chat, pinned] {
            pool.preload(item)
        }
        _ = pool.webView(for: active)
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded + 1)

        // Each preload and activation also starts its own sweep. Wait for the
        // pool to settle instead of racing those tasks.
        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertEqual(evicted, [ordinary[0].id], "only the least recent unprotected service is released")
        XCTAssertTrue(pool.isHibernated(ordinary[0].id))
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded)

        for spared in [keepLoaded, chat, pinned, active] {
            XCTAssertFalse(pool.isHibernated(spared.id), "\(spared.label) must survive the capacity sweep")
            XCTAssertTrue(pool.hasWebView(for: spared.id), "\(spared.label) must keep its live web view")
        }
        for survivor in ordinary.dropFirst() {
            XCTAssertFalse(pool.isHibernated(survivor.id), "\(survivor.label) is not the least recent service")
        }
    }

    /// The sweep stops at the limit instead of reclaiming everything it can, so
    /// a second pass over a pool that is already at the limit releases nothing.
    @MainActor
    func testASweepAtTheLimitReleasesNothing() async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        let store = UUID()
        let services = (0..<WebViewPoolCapacity.maxLoaded).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        for item in services { context.insert(item) }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }
        for item in services { pool.preload(item) }

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertTrue(evicted.isEmpty)
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded)
    }

    /// A capacity test needs many services at the same time. They share one
    /// WebKit data-store identifier, so the test makes one store instead of one
    /// for each service. The pool keys every rule on the service id, so the
    /// shared store changes no result here.
    private static func poolService(
        label: String,
        store: UUID,
        catalogEntryID: String? = nil,
        hibernationPolicyRaw: String? = nil
    ) -> ServiceInstance {
        ServiceInstance(
            label: label,
            url: "about:blank",
            catalogEntryID: catalogEntryID,
            dataStoreIdentifier: store,
            hibernationPolicyRaw: hibernationPolicyRaw
        )
    }

    /// Waits until the pool holds no more views than its limit.
    @MainActor
    private func waitForLoadedCountToSettle(
        _ pool: WebViewPool,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while pool.loadedCount > WebViewPoolCapacity.maxLoaded, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertLessThanOrEqual(
            pool.loadedCount,
            WebViewPoolCapacity.maxLoaded,
            "the capacity sweep must bring the pool back to its limit"
        )
    }

    @MainActor
    private func makePool() -> WebViewPool {
        WebViewPool(
            dataStoreManager: DataStoreManager(),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
    }
}
