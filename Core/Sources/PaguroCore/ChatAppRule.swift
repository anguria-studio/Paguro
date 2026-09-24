/// Pure rule that decides whether a service is a chat app.
///
/// A chat app (notification-critical service) stays live so that its
/// messages arrive at once. It never auto-hibernates, launch preload also
/// loads it from other workspaces, and the transient badge fetch skips it.
///
/// The user can set the value for each service. When the service has no
/// value, its catalog category decides. A custom website has no category, so
/// it is not a chat app until the user turns the setting on.
public enum ChatAppRule {
    /// Catalog categories that are chat apps when the service has no value.
    public static let catalogCategories: Set<String> = ["Messaging"]

    public static func isChatApp(override: Bool?, catalogCategory: String?) -> Bool {
        if let override { return override }
        guard let catalogCategory else { return false }
        return catalogCategories.contains(catalogCategory)
    }
}
