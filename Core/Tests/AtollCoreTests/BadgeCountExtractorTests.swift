import Testing
@testable import AtollCore

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
}
