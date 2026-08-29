import XCTest
@testable import BlattaCore

final class WorkspaceNavigationPolicyTests: XCTestCase {
    func testWorkspaceViewModeUsesAllAsTheReviewedFallback() {
        XCTAssertEqual(WorkspaceViewMode.defaultMode, .all)
        XCTAssertEqual(WorkspaceViewMode.resolving(nil), .all)
        XCTAssertEqual(WorkspaceViewMode.resolving("current"), .current)
        XCTAssertEqual(WorkspaceViewMode.resolving("all"), .all)
        XCTAssertEqual(WorkspaceViewMode.resolving("unknown"), .all)
    }

    func testAggregateBadgeAppearsOnlyWhenServiceRowsAreHidden() {
        XCTAssertFalse(
            WorkspaceNavigationPolicy.showsAggregateBadge(serviceRowsVisible: true)
        )
        XCTAssertTrue(
            WorkspaceNavigationPolicy.showsAggregateBadge(serviceRowsVisible: false)
        )
    }

    func testDragReorderStaysInsideOneWorkspace() {
        XCTAssertTrue(
            WorkspaceNavigationPolicy.allowsReorder(
                sourceWorkspaceID: "work",
                targetWorkspaceID: "work"
            )
        )
        XCTAssertFalse(
            WorkspaceNavigationPolicy.allowsReorder(
                sourceWorkspaceID: "personal",
                targetWorkspaceID: "work"
            )
        )
    }
}
