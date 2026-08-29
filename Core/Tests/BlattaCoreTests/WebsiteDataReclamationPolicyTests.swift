import Foundation
import XCTest
@testable import BlattaCore

final class WebsiteDataReclamationPolicyTests: XCTestCase {
    func testReconcileDropsAClaimedTombstone() {
        let live = UUID()
        let deleted = UUID()

        let result = WebsiteDataReclamationPolicy.reconcile(
            tombstoned: [live, deleted],
            claimed: [live, UUID()]
        )

        XCTAssertEqual(result.dropped, [live])
        XCTAssertEqual(result.keep, [deleted])
    }

    func testUnreferencedFailsClosedWhenClaimsAreUnknown() {
        let onDisk: Set<UUID> = [UUID(), UUID(), UUID()]

        XCTAssertEqual(
            WebsiteDataReclamationPolicy.unreferenced(onDisk: onDisk, claimed: []),
            []
        )
    }

    func testUnreferencedExcludesEveryClaimedIdentifier() {
        let claimedA = UUID()
        let claimedB = UUID()
        let stranded = UUID()

        XCTAssertEqual(
            WebsiteDataReclamationPolicy.unreferenced(
                onDisk: [claimedA, claimedB, stranded],
                claimed: [claimedA, claimedB]
            ),
            [stranded]
        )
    }
}
