import BlattaCore
import Foundation
import Testing

@Suite("Notification island focus recovery")
struct NotificationIslandFocusRuleTests {
    @Test func dismissalKeepsReadingOrder() {
        let ids = [UUID(), UUID(), UUID()]
        #expect(NotificationIslandFocusRule.replacement(for: ids[0], in: ids) == ids[1])
        #expect(NotificationIslandFocusRule.replacement(for: ids[1], in: ids) == ids[2])
        #expect(NotificationIslandFocusRule.replacement(for: ids[2], in: ids) == ids[1])
    }

    @Test func noRemainingOrMatchingCardHasNoReplacement() {
        let id = UUID()
        #expect(NotificationIslandFocusRule.replacement(for: id, in: [id]) == nil)
        #expect(NotificationIslandFocusRule.replacement(for: id, in: []) == nil)
        #expect(NotificationIslandFocusRule.replacement(for: id, in: [UUID()]) == nil)
    }
}
