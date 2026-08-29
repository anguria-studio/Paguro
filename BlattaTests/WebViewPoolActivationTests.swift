import SwiftData
import WebKit
import XCTest
@testable import Blatta

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

    @MainActor
    private func makePool() -> WebViewPool {
        WebViewPool(
            dataStoreManager: DataStoreManager(),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
    }
}
