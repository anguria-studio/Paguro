import XCTest
import Foundation
@testable import Blatta

final class SessionRuntimeTests: XCTestCase {
    // MARK: - Keeping chat services live outside the active space

    /// A chat service the active-space preload doesn't cover must still be kept
    /// live — it is the only way it can post a notification banner. A non-chat
    /// service must not be, and one already covered must not be preloaded twice.
    @MainActor
    func testChatServicesOutsideTheActiveSpaceAreKeptLive() {
        let slack = ModelFixtures.service(label: "Slack", catalogID: "slack")
        let coveredSlack = ModelFixtures.service(label: "Slack (this space)", catalogID: "slack")
        let reddit = ModelFixtures.service(label: "Reddit", catalogID: "reddit")
        let custom = ModelFixtures.service(label: "Custom chat", catalogID: nil)

        let chosen = AppState.criticalServicesToKeepLive(
            among: [slack, coveredSlack, reddit, custom],
            covered: [coveredSlack.id],
            limit: 5
        )
        XCTAssertEqual(chosen.map(\.id), [slack.id], "only the uncovered chat service is kept live")
    }

    /// The cap exists because these are exempt from eviction: without it a user
    /// with many chat services would pin every slot in the pool. It must also
    /// pick the SAME ones each launch, or a different set would be kept live
    /// every time the app started.
    @MainActor
    func testKeepLiveSelectionIsCappedAndStable() {
        let services = (0..<12).map { ModelFixtures.service(label: "Slack \($0)", catalogID: "slack") }

        let first = AppState.criticalServicesToKeepLive(among: services, covered: [], limit: 5)
        XCTAssertEqual(first.count, 5, "the cap must bound how many are kept live")
        XCTAssertLessThan(
            AppState.maxCrossSpaceCriticalServices, 15,
            "the cap must stay below the pool's maxLoaded or the LRU sweep has nothing to reclaim"
        )

        let shuffled = AppState.criticalServicesToKeepLive(among: services.shuffled(), covered: [], limit: 5)
        XCTAssertEqual(first.map(\.id), shuffled.map(\.id), "the same services must win the cap regardless of fetch order")
    }

    /// The signal that gates both destructive reclaim paths. It has to be read
    /// from the raw file before the open path repairs the damage away.
    @MainActor
    func testHasDanglingLinksSeesDamageAndClearsAfterRepair() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "damaged")
        let storeURL = sandbox.storeURL

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        XCTAssertFalse(StoreRepair.hasDanglingLinks(at: storeURL), "a healthy store is not damaged")

        // A link pointing at a space that isn't there — what a lost Space row
        // leaves behind.
        _ = try SQLiteHelpers.run(storeURL, """
            INSERT INTO ZSPACESERVICELINK (Z_PK, Z_ENT, Z_OPT, ZSPACE, ZSERVICE, ZSORTORDER)
            VALUES (9001, 3, 1, 8888, 9999, 0);
            """)
        XCTAssertTrue(StoreRepair.hasDanglingLinks(at: storeURL), "a dangling link must be reported as damage")

        StoreRepair.repairDanglingLinks(at: storeURL)
        XCTAssertFalse(StoreRepair.hasDanglingLinks(at: storeURL), "and must read clean once repaired")
    }
}
