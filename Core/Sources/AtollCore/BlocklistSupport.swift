import CryptoKit
import Foundation

/// Pure helpers for hashing and splitting content-blocker rules.
public enum BlocklistSupport {
    /// WebKit's maximum number of rules in one content-rule list.
    public static let maxRulesPerList = 150_000

    /// Returns a stable, content-addressed identifier for rule-list JSON.
    public static func identifier(prefix: String, forJSON json: String) -> String {
        let digest = SHA256.hash(data: Data(json.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(prefix)-\(hex.prefix(16))"
    }

    /// Returns the number of rules in a top-level JSON array.
    /// A valid JSON value with another shape returns zero.
    public static func ruleCount(inJSON json: String) throws -> Int {
        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        return (parsed as? [Any])?.count ?? 0
    }

    /// Returns whether a rule set exceeds the list capacity.
    public static func needsChunking(count: Int, cap: Int = maxRulesPerList) -> Bool {
        count > cap
    }

    /// Splits a JSON rule array into lists that contain at most `cap` rules.
    public static func chunk(
        json: String,
        cap: Int = maxRulesPerList
    ) throws -> [String] {
        guard cap > 0 else { throw BlocklistError.invalidCap }

        let parsed = try JSONSerialization.jsonObject(with: Data(json.utf8))
        guard let rules = parsed as? [Any] else {
            throw BlocklistError.notAnArray
        }
        if rules.count <= cap { return [json] }

        var chunks: [String] = []
        var index = 0
        while index < rules.count {
            let slice = Array(rules[index..<min(index + cap, rules.count)])
            let data = try JSONSerialization.data(withJSONObject: slice)
            chunks.append(String(decoding: data, as: UTF8.self))
            index += cap
        }
        return chunks
    }

    public enum BlocklistError: Error, Equatable, Sendable {
        case invalidCap
        case notAnArray
    }
}
