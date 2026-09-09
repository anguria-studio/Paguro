import XCTest
@testable import PaguroCore

final class WorkspaceEmojiTests: XCTestCase {
    func testEmptyAndWhitespaceValuesMeanNoEmoji() {
        XCTAssertNil(WorkspaceEmoji.displayValue(""))
        XCTAssertNil(WorkspaceEmoji.displayValue("  \n"))
        XCTAssertEqual(WorkspaceEmoji.storedValue("  \n"), "")
    }

    func testEmojiIsTrimmedForDisplayAndStorage() {
        XCTAssertEqual(WorkspaceEmoji.displayValue("  🏝️  "), "🏝️")
        XCTAssertEqual(WorkspaceEmoji.storedValue("  🏝️  "), "🏝️")
    }

    func testLabelOmitsTheEmojiSeparatorWhenNoEmojiExists() {
        XCTAssertEqual(WorkspaceEmoji.label(name: "Work", emoji: ""), "Work")
        XCTAssertEqual(WorkspaceEmoji.label(name: "Work", emoji: "💼"), "💼 Work")
    }
}
