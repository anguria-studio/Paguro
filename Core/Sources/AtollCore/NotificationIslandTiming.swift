import Foundation

/// Stable display times for the notification island.
public struct NotificationIslandTiming: Equatable, Sendable {
    public static let standard = NotificationIslandTiming(
        alertDuration: .seconds(4),
        voiceOverAlertDuration: .seconds(12),
        dismissalDuration: .milliseconds(180)
    )

    public let alertDuration: Duration
    public let voiceOverAlertDuration: Duration
    public let dismissalDuration: Duration

    public init(
        alertDuration: Duration,
        voiceOverAlertDuration: Duration,
        dismissalDuration: Duration
    ) {
        let safeAlertDuration = Self.nonnegative(alertDuration)
        self.alertDuration = safeAlertDuration
        self.voiceOverAlertDuration = max(
            safeAlertDuration,
            Self.nonnegative(voiceOverAlertDuration)
        )
        self.dismissalDuration = Self.nonnegative(dismissalDuration)
    }

    public func alertDuration(isVoiceOverEnabled: Bool) -> Duration {
        isVoiceOverEnabled ? voiceOverAlertDuration : alertDuration
    }

    private static func nonnegative(_ duration: Duration) -> Duration {
        duration < .zero ? .zero : duration
    }
}
