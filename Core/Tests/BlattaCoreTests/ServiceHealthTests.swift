import Testing
@testable import BlattaCore

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
    func navigationEventsNeverProduceSignedOut() {
        for state in ServiceHealth.allCases {
            for event in ServiceHealth.Event.allCases {
                #expect(state.next(event) != .signedOut)
            }
        }
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
