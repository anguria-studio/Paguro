import XCTest
@testable import BlattaCore

final class MenuBarPresentationTests: XCTestCase {
    func testUnreadSummaryUsesReadableSingularAndPluralText() {
        XCTAssertEqual(
            MenuBarPresentation.unreadSummary(0),
            "No unread notifications"
        )
        XCTAssertEqual(
            MenuBarPresentation.unreadSummary(1),
            "1 unread notification"
        )
        XCTAssertEqual(
            MenuBarPresentation.unreadSummary(12),
            "12 unread notifications"
        )
    }

    func testUnreadSummaryClampsAnInvalidNegativeCount() {
        XCTAssertEqual(
            MenuBarPresentation.unreadSummary(-1),
            "No unread notifications"
        )
    }

    func testServiceLabelAddsWorkspaceAndSelectionState() {
        XCTAssertEqual(
            MenuBarPresentation.serviceAccessibilityLabel(
                serviceStateLabel: "Mail, 3 unread, muted",
                workspaceName: "Work",
                isSelected: true
            ),
            "Mail, 3 unread, muted, workspace Work, selected"
        )
    }
}
