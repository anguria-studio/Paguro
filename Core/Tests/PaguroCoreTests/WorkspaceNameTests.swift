import XCTest
@testable import PaguroCore

final class WorkspaceNameTests: XCTestCase {
    func testTrimsWhitespaceAndPreservesTheEnteredName() {
        XCTAssertEqual(WorkspaceName.normalized("  Work & projects 🪴\n"), "Work & projects 🪴")
    }

    func testBlankNameIsInvalid() {
        XCTAssertNil(WorkspaceName.normalized(""))
        XCTAssertNil(WorkspaceName.normalized(" \n\t "))
    }

    func testSelectionChangesKeepTheWorkspaceName() {
        var selection = ServiceSetupSelection()
        XCTAssertEqual(selection.workspaceName, "Personal")
        selection.workspaceName = "Work"
        selection.toggle(ServiceSetupDraft(label: "Notes", url: "https://notes.example"))
        XCTAssertEqual(selection.workspaceName, "Work")
    }
}
