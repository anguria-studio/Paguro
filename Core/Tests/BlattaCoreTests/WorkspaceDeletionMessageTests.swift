import XCTest
@testable import BlattaCore

final class WorkspaceDeletionMessageTests: XCTestCase {
    func testNoOrphanedServiceSaysNothingIsDeleted() {
        let text = WorkspaceDeletionMessage.text(orphanedServiceCount: 0)
        XCTAssertTrue(text.hasPrefix("No service will be deleted."))
    }

    func testOneOrphanedServiceUsesSingular() {
        let text = WorkspaceDeletionMessage.text(orphanedServiceCount: 1)
        XCTAssertTrue(text.hasPrefix("1 service exists only in this workspace."))
        XCTAssertTrue(text.contains("sign-in data"))
    }

    func testManyOrphanedServicesUsePluralAndCount() {
        let text = WorkspaceDeletionMessage.text(orphanedServiceCount: 3)
        XCTAssertTrue(text.hasPrefix("3 services exist only in this workspace."))
        XCTAssertTrue(text.contains("sign-in data"))
    }

    func testNegativeCountIsTreatedAsZero() {
        XCTAssertEqual(
            WorkspaceDeletionMessage.text(orphanedServiceCount: -2),
            WorkspaceDeletionMessage.text(orphanedServiceCount: 0)
        )
    }
}
