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
}
