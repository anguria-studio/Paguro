import Testing
@testable import PaguroCore

struct LinkOpeningPolicyTests {
    @Test(arguments: [false, true])
    func inheritanceAndOverrides(global: Bool) {
        #expect(LinkOpeningPolicy(override: nil).opensInPaguro(globalDefault: global) == global)
        #expect(LinkOpeningPolicy(override: true).opensInPaguro(globalDefault: global))
        #expect(!LinkOpeningPolicy(override: false).opensInPaguro(globalDefault: global))
    }

    @Test(arguments: LinkOpeningPolicy.allCases)
    func editorChoiceRoundTrips(policy: LinkOpeningPolicy) {
        #expect(LinkOpeningPolicy(override: policy.override) == policy)
    }
}
