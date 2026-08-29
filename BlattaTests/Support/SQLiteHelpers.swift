import Foundation
import SQLite3

enum SQLiteHelpers {
    struct SQLiteError: Error, CustomStringConvertible {
        let operation: String
        let code: Int32
        let message: String

        var description: String {
            "SQLite \(operation) failed with code \(code): \(message)"
        }
    }

    /// Runs one SQL statement and returns rows in the sqlite3 CLI text format.
    @discardableResult
    static func run(_ url: URL, _ sql: String) throws -> String {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let database else {
            let message = database.map { String(cString: sqlite3_errmsg($0)) }
                ?? "No database handle"
            if let database {
                sqlite3_close(database)
            }
            throw SQLiteError(operation: "open", code: openResult, message: message)
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 1_000)

        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(database, sql, -1, &statement, nil)
        guard prepareResult == SQLITE_OK else {
            throw SQLiteError(
                operation: "prepare",
                code: prepareResult,
                message: String(cString: sqlite3_errmsg(database))
            )
        }
        guard let statement else { return "" }
        defer { sqlite3_finalize(statement) }

        var rows: [String] = []
        while true {
            let stepResult = sqlite3_step(statement)
            switch stepResult {
            case SQLITE_ROW:
                let columns = (0..<sqlite3_column_count(statement)).map { index in
                    guard let text = sqlite3_column_text(statement, index) else { return "" }
                    return String(cString: text)
                }
                rows.append(columns.joined(separator: "|"))
            case SQLITE_DONE:
                return rows.isEmpty ? "" : rows.joined(separator: "\n") + "\n"
            default:
                throw SQLiteError(
                    operation: "step",
                    code: stepResult,
                    message: String(cString: sqlite3_errmsg(database))
                )
            }
        }
    }
}
