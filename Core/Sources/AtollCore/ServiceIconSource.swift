import Foundation

/// Normalizes the website or image address used to discover a service icon.
public enum ServiceIconSource {
    /// Returns an HTTP(S) URL for icon discovery.
    ///
    /// A blank value uses the service address. A host without a scheme uses
    /// HTTPS, which keeps the small editor field convenient without accepting
    /// non-web schemes.
    public static func normalizedURL(
        from rawValue: String,
        fallbackURL: String
    ) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFallback = fallbackURL.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmedValue.isEmpty ? trimmedFallback : trimmedValue
        guard !candidate.isEmpty else { return nil }

        if !candidate.contains("://") {
            candidate = "https://\(candidate)"
        }

        guard var components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil
        else {
            return nil
        }

        components.scheme = scheme
        return components.url
    }
}
