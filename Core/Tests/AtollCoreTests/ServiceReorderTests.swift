import Testing
@testable import AtollCore

struct ServiceReorderTests {
    @Test
    func placementMovesAnItemToEitherSideOfTheTarget() {
        let ids = ["first", "second", "third", "fourth"]

        #expect(ServiceReorder.reorderedIDs(
            ids,
            moving: "first",
            relativeTo: "second",
            placement: .after
        ) == ["second", "first", "third", "fourth"])
        #expect(ServiceReorder.reorderedIDs(
            ids,
            moving: "fourth",
            relativeTo: "first",
            placement: .before
        ) == ["fourth", "first", "second", "third"])
        #expect(ServiceReorder.reorderedIDs(
            ids,
            moving: "second",
            relativeTo: "fourth",
            placement: .after
        ) == ["first", "third", "fourth", "second"])
    }

    @Test
    func invalidAndNoEffectMovesReturnNil() {
        let ids = ["first", "second"]

        #expect(ServiceReorder.reorderedIDs(
            ids, moving: "first", relativeTo: "first", placement: .after
        ) == nil)
        #expect(ServiceReorder.reorderedIDs(
            ids, moving: "first", relativeTo: "second", placement: .before
        ) == nil)
        #expect(ServiceReorder.reorderedIDs(
            ids, moving: "second", relativeTo: "first", placement: .after
        ) == nil)
        #expect(ServiceReorder.reorderedIDs(
            ids, moving: "missing", relativeTo: "first", placement: .before
        ) == nil)
        #expect(ServiceReorder.reorderedIDs(
            ids, moving: "first", relativeTo: "missing", placement: .before
        ) == nil)
    }
}
