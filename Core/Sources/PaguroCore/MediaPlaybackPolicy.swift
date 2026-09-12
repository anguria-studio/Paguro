/// Mute and background suspension are independent reasons to block playback.
public enum MediaPlaybackPolicy {
    public static func shouldSuspend(isMuted: Bool, isSoftHibernated: Bool) -> Bool {
        isMuted || isSoftHibernated
    }
}
