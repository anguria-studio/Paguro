import Testing
@testable import PaguroCore

struct ServiceHealthTests {
    @Test
    func navigationEventsDetermineTheNextState() {
        for state in ServiceHealth.allCases {
            #expect(state.next(.startedLoading) == .loading)
            #expect(state.next(.finishedLoading) == .live)
            #expect(state.next(.failed) == .failed)
        }
    }

    @Test
    func navigationEventsDoNotIntroduceSignedOut() {
        for state in ServiceHealth.allCases {
            for event in ServiceHealth.Event.allCases {
                #expect(state.next(event) != .signedOut || (state == .signedOut && event == .stoppedLoading))
            }
        }
    }

    @Test
    func stoppingClearsOnlyTheLoadingMark() {
        #expect(ServiceHealth.loading.next(.stoppedLoading) == .live)
        #expect(ServiceHealth.failed.next(.stoppedLoading) == .failed)
        #expect(ServiceHealth.signedOut.next(.stoppedLoading) == .signedOut)
        #expect(ServiceHealth.live.next(.stoppedLoading) == .live)
    }

    @Test
    func visibleStatesHaveDistinctShapesAndDescriptions() {
        #expect(ServiceHealth.live.drawsDot == false)
        #expect(ServiceHealth.loading.drawsDot)
        #expect(ServiceHealth.failed.drawsDot)
        #expect(ServiceHealth.signedOut.drawsDot)

        let shapes = [
            ServiceHealth.loading.dotShape,
            ServiceHealth.failed.dotShape,
            ServiceHealth.signedOut.dotShape,
        ]
        #expect(Set(shapes).count == 3)

        #expect(ServiceHealth.live.spokenDescription.isEmpty)
        #expect(ServiceHealth.loading.spokenDescription == "loading")
        #expect(ServiceHealth.failed.spokenDescription == "failed to load")
        #expect(ServiceHealth.signedOut.spokenDescription == "signed out")
    }
}
