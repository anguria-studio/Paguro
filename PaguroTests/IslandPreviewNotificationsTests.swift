#if DEBUG
import Foundation
import PaguroCore
import XCTest
@testable import Paguro

final class IslandPreviewNotificationsTests: XCTestCase {
    func testCatalogContainsTwelveValidFictionalNotifications() throws {
        let messages = IslandPreviewNotifications.messages
        XCTAssertEqual(messages.count, 12)
        for catalogID in ["slack", "whatsapp", "gmail"] {
            XCTAssertEqual(messages.filter { $0.catalogID == catalogID }.count, 4, catalogID)
        }
        for message in messages {
            let event = try NotificationEvent.normalize(
                id: UUID(), serviceID: UUID(), source: .pageNotification,
                title: message.title, body: message.body, receivedAt: Date()
            )
            XCTAssertEqual(event.title, message.title)
            XCTAssertEqual(event.body, message.body)
            XCTAssertNil(event.targetURL)
        }
    }

    func testSelectionUsesOnlyConfiguredAccountsAndDoesNotRepeatTheLastMessage() throws {
        let slack = account("slack")
        let gmail = account("gmail")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        var previous: IslandPreviewNotifications.Message?
        var seenServices: Set<UUID> = []
        for _ in 0..<100 {
            let selection = try XCTUnwrap(previews.next(accounts: [slack, gmail], using: &random))
            XCTAssertNotEqual(selection.message, previous)
            let expectedID = selection.message.catalogID == "slack" ? slack.serviceID : gmail.serviceID
            XCTAssertEqual(selection.serviceID, expectedID)
            XCTAssertNotEqual(selection.message.catalogID, "whatsapp")
            seenServices.insert(selection.serviceID)
            previous = selection.message
        }
        XCTAssertEqual(seenServices, [slack.serviceID, gmail.serviceID])
    }

    func testASingleServiceStillHasVarietyAndRemovedAccountsAreNotReused() throws {
        let slack = account("slack")
        let whatsapp = account("whatsapp")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        _ = previews.next(accounts: [slack], using: &random)
        var previous: IslandPreviewNotifications.Message?
        var seenBodies: Set<String> = []
        for _ in 0..<30 {
            let selection = try XCTUnwrap(previews.next(accounts: [whatsapp], using: &random))
            XCTAssertEqual(selection.serviceID, whatsapp.serviceID)
            XCTAssertEqual(selection.message.catalogID, "whatsapp")
            XCTAssertNotEqual(selection.message, previous)
            previous = selection.message
            seenBodies.insert(selection.message.body)
        }
        XCTAssertEqual(seenBodies.count, 4)
    }

    func testSeparateAccountsForTheSameServiceKeepTheirOwnIDs() throws {
        let personal = account("gmail")
        let work = account("gmail")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        var seenServices: Set<UUID> = []
        for _ in 0..<50 {
            let selection = try XCTUnwrap(previews.next(accounts: [personal, work], using: &random))
            XCTAssertEqual(selection.message.catalogID, "gmail")
            seenServices.insert(selection.serviceID)
        }
        XCTAssertEqual(seenServices, [personal.serviceID, work.serviceID])
    }

    func testEmptyOrUnsupportedAccountsAllowTheGenericPreviewFallback() {
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        XCTAssertNil(previews.next(accounts: [], using: &random))
        XCTAssertNil(previews.next(accounts: [account("telegram")], using: &random))
    }

    func testCustomAccountsUseKnownServiceHosts() throws {
        let cases = [
            ("https://web.whatsapp.com/", "whatsapp"),
            ("https://mail.google.com/mail/u/1/#inbox", "gmail"),
            ("https://app.slack.com/client", "slack"),
            ("https://design-team.slack.com/", "slack")
        ]
        for (url, expected) in cases {
            let custom = IslandPreviewNotifications.Account(serviceID: UUID(), catalogID: nil, url: url)
            var previews = IslandPreviewNotifications()
            var random = SeededGenerator()
            let selection = try XCTUnwrap(previews.next(accounts: [custom], using: &random), url)
            XCTAssertEqual(selection.serviceID, custom.serviceID, url)
            XCTAssertEqual(selection.message.catalogID, expected, url)
        }
    }

    func testUnrelatedAddressesDoNotGenerateBrandedMessages() {
        let urls = [
            "https://example.com/slack.com", "https://notslack.com/",
            "https://web.whatsapp.com.example.com/", "https://calendar.google.com/", "not a URL"
        ]
        for url in urls {
            let custom = IslandPreviewNotifications.Account(serviceID: UUID(), catalogID: nil, url: url)
            var previews = IslandPreviewNotifications()
            var random = SeededGenerator()
            XCTAssertNil(previews.next(accounts: [custom], using: &random), url)
        }
    }

    private func account(_ catalogID: String) -> IslandPreviewNotifications.Account {
        IslandPreviewNotifications.Account(serviceID: UUID(), catalogID: catalogID, url: "https://example.com")
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64 = 42

    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}
#endif
