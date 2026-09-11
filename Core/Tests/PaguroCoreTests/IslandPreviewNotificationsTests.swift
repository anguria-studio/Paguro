#if DEBUG
import Foundation
import Testing
@testable import PaguroCore

struct IslandPreviewNotificationsTests {
    @Test
    func catalogContainsTwelveValidFictionalNotifications() throws {
        let messages = IslandPreviewNotifications.messages
        #expect(messages.count == 12)
        for catalogID in ["slack", "whatsapp", "gmail"] {
            #expect(messages.filter { $0.catalogID == catalogID }.count == 4)
        }
        for message in messages {
            let event = try NotificationEvent.normalize(
                id: UUID(), serviceID: UUID(), source: .pageNotification,
                title: message.title, body: message.body, receivedAt: Date()
            )
            #expect(event.title == message.title)
            #expect(event.body == message.body)
            #expect(event.targetURL == nil)
        }
    }

    @Test
    func selectionUsesOnlyConfiguredAccountsAndDoesNotRepeatTheLastMessage() throws {
        let slack = account("slack")
        let gmail = account("gmail")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        var previous: IslandPreviewNotifications.Message?
        var seenServices: Set<UUID> = []
        for _ in 0..<100 {
            let selection = try #require(previews.next(accounts: [slack, gmail], using: &random))
            #expect(selection.message != previous)
            let expectedID = selection.message.catalogID == "slack" ? slack.serviceID : gmail.serviceID
            #expect(selection.serviceID == expectedID)
            #expect(selection.message.catalogID != "whatsapp")
            seenServices.insert(selection.serviceID)
            previous = selection.message
        }
        #expect(seenServices == [slack.serviceID, gmail.serviceID])
    }

    @Test
    func aSingleServiceStillHasVarietyAndRemovedAccountsAreNotReused() throws {
        let slack = account("slack")
        let whatsapp = account("whatsapp")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        _ = previews.next(accounts: [slack], using: &random)
        var previous: IslandPreviewNotifications.Message?
        var seenBodies: Set<String> = []
        for _ in 0..<30 {
            let selection = try #require(previews.next(accounts: [whatsapp], using: &random))
            #expect(selection.serviceID == whatsapp.serviceID)
            #expect(selection.message.catalogID == "whatsapp")
            #expect(selection.message != previous)
            previous = selection.message
            seenBodies.insert(selection.message.body)
        }
        #expect(seenBodies.count == 4)
    }

    @Test
    func separateAccountsForTheSameServiceKeepTheirOwnIDs() throws {
        let personal = account("gmail")
        let work = account("gmail")
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        var seenServices: Set<UUID> = []
        for _ in 0..<50 {
            let selection = try #require(previews.next(accounts: [personal, work], using: &random))
            #expect(selection.message.catalogID == "gmail")
            seenServices.insert(selection.serviceID)
        }
        #expect(seenServices == [personal.serviceID, work.serviceID])
    }

    @Test
    func emptyOrUnsupportedAccountsAllowTheGenericPreviewFallback() {
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        #expect(previews.next(accounts: [], using: &random) == nil)
        #expect(previews.next(accounts: [account("telegram")], using: &random) == nil)
    }

    @Test(arguments: [
        ("https://web.whatsapp.com/", "whatsapp"),
        ("https://mail.google.com/mail/u/1/#inbox", "gmail"),
        ("https://app.slack.com/client", "slack"),
        ("https://design-team.slack.com/", "slack")
    ])
    func customAccountsUseKnownServiceHosts(url: String, expected: String) throws {
        let custom = IslandPreviewNotifications.Account(serviceID: UUID(), catalogID: nil, url: url)
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        let selection = try #require(previews.next(accounts: [custom], using: &random))
        #expect(selection.serviceID == custom.serviceID)
        #expect(selection.message.catalogID == expected)
    }

    @Test(arguments: [
        "https://example.com/slack.com", "https://notslack.com/",
        "https://web.whatsapp.com.example.com/", "https://calendar.google.com/", "not a URL"
    ])
    func unrelatedAddressesDoNotGenerateBrandedMessages(url: String) {
        let custom = IslandPreviewNotifications.Account(serviceID: UUID(), catalogID: nil, url: url)
        var previews = IslandPreviewNotifications()
        var random = SeededGenerator()
        #expect(previews.next(accounts: [custom], using: &random) == nil)
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
