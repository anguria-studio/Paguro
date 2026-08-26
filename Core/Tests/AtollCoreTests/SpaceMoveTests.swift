import Testing
@testable import AtollCore

struct SpaceMoveTests {
    @Test
    func eligibleSpacesExcludeExistingMembershipsAndKeepOrder() {
        #expect(SpaceMove.eligibleSpaceIDs(
            allSpaceIDs: ["a", "b", "c"],
            memberSpaceIDs: ["a"]
        ) == ["b", "c"])
        #expect(SpaceMove.eligibleSpaceIDs(
            allSpaceIDs: ["c", "a", "b"],
            memberSpaceIDs: ["a"]
        ) == ["c", "b"])
    }

    @Test
    func noEligibleSpaceReturnsAnEmptyList() {
        #expect(SpaceMove.eligibleSpaceIDs(
            allSpaceIDs: ["a", "b"],
            memberSpaceIDs: ["a", "b"]
        ).isEmpty)
        #expect(SpaceMove.eligibleSpaceIDs(
            allSpaceIDs: [String](),
            memberSpaceIDs: ["a"]
        ).isEmpty)
    }
}
