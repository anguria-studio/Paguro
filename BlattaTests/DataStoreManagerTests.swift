import Foundation
import WebKit
import XCTest
@testable import Blatta

@MainActor
final class DataStoreManagerTests: XCTestCase {
    func testManagerUsesAndCachesTheAccountIdentifier() async throws {
        let identifier = UUID()
        exerciseManagerCache(identifier: identifier)
        try await WKWebsiteDataStore.remove(forIdentifier: identifier)
    }

    private func exerciseManagerCache(identifier: UUID) {
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
        manager.evict(identifier: identifier)
    }

    func testSameOriginAccountsStaySeparateAfterManagerRecreation() async throws {
        let accountAIdentifier = UUID()
        let accountBIdentifier = UUID()

        let exerciseResult: Result<Void, Error>
        do {
            try await exerciseAccountIsolation(
                accountAIdentifier: accountAIdentifier,
                accountBIdentifier: accountBIdentifier
            )
            exerciseResult = .success(())
        } catch {
            exerciseResult = .failure(error)
        }

        var cleanupError: Error?
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: accountAIdentifier)
        } catch {
            cleanupError = error
        }
        do {
            try await WKWebsiteDataStore.remove(forIdentifier: accountBIdentifier)
        } catch {
            cleanupError = cleanupError ?? error
        }
        try exerciseResult.get()
        if let cleanupError {
            throw cleanupError
        }
    }

    private func exerciseAccountIsolation(
        accountAIdentifier: UUID,
        accountBIdentifier: UUID
    ) async throws {
        let cookieName = "blatta-isolation-\(UUID().uuidString)"
        let accountAValue = "account-a"
        let accountBValue = "account-b"

        let firstManager = DataStoreManager()
        let firstAccountA = firstManager.dataStore(forIdentifier: accountAIdentifier)
        let firstAccountB = firstManager.dataStore(forIdentifier: accountBIdentifier)

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
        let relaunchedAccountA = relaunchedManager.dataStore(forIdentifier: accountAIdentifier)
        let relaunchedAccountB = relaunchedManager.dataStore(forIdentifier: accountBIdentifier)

        XCTAssertEqual(relaunchedAccountA.identifier, accountAIdentifier)
        XCTAssertEqual(relaunchedAccountB.identifier, accountBIdentifier)
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
        firstManager.evict(identifier: accountAIdentifier)
        firstManager.evict(identifier: accountBIdentifier)
        relaunchedManager.evict(identifier: accountAIdentifier)
        relaunchedManager.evict(identifier: accountBIdentifier)
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
