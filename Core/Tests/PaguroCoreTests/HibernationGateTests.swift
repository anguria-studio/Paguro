import Testing
@testable import PaguroCore

struct HibernationGateTests {
    @Test
    func allFalseFactsPermitHibernation() {
        #expect(HibernationGate.permits(HibernationFacts()))
        #expect(HibernationGate.block(HibernationFacts()) == nil)
    }

    @Test
    func eachFactStopsHibernation() {
        #expect(HibernationGate.block(HibernationFacts(isLoaded: false)) == .notLoaded)
        #expect(HibernationGate.block(HibernationFacts(isActiveService: true)) == .activeService)
        #expect(HibernationGate.block(HibernationFacts(isEvictionInFlight: true)) == .evictionInFlight)
        #expect(HibernationGate.block(HibernationFacts(keepsLoaded: true)) == .keepLoaded)
        #expect(
            HibernationGate.block(HibernationFacts(isNotificationCritical: true))
                == .notificationCritical
        )
        #expect(HibernationGate.block(HibernationFacts(isPinned: true)) == .pinned)
        #expect(HibernationGate.block(HibernationFacts(isCapturingMedia: true)) == .mediaCapture)
        #expect(HibernationGate.block(HibernationFacts(hasDetectedCall: true)) == .activeCall)
        #expect(
            HibernationGate.block(HibernationFacts(isPlayingUserAudio: true))
                == .playingAudio
        )
    }

    /// The exit condition of the audio exemption: a service that keeps playing
    /// music or a voice message survives the idle sweep and the capacity sweep,
    /// because both read this one rule.
    @Test
    func backgroundAudioStopsHibernationOnItsOwn() {
        #expect(!HibernationGate.permits(HibernationFacts(isPlayingUserAudio: true)))
        #expect(!HibernationGate.permits(HibernationFacts(
            isCapturingMedia: true,
            isPlayingUserAudio: true
        )))
        #expect(!HibernationGate.permits(HibernationFacts(
            hasDetectedCall: true,
            isPlayingUserAudio: true
        )))
    }

    /// Audio is the last reason in the list, so a call or capture on the same
    /// service is still the reported reason.
    @Test
    func anEarlierReasonWinsOverBackgroundAudio() {
        #expect(HibernationGate.block(HibernationFacts(
            isCapturingMedia: true,
            isPlayingUserAudio: true
        )) == .mediaCapture)
        #expect(HibernationGate.block(HibernationFacts(
            hasDetectedCall: true,
            isPlayingUserAudio: true
        )) == .activeCall)
        #expect(HibernationGate.block(HibernationFacts(
            isActiveService: true,
            isPlayingUserAudio: true
        )) == .activeService)
    }

    /// The exit condition of the call protection: capture and a detected call
    /// each stop hibernation on their own, and no other fact can overrule them.
    @Test
    func captureAndCallStopHibernationOnTheirOwn() {
        let capturing = HibernationFacts(isCapturingMedia: true)
        let calling = HibernationFacts(hasDetectedCall: true)
        #expect(!HibernationGate.permits(capturing))
        #expect(!HibernationGate.permits(calling))
        #expect(!HibernationGate.permits(HibernationFacts(
            isCapturingMedia: true,
            hasDetectedCall: true
        )))
    }

    @Test
    func theFirstReasonWins() {
        let facts = HibernationFacts(
            isLoaded: false,
            isActiveService: true,
            isCapturingMedia: true,
            hasDetectedCall: true,
            isPlayingUserAudio: true
        )
        #expect(HibernationGate.block(facts) == .notLoaded)
    }

    @Test
    func everyReasonHasASentence() {
        for block in HibernationBlock.allCases {
            #expect(!block.reason.isEmpty)
        }
    }
}
