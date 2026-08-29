/// One web origin used by the notification bridge.
public struct NotificationOrigin: Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int?

    public init(scheme: String, host: String, port: Int?) {
        self.scheme = scheme
        self.host = host
        self.port = port
    }
}

/// Pure origin checks for notification messages from web frames.
public enum NotificationOriginPolicy {
    /// Returns whether a frame can send a notification for the main document.
    /// Main-frame messages are trusted by their owning web view. A subframe
    /// must have the same HTTP or HTTPS scheme, host, and effective port.
    public static func accepts(
        isMainFrame: Bool,
        mainOrigin: NotificationOrigin?,
        frameOrigin: NotificationOrigin?
    ) -> Bool {
        if isMainFrame { return true }
        guard let main = normalized(mainOrigin),
              let frame = normalized(frameOrigin) else {
            return false
        }
        return main == frame
    }

    private static func normalized(
        _ origin: NotificationOrigin?
    ) -> (scheme: String, host: String, port: Int)? {
        guard let origin else { return nil }
        let scheme = origin.scheme.lowercased()
        let host = origin.host.lowercased()
        guard !host.isEmpty else { return nil }

        let defaultPort: Int
        switch scheme {
        case "http": defaultPort = 80
        case "https": defaultPort = 443
        default: return nil
        }

        let port = origin.port ?? defaultPort
        guard (0...65_535).contains(port) else { return nil }
        return (scheme, host, port == 0 ? defaultPort : port)
    }
}
