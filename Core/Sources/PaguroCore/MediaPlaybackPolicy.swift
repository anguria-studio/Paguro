/// Mute and background suspension are independent reasons to block playback.
public enum MediaPlaybackPolicy {
    /// Whether a service must suspend its media playback.
    ///
    /// A page that holds the camera or the microphone is in a call. Background
    /// suspension must not silence the far end while that call runs, so capture
    /// cancels the background reason. An explicit mute still wins, because the
    /// user asked for silence.
    public static func shouldSuspend(
        isMuted: Bool,
        isSoftHibernated: Bool,
        isCapturingMedia: Bool = false
    ) -> Bool {
        if isMuted { return true }
        return isSoftHibernated && !isCapturingMedia
    }
}
