import XCTest
@testable import PaguroCore

final class AppDistributionTests: XCTestCase {
    func testDistributionFeatures() {
        for (distribution, updates, google) in [
            (AppDistribution.development, false, true),
            (.directDownload, true, true),
            (.appStore, false, false)
        ] {
            XCTAssertEqual(distribution.supportsSelfUpdates, updates)
            XCTAssertEqual(distribution.supportsGoogleIconFallback, google)
        }
    }
}
