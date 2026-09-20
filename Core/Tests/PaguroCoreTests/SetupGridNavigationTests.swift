import XCTest
@testable import PaguroCore

final class SetupGridNavigationTests: XCTestCase {
    func testArrowMovementUsesVisibleColumns() {
        let grid = SetupGridNavigation(sections: [["a", "b", "c", "d", "e", "f"]], columns: 3)
        XCTAssertEqual(grid.destination(from: "b", direction: .right), "c")
        XCTAssertEqual(grid.destination(from: "b", direction: .left), "a")
        XCTAssertEqual(grid.destination(from: "b", direction: .down), "e")
        XCTAssertEqual(grid.destination(from: "e", direction: .up), "b")
    }

    func testEdgesDoNotWrapToAnotherRow() {
        let grid = SetupGridNavigation(sections: [["a", "b", "c", "d"]], columns: 2)
        XCTAssertEqual(grid.destination(from: "a", direction: .left), "a")
        XCTAssertEqual(grid.destination(from: "b", direction: .right), "b")
        XCTAssertEqual(grid.destination(from: "a", direction: .up), "a")
        XCTAssertEqual(grid.destination(from: "d", direction: .down), "d")
    }

    func testShortLastRowUsesItsLastCard() {
        let grid = SetupGridNavigation(sections: [["a", "b", "c", "d"]], columns: 3)
        XCTAssertEqual(grid.destination(from: "c", direction: .down), "d")
    }

    func testCustomAndCatalogStartSeparateRows() {
        let grid = SetupGridNavigation(sections: [["custom"], ["a", "b", "c"]], columns: 2)
        XCTAssertEqual(grid.rows, [["custom"], ["a", "b"], ["c"]])
        XCTAssertEqual(grid.destination(from: "custom", direction: .down), "a")
        XCTAssertEqual(grid.destination(from: "b", direction: .up), "custom")
    }

    func testFiltersRetainVisibleFocusOrChooseFirstResult() {
        let grid = SetupGridNavigation(sections: [[], ["b", "c"]], columns: 2)
        XCTAssertEqual(grid.retainedID("c"), "c")
        XCTAssertEqual(grid.retainedID("removed"), "b")
        XCTAssertEqual(grid.destination(from: "removed", direction: .down), "b")
    }

    func testEmptyResultsHaveNoFocusTarget() {
        let grid = SetupGridNavigation(sections: [[], []], columns: 4)
        XCTAssertNil(grid.firstID)
        XCTAssertNil(grid.retainedID("removed"))
        XCTAssertNil(grid.destination(from: nil, direction: .down))
    }

    func testResizingChangesVerticalMovement() {
        let ids = ["a", "b", "c", "d", "e", "f"]
        XCTAssertEqual(SetupGridNavigation(sections: [ids], columns: 3).destination(from: "b", direction: .down), "e")
        XCTAssertEqual(SetupGridNavigation(sections: [ids], columns: 2).destination(from: "b", direction: .down), "d")
    }

    func testInvalidColumnCountStillMakesProgress() {
        XCTAssertEqual(SetupGridNavigation(sections: [["a", "b"]], columns: 0).rows, [["a"], ["b"]])
    }
}
