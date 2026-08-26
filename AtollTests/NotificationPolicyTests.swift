import XCTest
@testable import Atoll

final class NotificationPolicyTests: XCTestCase {
    // MARK: - BadgeManager

    @MainActor
    func testMutingPreservesRawCountAndRestoresOnUnmute() {
        let manager = BadgeManager()
        let id = UUID()

        // A live poll reports 5 unread.
        manager.updateBadge(for: id, count: 5, isMuted: false, showBadge: true)
        XCTAssertEqual(manager.badgeCount(for: id), 5)
        XCTAssertEqual(manager.rawCount(for: id), 5)

        // Muting hides the badge but must NOT destroy the real count — the
        // adaptive poller relies on rawCount to detect deltas, and un-muting
        // must restore the badge instantly without waiting for a poll tick.
        manager.updateBadge(for: id, count: 5, isMuted: true, showBadge: true)
        XCTAssertEqual(manager.badgeCount(for: id), 0, "muted badge is hidden")
        XCTAssertEqual(manager.rawCount(for: id), 5, "real count survives muting")

        // Un-mute by re-applying with the preserved rawCount (mirrors
        // AppState.refreshBadgeState reading rawCount).
        manager.updateBadge(for: id, count: manager.rawCount(for: id), isMuted: false, showBadge: true)
        XCTAssertEqual(manager.badgeCount(for: id), 5, "un-mute restores the badge immediately")
    }

    @MainActor
    func testAggregateAndTotalExcludeMaskedServices() {
        let manager = BadgeManager()
        let visible = UUID()
        let muted = UUID()
        let hidden = UUID()

        manager.updateBadge(for: visible, count: 3, isMuted: false, showBadge: true)
        manager.updateBadge(for: muted, count: 7, isMuted: true, showBadge: true)
        manager.updateBadge(for: hidden, count: 4, isMuted: false, showBadge: false)

        XCTAssertEqual(manager.aggregateCount(for: [visible, muted, hidden]), 3)
        XCTAssertEqual(manager.totalCount, 3)
        // Raw counts are all preserved regardless of masking.
        XCTAssertEqual(manager.rawCount(for: muted), 7)
        XCTAssertEqual(manager.rawCount(for: hidden), 4)
    }

    @MainActor
    func testDoNotDisturbKeepsVisibleAndRawCounts() {
        let manager = BadgeManager()
        let id = UUID()
        manager.updateBadge(for: id, count: 9, isMuted: false, showBadge: true)

        manager.doNotDisturb = true
        XCTAssertEqual(manager.badgeCount(for: id), 9)
        XCTAssertEqual(manager.aggregateCount(for: [id]), 9)
        XCTAssertEqual(manager.totalCount, 9)
        XCTAssertEqual(manager.rawCount(for: id), 9, "DND does not destroy the real count")

        manager.doNotDisturb = false
        XCTAssertEqual(manager.badgeCount(for: id), 9)
    }

    @MainActor
    func testUpdateBadgeClampsOutOfRangeCounts() {
        let manager = BadgeManager()
        let negative = UUID()
        let huge = UUID()
        let ok = UUID()

        // A misbehaving DOM badge (catalog badgeJS) could yield a negative or a
        // garbage-large value; a stored negative would subtract from the sum and
        // hide the dock badge for every other service.
        manager.updateBadge(for: negative, count: -5, isMuted: false, showBadge: true)
        manager.updateBadge(for: huge, count: 100_000, isMuted: false, showBadge: true)
        manager.updateBadge(for: ok, count: 3, isMuted: false, showBadge: true)

        XCTAssertEqual(manager.rawCount(for: negative), 0, "negative clamps to 0")
        XCTAssertEqual(manager.rawCount(for: huge), 999, "huge clamps to 999")
        // The total is the clamped sum, never dragged below the other services.
        XCTAssertEqual(manager.totalCount, 0 + 999 + 3)
    }

    @MainActor
    func testDoNotDisturbSnapshotMirrorsValue() {
        let manager = BadgeManager()
        XCTAssertFalse(manager.doNotDisturbSnapshot.value)
        manager.doNotDisturb = true
        XCTAssertTrue(manager.doNotDisturbSnapshot.value, "snapshot follows the property for off-main reads")
        manager.doNotDisturb = false
        XCTAssertFalse(manager.doNotDisturbSnapshot.value)
    }

    @MainActor
    func testRemoveBadgeClearsMaskState() {
        let manager = BadgeManager()
        let id = UUID()
        manager.updateBadge(for: id, count: 2, isMuted: true, showBadge: true)
        manager.removeBadge(for: id)
        // Re-adding an un-muted badge after removal must not stay masked.
        manager.updateBadge(for: id, count: 6, isMuted: false, showBadge: true)
        XCTAssertEqual(manager.badgeCount(for: id), 6)
    }

}
