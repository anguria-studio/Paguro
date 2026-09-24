import Foundation
import Testing
@testable import PaguroCore

struct QuitVisibilityHandoffPolicyTests {
    @Test
    func limitsMatchTheAgreedValues() {
        #expect(QuitVisibilityHandoffPolicy.cap == .milliseconds(300))
        #expect(QuitVisibilityHandoffPolicy.minimumGrace == .milliseconds(150))
    }

    @Test
    func minimumGraceAppliesOnlyWhenAPageAccepted() {
        #expect(QuitVisibilityHandoffPolicy.remainingGrace(elapsed: .milliseconds(20), acceptedCount: 0) == .zero)
        #expect(
            QuitVisibilityHandoffPolicy.remainingGrace(elapsed: .milliseconds(20), acceptedCount: 1)
                == .milliseconds(130)
        )
        #expect(
            QuitVisibilityHandoffPolicy.remainingGrace(elapsed: .zero, acceptedCount: 3)
                == .milliseconds(150)
        )
    }

    @Test
    func graceEndsWhenTheMinimumHasPassed() {
        #expect(QuitVisibilityHandoffPolicy.remainingGrace(elapsed: .milliseconds(150), acceptedCount: 1) == .zero)
        #expect(QuitVisibilityHandoffPolicy.remainingGrace(elapsed: .milliseconds(300), acceptedCount: 1) == .zero)
    }

    /// A hung page ends the release step at the cap, and the grace never adds
    /// time after it, even with a minimum larger than the cap.
    @Test
    func graceNeverGoesPastTheCap() {
        #expect(
            QuitVisibilityHandoffPolicy.remainingGrace(
                elapsed: .milliseconds(100),
                acceptedCount: 1,
                minimumGrace: .milliseconds(500),
                cap: .milliseconds(300)
            ) == .milliseconds(200)
        )
        #expect(
            QuitVisibilityHandoffPolicy.remainingGrace(
                elapsed: QuitVisibilityHandoffPolicy.cap,
                acceptedCount: 2
            ) == .zero
        )
    }

    @Test
    func noLiveViewsMeansNoWait() {
        #expect(QuitVisibilityHandoffPolicy.releaseTimeout(viewCount: 0) == .zero)
        #expect(QuitVisibilityHandoffPolicy.releaseTimeout(viewCount: 2) == .milliseconds(300))
    }
}
