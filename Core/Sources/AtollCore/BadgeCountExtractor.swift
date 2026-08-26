/// Pure rules for reading an unread count from a page title.
public enum BadgeCountExtractor {
    /// Returns a parenthesized count from the first section of a page title.
    /// Invalid, zero, and implausibly large counts return zero.
    public static func extractBadgeCount(from title: String) -> Int {
        let separators = [" - ", " | ", " — ", " : ", " · "]
        var head = title
        for separator in separators {
            if let range = head.range(of: separator) {
                head = String(head[..<range.lowerBound])
            }
        }

        let pattern = /\((\d+)\)/
        guard let match = head.firstMatch(of: pattern),
              let count = Int(match.1),
              (1...999).contains(count) else {
            return 0
        }
        return count
    }
}
