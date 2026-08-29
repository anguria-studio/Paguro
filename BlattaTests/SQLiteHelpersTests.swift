import XCTest

final class SQLiteHelpersTests: XCTestCase {
    func testRunReturnsQueryRows() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "sqlite-query")

        try SQLiteHelpers.run(sandbox.storeURL, "CREATE TABLE sample (value TEXT);")
        try SQLiteHelpers.run(sandbox.storeURL, "INSERT INTO sample VALUES ('Blatta');")

        XCTAssertEqual(
            try SQLiteHelpers.run(sandbox.storeURL, "SELECT value FROM sample;"),
            "Blatta\n"
        )
    }

    func testRunThrowsForInvalidSQL() throws {
        let sandbox = try StoreSandbox(testCase: self, label: "sqlite-error")

        XCTAssertThrowsError(
            try SQLiteHelpers.run(sandbox.storeURL, "DELETE FROM missing_table;")
        )
    }
}
