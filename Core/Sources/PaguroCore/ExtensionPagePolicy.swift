import Foundation

/// URL rules for the visible windows that show extension-created pages.
public enum ExtensionPagePolicy {
    public static let maximumOpenPages = 4
    static let maximumURLBytes = 16_384

    /// The main frame shows a visible address, so it accepts only web pages,
    /// the requesting extension's own files, and a blank page.
    public static func allows(_ url: URL, extensionBaseURL: URL) -> Bool {
        guard let parts = components(of: url) else { return false }
        switch parts.scheme?.lowercased() {
        case "https", "http": return parts.host?.isEmpty == false
        case "webkit-extension":
            return parts.host?.lowercased() == extensionBaseURL.host?.lowercased() && parts.port == nil
        case "about": return url.absoluteString == "about:blank"
        default: return false
        }
    }

    /// Frames inside a page can also use the local document schemes that
    /// options pages build with. Script and file URLs stay blocked.
    public static func allowsSubframe(_ url: URL, extensionBaseURL: URL) -> Bool {
        if allows(url, extensionBaseURL: extensionBaseURL) { return true }
        guard let parts = components(of: url) else { return false }
        switch parts.scheme?.lowercased() {
        case "blob", "data": return true
        case "about": return url.absoluteString == "about:srcdoc"
        default: return false
        }
    }

    private static func components(of url: URL) -> URLComponents? {
        guard url.absoluteString.utf8.count <= maximumURLBytes,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil else { return nil }
        return parts
    }
}
