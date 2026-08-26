/// Pure rules for detecting a sign-in wall during a background badge fetch.
public enum AuthWallResolver {
    /// Returns true when a fetch moved to another host and produced no badge.
    /// Missing hosts are unknown and do not count as a sign-in wall.
    public static func looksLikeSignInWall(
        requestedHost: String?,
        landedHost: String?,
        badge: Int
    ) -> Bool {
        guard let requestedHost, let landedHost else { return false }
        return landedHost.lowercased() != requestedHost.lowercased() && badge == 0
    }
}
