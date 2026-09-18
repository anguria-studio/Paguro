/// Mute and background suspension are independent reasons to block playback.
public enum MediaPlaybackPolicy {
    /// Whether a service must suspend its media playback.
    ///
    /// A page that holds the camera or the microphone is in a call. Background
    /// suspension must not silence the far end while that call runs, so capture
    /// cancels the background reason. A service that was playing audible media
    /// when it left the screen holds the same kind of exemption, so music and a
    /// voice message survive a switch to another service. An explicit mute
    /// still wins over both, because the user asked for silence.
    public static func shouldSuspend(
        isMuted: Bool,
        isSoftHibernated: Bool,
        isCapturingMedia: Bool = false,
        isPlayingUserAudio: Bool = false
    ) -> Bool {
        if isMuted { return true }
        return isSoftHibernated && !isCapturingMedia && !isPlayingUserAudio
    }
}
