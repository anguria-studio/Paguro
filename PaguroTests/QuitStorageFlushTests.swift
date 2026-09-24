import Foundation
import WebKit
import XCTest
import PaguroCore
@testable import Paguro

@MainActor
final class QuitStorageFlushTests: XCTestCase {
    /// A stand-in for a data store. The flush only needs object identity.
    private final class FakeStore {}

    /// Records which fetches started and which finished.
    private final class FetchLog {
        var started = 0
        var finished = 0
        var startedWhenFirstFinished = 0
    }

    func testHungStoreCannotHoldTheQuitPastTheTimeout() async {
        let stores = [FakeStore(), FakeStore()]
        let hung = stores[1]
        let start = ContinuousClock.now

        let outcome = await QuitStorageFlush.run(
            stores: stores,
            teardownFinishedAt: start,
            timeout: .milliseconds(200),
            minimumWait: .milliseconds(10)
        ) { store in
            // The hung store never answers within the test.
            if store === hung { try? await Task.sleep(for: .seconds(30)) }
        }
        let waited = ContinuousClock.now - start

        XCTAssertEqual(outcome.storeCount, 2)
        XCTAssertEqual(outcome.completedCount, 1)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(200))
        XCTAssertLessThan(waited, .seconds(2), "the timeout must end the flush")
    }

    func testFastStoresStillWaitTheMinimumAfterTeardown() async {
        let start = ContinuousClock.now

        let outcome = await QuitStorageFlush.run(
            stores: [FakeStore()],
            teardownFinishedAt: start,
            timeout: .seconds(5),
            minimumWait: .milliseconds(80)
        ) { _ in }
        let waited = ContinuousClock.now - start

        XCTAssertEqual(outcome.completedCount, 1)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertGreaterThanOrEqual(waited, .milliseconds(80))
        XCTAssertGreaterThanOrEqual(outcome.elapsed, .milliseconds(80))
        XCTAssertLessThan(waited, .seconds(2))
    }

    func testMinimumWaitCountsTimeAlreadySpentSinceTeardown() async {
        let teardown = ContinuousClock.now - .milliseconds(200)
        let callStart = ContinuousClock.now

        let outcome = await QuitStorageFlush.run(
            stores: [FakeStore()],
            teardownFinishedAt: teardown,
            timeout: .seconds(5),
            minimumWait: .milliseconds(100)
        ) { _ in }
        let waited = ContinuousClock.now - callStart

        XCTAssertFalse(outcome.timedOut)
        XCTAssertLessThan(waited, .milliseconds(90), "the minimum already passed before the call")
        XCTAssertGreaterThanOrEqual(outcome.elapsed, .milliseconds(200))
    }

    func testStoresAreFetchedInParallel() async {
        let stores = (0..<4).map { _ in FakeStore() }
        let log = FetchLog()
        let start = ContinuousClock.now

        let outcome = await QuitStorageFlush.run(
            stores: stores,
            teardownFinishedAt: start,
            timeout: .seconds(5),
            minimumWait: .zero
        ) { _ in
            log.started += 1
            try? await Task.sleep(for: .milliseconds(150))
            if log.finished == 0 { log.startedWhenFirstFinished = log.started }
            log.finished += 1
        }
        let waited = ContinuousClock.now - start

        XCTAssertEqual(outcome.completedCount, 4)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertEqual(log.startedWhenFirstFinished, 4, "every fetch must start before the first one ends")
        XCTAssertLessThan(waited, .milliseconds(500), "four 150 ms fetches in sequence would take 600 ms")
    }

    func testNoStoresReturnsWithoutWaiting() async {
        let start = ContinuousClock.now

        let outcome = await QuitStorageFlush.run(
            stores: [FakeStore](),
            teardownFinishedAt: start,
            timeout: .seconds(5),
            minimumWait: .seconds(5)
        ) { _ in XCTFail("no store to fetch") }

        XCTAssertEqual(outcome.storeCount, 0)
        XCTAssertEqual(outcome.completedCount, 0)
        XCTAssertFalse(outcome.timedOut)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
    }

    func testPoolSkipsNonPersistentStores() {
        let pool = WebViewPool(
            dataStoreManager: DataStoreManager(arguments: [FirstRunPreviewConfiguration.launchArgument]),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
        defer { pool.shutdown() }
        _ = pool.webView(for: ServiceInstance(label: "Preview", url: "about:blank"))

        XCTAssertEqual(pool.loadedCount, 1)
        XCTAssertTrue(pool.persistentDataStoresForQuitFlush().isEmpty)
    }

    func testPoolListsEachPersistentStoreOnce() {
        let pool = WebViewPool(
            dataStoreManager: DataStoreManager(arguments: []),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
        defer { pool.shutdown() }
        let shared = UUID()
        let first = ServiceInstance(label: "First", url: "about:blank", dataStoreIdentifier: shared)
        let second = ServiceInstance(label: "Second", url: "about:blank", dataStoreIdentifier: shared)
        let third = ServiceInstance(label: "Third", url: "about:blank")
        for service in [first, second, third] {
            _ = pool.webView(for: service)
        }

        let stores = pool.persistentDataStoresForQuitFlush()

        XCTAssertEqual(stores.count, 2)
        XCTAssertTrue(stores.allSatisfy(\.isPersistent))
        XCTAssertEqual(Set(stores.compactMap(\.identifier)), [shared, third.dataStoreIdentifier])
    }
}
