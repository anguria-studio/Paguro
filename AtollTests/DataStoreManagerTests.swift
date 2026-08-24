import Foundation
import WebKit
import XCTest
@testable import Atoll

@MainActor
final class DataStoreManagerTests: XCTestCase {
    private static let accountAIdentifier = UUID(uuidString: "A7011000-0000-4000-8000-000000000001")!
    private static let accountBIdentifier = UUID(uuidString: "A7011000-0000-4000-8000-000000000002")!

    func testManagerUsesAndCachesTheAccountIdentifier() {
        let identifier = UUID()
        let service = ServiceInstance(
            label: "Fixture account",
            url: "https://localhost:8443",
            dataStoreIdentifier: identifier
        )
        let manager = DataStoreManager()

        let first = manager.dataStore(for: service)
        let second = manager.dataStore(forIdentifier: identifier)

        XCTAssertEqual(first.identifier, identifier)
        XCTAssertTrue(first === second, "one manager must reuse one store object for an account")
    }

    func testSameOriginAccountsStaySeparateAfterManagerRecreation() async throws {
        let cookieName = "atoll-isolation-\(UUID().uuidString)"
        let accountAValue = "account-a"
        let accountBValue = "account-b"

        let firstManager = DataStoreManager()
        let firstAccountA = firstManager.dataStore(forIdentifier: Self.accountAIdentifier)
        let firstAccountB = firstManager.dataStore(forIdentifier: Self.accountBIdentifier)

        let accountACookie = try XCTUnwrap(Self.markerCookie(name: cookieName, value: accountAValue))
        let accountBCookie = try XCTUnwrap(Self.markerCookie(name: cookieName, value: accountBValue))
        await setCookie(accountACookie, in: firstAccountA.httpCookieStore)
        await setCookie(accountBCookie, in: firstAccountB.httpCookieStore)

        let firstAccountAMarker = await markerValue(named: cookieName, in: firstAccountA)
        let firstAccountBMarker = await markerValue(named: cookieName, in: firstAccountB)
        XCTAssertEqual(firstAccountAMarker, accountAValue)
        XCTAssertEqual(firstAccountBMarker, accountBValue)

        // A new manager models the application rebuilding its service graph after launch.
        let relaunchedManager = DataStoreManager()
        let relaunchedAccountA = relaunchedManager.dataStore(forIdentifier: Self.accountAIdentifier)
        let relaunchedAccountB = relaunchedManager.dataStore(forIdentifier: Self.accountBIdentifier)

        XCTAssertEqual(relaunchedAccountA.identifier, Self.accountAIdentifier)
        XCTAssertEqual(relaunchedAccountB.identifier, Self.accountBIdentifier)
        let relaunchedAccountAMarker = await markerValue(named: cookieName, in: relaunchedAccountA)
        let relaunchedAccountBMarker = await markerValue(named: cookieName, in: relaunchedAccountB)
        XCTAssertEqual(relaunchedAccountAMarker, accountAValue)
        XCTAssertEqual(relaunchedAccountBMarker, accountBValue)

        await deleteCookie(accountACookie, from: relaunchedAccountA.httpCookieStore)
        let clearedAccountAMarker = await markerValue(named: cookieName, in: relaunchedAccountA)
        let unchangedAccountBMarker = await markerValue(named: cookieName, in: relaunchedAccountB)
        XCTAssertNil(clearedAccountAMarker)
        XCTAssertEqual(
            unchangedAccountBMarker,
            accountBValue,
            "clearing one account must not change the second account"
        )

        await deleteCookie(accountBCookie, from: relaunchedAccountB.httpCookieStore)
    }

    private static func markerCookie(name: String, value: String) -> HTTPCookie? {
        HTTPCookie(properties: [
            .domain: "localhost",
            .path: "/",
            .name: name,
            .value: value,
            .secure: "TRUE",
            .expires: Date(timeIntervalSinceNow: 300),
        ])
    }

    private func markerValue(named name: String, in dataStore: WKWebsiteDataStore) async -> String? {
        let cookies = await allCookies(in: dataStore.httpCookieStore)
        return cookies.first { $0.name == name && $0.domain == "localhost" }?.value
    }

    private func setCookie(_ cookie: HTTPCookie, in store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.setCookie(cookie) {
                continuation.resume()
            }
        }
    }

    private func allCookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func deleteCookie(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) {
                continuation.resume()
            }
        }
    }
}
