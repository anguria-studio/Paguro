/// Pure rules for the badge on the Dock icon.
///
/// The badge label is a deterministic function of the visible unread total and
/// the user preference, so it stays free of AppKit and the app applies the
/// result to the Dock tile.
public enum DockBadgePolicy {
    /// Returns the label for the Dock tile, or nil when the Dock icon must show
    /// no badge.
    ///
    /// The preference removes the badge. A total of zero has nothing to show.
    /// A negative total cannot occur, because the badge manager clamps each
    /// count, but it must never make a label.
    public static func badgeLabel(unreadTotal: Int, showsBadgeCount: Bool, allServicesMuted: Bool = false) -> String? {
        guard !allServicesMuted, showsBadgeCount, unreadTotal > 0 else { return nil }
        return String(unreadTotal)
    }
}
