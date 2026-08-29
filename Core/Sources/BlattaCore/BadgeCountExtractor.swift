import Foundation

/// One reading of an unread count, with a short text that is safe for a log.
///
/// `count` is `nil` when the source gave no information. A `nil` count must
/// never clear a badge. A count of zero is an authoritative empty state.
public struct BadgeReading: Equatable, Sendable {
    /// The unread count, or `nil` when the source gave no count.
    public let count: Int?
    /// A short redacted text for a log line. It holds digits and a shape only.
    public let raw: String

    public init(count: Int?, raw: String) {
        self.count = count
        self.raw = raw
    }
}

/// Pure rules that read an unread count from a page title or from the value a
/// badge expression returned.
///
/// The rules stay here so a test can run them against realistic titles and
/// realistic JavaScript values without a web view.
public enum BadgeCountExtractor {
    /// The largest count that a page title can report. A larger number in a
    /// title is a year, a price, or an identifier, not an unread count.
    static let maximumTitleCount = 999

    /// Returns a parenthesized count from the first section of a page title.
    /// Invalid, zero, and implausibly large counts return zero.
    public static func extractBadgeCount(from title: String) -> Int {
        readTitle(title).count ?? 0
    }

    /// Reads the unread count that a page title reports.
    ///
    /// Gmail, WhatsApp Web, Discord, Slack, and Telegram all put the count in
    /// parentheses in the first section of the title. The rule cuts the title
    /// at the first separator, so a count that belongs to a workspace name or
    /// to an account name cannot reach the badge.
    ///
    /// The count is zero when the title holds no parenthesized number. A title
    /// is a reliable source, so an absent number means an empty state.
    public static func readTitle(_ title: String) -> BadgeReading {
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
              (1...maximumTitleCount).contains(count) else {
            return BadgeReading(count: 0, raw: "none/len=\(title.count)")
        }
        return BadgeReading(count: count, raw: "(\(count))")
    }

    /// Reads the unread count from the value a badge expression returned.
    ///
    /// WebKit returns a JavaScript number as `NSNumber`, a JavaScript string as
    /// `NSString`, and JavaScript `null` as `NSNull`. A badge expression that
    /// cannot read its page returns `null`, which this rule reports as "no
    /// count" so the current badge stays.
    ///
    /// A string value comes from element text, so it can hold a group
    /// separator or a "more than" marker. `"1,234"` reads as 1234 and `"9+"`
    /// reads as 9. Empty text means an empty badge, so it reads as zero.
    public static func readJSResult(_ value: Any?) -> BadgeReading {
        guard let value else {
            return BadgeReading(count: nil, raw: "nil")
        }
        if value is NSNull {
            return BadgeReading(count: nil, raw: "null")
        }
        if let number = value as? NSNumber {
            // A JavaScript boolean also bridges to NSNumber. It reports
            // presence, not a count, so it gives no count.
            if CFGetTypeID(number as CFTypeRef) == CFBooleanGetTypeID() {
                return BadgeReading(count: nil, raw: "bool(\(number.boolValue))")
            }
            let double = number.doubleValue
            guard double.isFinite else {
                return BadgeReading(count: nil, raw: "number(nonfinite)")
            }
            let count = max(0, Int(double.rounded(.towardZero)))
            return BadgeReading(count: count, raw: "number(\(count))")
        }
        if let text = value as? String {
            return readBadgeText(text)
        }
        return BadgeReading(count: nil, raw: "other(\(type(of: value)))")
    }

    /// Reads a count from the text of a badge element.
    static func readBadgeText(_ text: String) -> BadgeReading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shape = trimmed.count <= 16 ? "string(\(trimmed))" : "string(len=\(trimmed.count))"
        if trimmed.isEmpty {
            return BadgeReading(count: 0, raw: "string(empty)")
        }
        let digits = trimmed.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: " ", with: "")
        guard let match = digits.firstMatch(of: /(\d+)/), let count = Int(match.1) else {
            return BadgeReading(count: nil, raw: shape)
        }
        return BadgeReading(count: max(0, count), raw: shape)
    }
}
