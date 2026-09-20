import Foundation

/// Keyboard movement follows visible grid rows, including separate custom and catalog sections.
public struct SetupGridNavigation: Equatable, Sendable {
    public enum Direction: Sendable { case left, right, up, down }
    public let rows: [[String]]

    public init(sections: [[String]], columns: Int) {
        let width = max(1, columns)
        rows = sections.flatMap { section in
            stride(from: 0, to: section.count, by: width).map {
                Array(section[$0..<min($0 + width, section.count)])
            }
        }
    }

    public var firstID: String? { rows.first?.first }

    public func retainedID(_ id: String?) -> String? {
        guard let id, rows.contains(where: { $0.contains(id) }) else { return firstID }
        return id
    }

    public func destination(from id: String?, direction: Direction) -> String? {
        guard let id, let row = rows.firstIndex(where: { $0.contains(id) }),
              let column = rows[row].firstIndex(of: id) else { return firstID }
        switch direction {
        case .left:
            return column > 0 ? rows[row][column - 1] : id
        case .right:
            return column + 1 < rows[row].count ? rows[row][column + 1] : id
        case .up, .down:
            let nextRow = row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(nextRow) else { return id }
            return rows[nextRow][min(column, rows[nextRow].count - 1)]
        }
    }
}
