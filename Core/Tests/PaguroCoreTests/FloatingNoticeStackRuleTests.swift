import XCTest
@testable import PaguroCore

final class FloatingNoticeStackRuleTests: XCTestCase {
    func testAShortStackShowsEveryNotice() {
        let ids = ["offline", "offer"]

        XCTAssertEqual(
            FloatingNoticeStackRule.visible(newestFirst: ids, staysUntilActed: []),
            ids
        )
    }

    /// Three cards is the limit, and they keep the order they arrived in.
    func testTheStackShowsThreeCards() {
        let ids = ["d", "c", "b", "a"]

        XCTAssertEqual(
            FloatingNoticeStackRule.visible(newestFirst: ids, staysUntilActed: []),
            ["d", "c", "b"]
        )
        XCTAssertEqual(FloatingNoticeStackRule.visibleLimit, 3)
    }

    /// The oldest notice that leaves on its own gives up its place first, so the
    /// user always reaches the buttons of a notice that waits for an answer.
    func testANoticeThatWaitsForTheUserKeepsItsPlace() {
        let ids = ["mic", "capacity", "passkey", "offer"]

        let visible = FloatingNoticeStackRule.visible(
            newestFirst: ids,
            staysUntilActed: ["offer"]
        )

        XCTAssertEqual(visible, ["mic", "capacity", "offer"])
    }

    /// Two waiting notices and one that leaves on its own fill the stack. The
    /// newest transient notice takes the one free place.
    func testTheNewestTransientNoticeTakesTheFreePlace() {
        let ids = ["mic", "capacity", "offline", "offer"]

        let visible = FloatingNoticeStackRule.visible(
            newestFirst: ids,
            staysUntilActed: ["offline", "offer"]
        )

        XCTAssertEqual(visible, ["mic", "offline", "offer"])
    }

    /// Only another waiting notice can hold a waiting notice back, and the newest
    /// ones win.
    func testMoreWaitingNoticesThanPlacesKeepTheNewestOnes() {
        let ids = ["d", "c", "b", "a"]

        let visible = FloatingNoticeStackRule.visible(
            newestFirst: ids,
            staysUntilActed: ["a", "b", "c", "d"]
        )

        XCTAssertEqual(visible, ["d", "c", "b"])
    }

    func testAStackWithoutPlacesShowsNothing() {
        XCTAssertTrue(
            FloatingNoticeStackRule.visible(
                newestFirst: ["a", "b"],
                staysUntilActed: ["a"],
                limit: 0
            ).isEmpty
        )
    }
}
