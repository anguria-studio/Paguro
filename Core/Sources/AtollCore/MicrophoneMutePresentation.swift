/// Builds clear labels for the one-shot active-microphone mute action.
public enum MicrophoneMutePresentation {
    public static func menuTitle(activeCount: Int) -> String {
        switch max(0, activeCount) {
        case 1:
            return "Mute Active Microphone"
        case 2...:
            return "Mute \(activeCount) Active Microphones"
        default:
            return "Mute Active Microphones"
        }
    }

    public static func confirmation(mutedCount: Int) -> String? {
        switch max(0, mutedCount) {
        case 1:
            return "Muted 1 microphone."
        case 2...:
            return "Muted \(mutedCount) microphones."
        default:
            return nil
        }
    }
}
