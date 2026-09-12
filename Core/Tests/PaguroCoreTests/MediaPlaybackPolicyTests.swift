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
}
