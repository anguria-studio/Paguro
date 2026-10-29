import Foundation

/// Firefox dotted version ordering, with bounded ASCII input and checked numbers.
public enum FirefoxExtensionVersion {
    private struct Part {
        var number: Int32 = 0
        var label = ""
        var sequence: Int32 = 0
        var suffix = ""
    }

    public static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard let left = parse(lhs), let right = parse(rhs) else { return nil }
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : Part()
            let b = index < right.count ? right[index] : Part()
            if a.number != b.number { return a.number < b.number ? .orderedAscending : .orderedDescending }
            if let result = compareText(a.label, b.label) { return result }
            if a.sequence != b.sequence { return a.sequence < b.sequence ? .orderedAscending : .orderedDescending }
            if let result = compareText(a.suffix, b.suffix) { return result }
        }
        return .orderedSame
    }

    private static func compareText(_ lhs: String, _ rhs: String) -> ComparisonResult? {
        guard lhs != rhs else { return nil }
        if lhs.isEmpty { return .orderedDescending }
        if rhs.isEmpty { return .orderedAscending }
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8) ? .orderedAscending : .orderedDescending
    }

    private static func parse(_ version: String) -> [Part]? {
        guard (1...128).contains(version.utf8.count), version.utf8.allSatisfy({
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [42, 43, 45, 46, 95].contains($0)
        }) else { return nil }
        var parts: [Part] = []
        for segment in version.split(separator: ".", omittingEmptySubsequences: false) {
            if segment == "*" { parts.append(Part(number: .max)); continue }
            let bytes = Array(segment.utf8)
            var cursor = 0
            guard let first = number(bytes, cursor: &cursor) else { return nil }
            var part = Part(number: first)
            if cursor < bytes.count, bytes[cursor] == 43 {
                guard first < .max else { return nil }
                part.number += 1
                part.label = "pre"
            } else {
                let start = cursor
                while cursor < bytes.count, !((48...57).contains(bytes[cursor]) || bytes[cursor] == 43 || bytes[cursor] == 45) { cursor += 1 }
                part.label = String(decoding: bytes[start..<cursor], as: UTF8.self)
                guard let sequence = number(bytes, cursor: &cursor) else { return nil }
                part.sequence = sequence
                part.suffix = String(decoding: bytes[cursor...], as: UTF8.self)
            }
            parts.append(part)
        }
        return parts
    }

    private static func number(_ bytes: [UInt8], cursor: inout Int) -> Int32? {
        let start = cursor
        if cursor < bytes.count, bytes[cursor] == 43 || bytes[cursor] == 45 { cursor += 1 }
        let digits = cursor
        while cursor < bytes.count, (48...57).contains(bytes[cursor]) { cursor += 1 }
        guard cursor != digits else {
            cursor = start
            return start == digits ? 0 : nil
        }
        return Int32(String(decoding: bytes[start..<cursor], as: UTF8.self))
    }
}
