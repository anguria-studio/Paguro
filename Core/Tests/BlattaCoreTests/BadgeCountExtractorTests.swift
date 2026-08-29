import Foundation
import Testing
@testable import BlattaCore

struct BadgeCountExtractorTests {
    @Test
    func extractsPlausibleCountsFromTheTitleHead() {
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox (5) - Gmail") == 5)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "(12) Slack") == 12)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "(999) WhatsApp Web") == 999)
    }

    @Test
    func ignoresMissingInvalidAndTrailingCounts() {
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "No badges here") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "(0) Inbox") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Annual Report (2024) - Drive") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox - account (5)") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox | account (5)") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox — account (5)") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox : account (5)") == 0)
        #expect(BadgeCountExtractor.extractBadgeCount(
            from: "Inbox · account (5)") == 0)
    }

    /// The titles that Gmail, WhatsApp Web, and Discord write in a real
    /// account. A change here means the Dock badge stops for that service.
    @Test
    func readsTheTitleOfEachAudiencedService() {
        #expect(BadgeCountExtractor.readTitle(
            "Inbox (17) - person@example.com - Gmail").count == 17)
        #expect(BadgeCountExtractor.readTitle("(3) WhatsApp").count == 3)
        #expect(BadgeCountExtractor.readTitle("WhatsApp").count == 0)
        #expect(BadgeCountExtractor.readTitle(
            "(2) #general | Example Server | Discord").count == 2)
        #expect(BadgeCountExtractor.readTitle(
            "#general | Example Server | Discord").count == 0)
        #expect(BadgeCountExtractor.readTitle(
            "(8) general (Channel) - Example - Slack").count == 8)
        #expect(BadgeCountExtractor.readTitle("Telegram (4)").count == 4)
    }

    /// The log text holds the count and the shape only. A title can hold a
    /// message subject, so the reading must not repeat the title.
    @Test
    func titleLogTextHoldsNoTitleText() {
        #expect(BadgeCountExtractor.readTitle("(3) WhatsApp").raw == "(3)")
        let quiet = BadgeCountExtractor.readTitle("Secret subject line - Gmail")
        #expect(quiet.raw == "none/len=27")
        #expect(!quiet.raw.contains("Secret"))
    }

    @Test
    func readsNumbersThatWebKitReturns() {
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: 4)).count == 4)
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: 0)).count == 0)
        // WebKit returns every JavaScript number as a double.
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: 7.0)).count == 7)
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: 7.9)).count == 7)
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: -3)).count == 0)
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: Double.nan)).count == nil)
    }

    /// A badge rule returns `null` when it cannot read its page. That value
    /// must leave the current badge alone.
    @Test
    func reportsNoCountForValuesThatCarryNoNumber() {
        #expect(BadgeCountExtractor.readJSResult(nil).count == nil)
        #expect(BadgeCountExtractor.readJSResult(NSNull()).count == nil)
        #expect(BadgeCountExtractor.readJSResult(true).count == nil)
        #expect(BadgeCountExtractor.readJSResult(false).count == nil)
        #expect(BadgeCountExtractor.readJSResult(["a": 1]).count == nil)
        #expect(BadgeCountExtractor.readJSResult("New").count == nil)
    }

    /// Element text is the common shape of a DOM badge value.
    @Test
    func readsBadgeElementText() {
        #expect(BadgeCountExtractor.readJSResult("12").count == 12)
        #expect(BadgeCountExtractor.readJSResult(" 3 ").count == 3)
        #expect(BadgeCountExtractor.readJSResult("9+").count == 9)
        #expect(BadgeCountExtractor.readJSResult("1,234").count == 1234)
        #expect(BadgeCountExtractor.readJSResult("").count == 0)
        #expect(BadgeCountExtractor.readJSResult("   ").count == 0)
    }

    /// Long element text can hold page content, so the log keeps a length only.
    @Test
    func jsLogTextStaysShort() {
        #expect(BadgeCountExtractor.readJSResult(NSNumber(value: 5)).raw == "number(5)")
        #expect(BadgeCountExtractor.readJSResult(NSNull()).raw == "null")
        #expect(BadgeCountExtractor.readJSResult("9+").raw == "string(9+)")
        let long = String(repeating: "a", count: 40)
        #expect(BadgeCountExtractor.readJSResult(long).raw == "string(len=40)")
    }
}
