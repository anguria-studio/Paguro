import Foundation

/// The reason that stops one hibernation attempt.
///
/// Each sweep names its reason, so a log line and a test can state why a
/// service kept its web view.
public enum HibernationBlock: String, Sendable, CaseIterable {
    /// The service has no live web view to release.
    case notLoaded
    /// The user looks at the service now.
    case activeService
    /// Another sweep already decides about this service.
    case evictionInFlight
    /// The service has the "Keep Loaded" policy.
    case keepLoaded
    /// The service must stay live for real-time notifications.
    case notificationCritical
    /// A caller pinned the service.
    case pinned
    /// The page holds the camera or the microphone. A muted microphone counts,
    /// because a muted call is still a call.
    case mediaCapture
    /// The page reports a call in progress.
    case activeCall
    /// The service was playing audible media when it left the screen and keeps
    /// that audio.
    case playingAudio

    /// A short sentence for a log line.
    public var reason: String {
        switch self {
        case .notLoaded: "the service has no live web view"
        case .activeService: "the service is active"
        case .evictionInFlight: "another sweep decides about the service"
        case .keepLoaded: "the service policy keeps it loaded"
        case .notificationCritical: "the service must stay live for notifications"
        case .pinned: "the service is pinned"
        case .mediaCapture: "the camera or microphone is in use"
        case .activeCall: "a call is in progress"
        case .playingAudio: "the service keeps playing audio"
        }
    }
}

/// The facts that decide one hibernation attempt.
///
/// The web-view pool owns the WebKit state and the JavaScript call probe. It
/// collects the answers in this value, so every sweep reads one list and the
/// rule stays pure.
public struct HibernationFacts: Equatable, Sendable {
    public var isLoaded: Bool
    public var isActiveService: Bool
    public var isEvictionInFlight: Bool
    public var keepsLoaded: Bool
    public var isNotificationCritical: Bool
    public var isPinned: Bool
    /// The page holds the camera or the microphone, a muted microphone included.
    public var isCapturingMedia: Bool
    /// The call probe reported a call in progress.
    public var hasDetectedCall: Bool
    /// The service holds the background audio exemption, so a release would
    /// stop music or a voice message that the user started.
    public var isPlayingUserAudio: Bool

    public init(
        isLoaded: Bool = true,
        isActiveService: Bool = false,
        isEvictionInFlight: Bool = false,
        keepsLoaded: Bool = false,
        isNotificationCritical: Bool = false,
        isPinned: Bool = false,
        isCapturingMedia: Bool = false,
        hasDetectedCall: Bool = false,
        isPlayingUserAudio: Bool = false
    ) {
        self.isLoaded = isLoaded
        self.isActiveService = isActiveService
        self.isEvictionInFlight = isEvictionInFlight
        self.keepsLoaded = keepsLoaded
        self.isNotificationCritical = isNotificationCritical
        self.isPinned = isPinned
        self.isCapturingMedia = isCapturingMedia
        self.hasDetectedCall = hasDetectedCall
        self.isPlayingUserAudio = isPlayingUserAudio
    }
}

/// The deterministic part of the hibernation decision.
///
/// The idle sweep and the capacity sweep share this rule, so a service that one
/// sweep protects is never released by the other.
public enum HibernationGate {
    /// The first reason that stops hibernation, or `nil` when the pool can
    /// release the service.
    public static func block(_ facts: HibernationFacts) -> HibernationBlock? {
        if !facts.isLoaded { return .notLoaded }
        if facts.isActiveService { return .activeService }
        if facts.isEvictionInFlight { return .evictionInFlight }
        if facts.keepsLoaded { return .keepLoaded }
        if facts.isNotificationCritical { return .notificationCritical }
        if facts.isPinned { return .pinned }
        if facts.isCapturingMedia { return .mediaCapture }
        if facts.hasDetectedCall { return .activeCall }
        if facts.isPlayingUserAudio { return .playingAudio }
        return nil
    }

    /// True when no fact stops hibernation.
    public static func permits(_ facts: HibernationFacts) -> Bool {
        block(facts) == nil
    }
}
