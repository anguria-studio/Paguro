import Testing
@testable import PaguroCore

struct MediaPlaybackPolicyTests {
    @Test(arguments: [false, true], [false, true])
    func suspensionKeepsEveryActiveReason(muted: Bool, background: Bool) {
        let suspended = MediaPlaybackPolicy.shouldSuspend(
            isMuted: muted, isSoftHibernated: background
        )
        if !muted && !background {
            #expect(!suspended)
        } else {
            #expect(suspended)
        }
    }

    /// A background service in a call must keep its playback, or the user stops
    /// hearing the far end after a switch to another service.
    @Test(arguments: [false, true], [false, true])
    func captureCancelsTheBackgroundReasonOnly(muted: Bool, background: Bool) {
        let suspended = MediaPlaybackPolicy.shouldSuspend(
            isMuted: muted, isSoftHibernated: background, isCapturingMedia: true
        )
        #expect(suspended == muted)
    }

    /// A service that was playing when it left the screen keeps its audio, so a
    /// switch to another service does not stop music or a voice message. The
    /// exemption cancels the background reason only.
    @Test(arguments: [false, true], [false, true])
    func userAudioCancelsTheBackgroundReasonOnly(muted: Bool, background: Bool) {
        let suspended = MediaPlaybackPolicy.shouldSuspend(
            isMuted: muted, isSoftHibernated: background, isPlayingUserAudio: true
        )
        #expect(suspended == muted)
    }

    /// A call and background audio on the same service is one page that plays
    /// and captures. Either reason alone keeps the playback, and mute still
    /// silences both.
    @Test(arguments: [false, true])
    func captureAndUserAudioTogetherStillLoseToMute(muted: Bool) {
        let suspended = MediaPlaybackPolicy.shouldSuspend(
            isMuted: muted,
            isSoftHibernated: true,
            isCapturingMedia: true,
            isPlayingUserAudio: true
        )
        #expect(suspended == muted)
    }

    /// The exemption changes nothing for a service on the screen.
    @Test
    func theForegroundServiceIsNeverSuspendedByTheExemption() {
        #expect(!MediaPlaybackPolicy.shouldSuspend(
            isMuted: false, isSoftHibernated: false, isPlayingUserAudio: false
        ))
        #expect(!MediaPlaybackPolicy.shouldSuspend(
            isMuted: false, isSoftHibernated: false, isPlayingUserAudio: true
        ))
    }

    /// The defaulted argument keeps every existing caller on the old answer.
    @Test(arguments: [false, true], [false, true])
    func theDefaultLeavesTheBackgroundRuleUnchanged(muted: Bool, background: Bool) {
        #expect(
            MediaPlaybackPolicy.shouldSuspend(
                isMuted: muted, isSoftHibernated: background
            ) == MediaPlaybackPolicy.shouldSuspend(
                isMuted: muted, isSoftHibernated: background, isPlayingUserAudio: false
            )
        )
    }
}
