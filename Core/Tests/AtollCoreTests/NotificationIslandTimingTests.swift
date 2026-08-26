import AtollCore
import Testing

@Suite("Notification island timing")
struct NotificationIslandTimingTests {
    @Test("Standard timing gives VoiceOver more reading time")
    func standardTimingSupportsVoiceOver() {
        let timing = NotificationIslandTiming.standard

        #expect(timing.alertDuration(isVoiceOverEnabled: false) == .seconds(6))
        #expect(timing.alertDuration(isVoiceOverEnabled: true) == .seconds(12))
        #expect(timing.dismissalDuration == .milliseconds(180))
    }

    @Test("Negative durations become zero")
    func negativeDurationsBecomeZero() {
        let timing = NotificationIslandTiming(
            alertDuration: .seconds(-1),
            voiceOverAlertDuration: .seconds(-2),
            dismissalDuration: .milliseconds(-1)
        )

        #expect(timing.alertDuration == .zero)
        #expect(timing.voiceOverAlertDuration == .zero)
        #expect(timing.dismissalDuration == .zero)
    }

    @Test("VoiceOver duration cannot be shorter than the standard duration")
    func voiceOverDurationHasSafeMinimum() {
        let timing = NotificationIslandTiming(
            alertDuration: .seconds(8),
            voiceOverAlertDuration: .seconds(3),
            dismissalDuration: .milliseconds(100)
        )

        #expect(timing.voiceOverAlertDuration == .seconds(8))
    }
}
