import Foundation

/// Only the official listing URL can select an add-on. Download URLs come from its API.
public struct FirefoxAddonSource: Equatable, Sendable {
    public let slug: String

    public init(link: String) throws {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 2_048,
              let parts = URLComponents(string: trimmed),
              parts.scheme == "https", parts.host == "addons.mozilla.org",
              parts.user == nil, parts.password == nil,
              parts.port == nil || parts.port == 443,
              !parts.percentEncodedPath.contains("%") else {
            throw ValidationError.invalidLink
        }
        var path = parts.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard path.first == "" else { throw ValidationError.invalidLink }
        path.removeFirst()
        if path.last == "" { path.removeLast() }
        if path.count == 4 {
            let locale = path.removeFirst()
            guard (2...16).contains(locale.count),
                  locale.utf8.allSatisfy({ Self.isLetter($0) || $0 == 45 }) else {
                throw ValidationError.invalidLink
            }
        }
        guard path.count == 3, path[0] == "firefox", path[1] == "addon",
              Self.isValidSlug(path[2]) else { throw ValidationError.invalidLink }
        slug = path[2]
    }

    public var listingURL: URL {
        URL(string: "https://addons.mozilla.org/firefox/addon/\(slug)/")!
    }

    public var metadataURL: URL {
        URL(string: "https://addons.mozilla.org/api/v5/addons/addon/\(slug)/")!
    }

    public static func isTrustedDownloadURL(_ url: URL) -> Bool {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https"
            && ["addons.mozilla.org", "addons.cdn.mozilla.net"].contains(parts.host ?? "")
            && parts.user == nil && parts.password == nil
            && (parts.port == nil || parts.port == 443)
    }

    public static func isValidSlug(_ slug: String) -> Bool {
        (1...200).contains(slug.utf8.count)
            && slug != "." && slug != ".."
            && slug.utf8.allSatisfy { isLetter($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (65...90).contains(byte) || (97...122).contains(byte)
    }

    public enum ValidationError: Error, LocalizedError {
        case invalidLink
        public var errorDescription: String? {
            "Paste an extension link from addons.mozilla.org. This prototype supports Firefox Add-ons only."
        }
    }
}
