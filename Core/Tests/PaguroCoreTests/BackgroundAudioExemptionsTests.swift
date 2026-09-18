import Foundation
import Testing
@testable import PaguroCore

struct BackgroundAudioExemptionsTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test
    func aPlayingServiceEarnsTheExemptionAtTheSwitch() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()

        let granted = exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        #expect(granted)
        #expect(exemptions.isExempt(service))
        #expect(exemptions.exemptServiceIDs == [service])
        #expect(!exemptions.isEmpty)
    }

    @Test
    func aSilentServiceEarnsNothingAtTheSwitch() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()

        let granted = exemptions.grantIfPlaying(service, isPlaying: false, now: start)

        #expect(!granted)
        #expect(!exemptions.isExempt(service))
        #expect(exemptions.isEmpty)
    }

    /// A background page must not keep itself awake by autoplay, so a poll
    /// answer alone never creates an exemption.
    @Test
    func playbackThatStartsInTheBackgroundEarnsNothing() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()

        exemptions.refresh(service, isPlaying: true, now: start)

        #expect(!exemptions.isExempt(service))
        #expect(exemptions.isEmpty)
    }

    @Test
    func theExemptionEndsAfterTheGracePeriod() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()
        exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        let beforeTheEnd = start.addingTimeInterval(
            BackgroundAudioExemptions.gracePeriod - 1
        )
        let earlyExpiry = exemptions.expire(now: beforeTheEnd)
        #expect(earlyExpiry.isEmpty)
        #expect(exemptions.isExempt(service))

        let atTheEnd = start.addingTimeInterval(BackgroundAudioExemptions.gracePeriod)
        let expiry = exemptions.expire(now: atTheEnd)
        #expect(expiry == [service])
        #expect(!exemptions.isExempt(service))
    }

    /// The gap between two tracks must not end the exemption. Each poll that
    /// reports playback moves the deadline.
    @Test
    func aPlayingPollRefreshesTheDeadline() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()
        exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        var moment = start
        for _ in 0..<10 {
            moment = moment.addingTimeInterval(
                BackgroundAudioExemptions.gracePeriod - 1
            )
            exemptions.refresh(service, isPlaying: true, now: moment)
            let expiry = exemptions.expire(now: moment)
            #expect(expiry.isEmpty)
        }

        #expect(exemptions.isExempt(service))
    }

    /// A silent poll keeps the entry, because the grace period decides the end.
    @Test
    func aSilentPollKeepsTheExemptionInsideTheGracePeriod() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()
        exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        let shortPause = start.addingTimeInterval(10)
        exemptions.refresh(service, isPlaying: false, now: shortPause)

        let expiry = exemptions.expire(now: shortPause)
        #expect(expiry.isEmpty)
        #expect(exemptions.isExempt(service))
    }

    @Test
    func revokeEndsTheExemption() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()
        exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        exemptions.revoke(service)

        #expect(!exemptions.isExempt(service))
        #expect(exemptions.isEmpty)
    }

    /// Mute, a return to the screen, the stop action, and removal all end the
    /// exemption through the same route, and a second revoke is harmless.
    @Test
    func revokeIsSafeForAServiceWithoutAnExemption() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()

        exemptions.revoke(service)
        exemptions.revoke(service)

        #expect(exemptions.isEmpty)
    }

    /// A switch away from a service that stopped playing clears the exemption
    /// it held before, so a stale grant cannot survive a second switch.
    @Test
    func aSecondSwitchWithoutPlaybackClearsTheExemption() {
        var exemptions = BackgroundAudioExemptions()
        let service = UUID()
        exemptions.grantIfPlaying(service, isPlaying: true, now: start)

        let regranted = exemptions.grantIfPlaying(service, isPlaying: false, now: start)

        #expect(!regranted)
        #expect(!exemptions.isExempt(service))
    }

    @Test
    func expiryLeavesEveryOtherServiceAlone() {
        var exemptions = BackgroundAudioExemptions()
        let stopped = UUID()
        let playing = UUID()
        exemptions.grantIfPlaying(stopped, isPlaying: true, now: start)
        exemptions.grantIfPlaying(playing, isPlaying: true, now: start)

        let later = start.addingTimeInterval(BackgroundAudioExemptions.gracePeriod)
        exemptions.refresh(playing, isPlaying: true, now: later)

        let expiry = exemptions.expire(now: later)
        #expect(expiry == [stopped])
        #expect(exemptions.isExempt(playing))
    }

    /// The grace period has to cover a track gap and a short keyboard pause,
    /// and it has to stay short enough to release a page that stopped for good.
    @Test
    func theGracePeriodAndPollIntervalStayInTheirRange() {
        #expect(BackgroundAudioExemptions.gracePeriod >= 60)
        #expect(BackgroundAudioExemptions.gracePeriod <= 300)
        #expect(BackgroundAudioExemptions.pollInterval >= 1)
        #expect(
            BackgroundAudioExemptions.pollInterval
                < BackgroundAudioExemptions.gracePeriod
        )
    }
}
