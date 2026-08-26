/// Resolves whether navigation UI shows a muted state.
///
/// Manual global mute is presentation-only. It marks every workspace and
/// service without changing their stored mute values or unread counts.
public enum NotificationMutePresentation {
    public static func showsMutedState(
        scopeMuted: Bool,
        manualGlobalMute: Bool
    ) -> Bool {
        scopeMuted || manualGlobalMute
    }
}
