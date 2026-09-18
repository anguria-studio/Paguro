import PaguroCore
import Testing

@Suite("Rail scroll indicator")
struct RailScrollIndicatorTests {
    private let rule = RailScrollIndicator.self

    private func placement(
        content: Double,
        viewport: Double,
        offset: Double,
        minimumLength: Double = RailScrollIndicator.minimumLength
    ) -> RailScrollIndicator.Placement? {
        rule.placement(
            contentLength: content,
            viewportLength: viewport,
            offset: offset,
            minimumLength: minimumLength
        )
    }

    @Test("Content shorter than the viewport shows no indicator")
    func contentShorterThanTheViewportShowsNoIndicator() {
        #expect(placement(content: 80, viewport: 200, offset: 0) == nil)
        #expect(placement(content: 200, viewport: 200, offset: 0) == nil)
    }

    @Test("Overflow inside the tolerance shows no indicator")
    func overflowInsideTheToleranceShowsNoIndicator() {
        #expect(placement(content: 200.4, viewport: 200, offset: 0) == nil)
        #expect(placement(content: 200.6, viewport: 200, offset: 0) != nil)
        #expect(rule.overflows(contentLength: 200.4, viewportLength: 200) == false)
        #expect(rule.overflows(contentLength: 200.6, viewportLength: 200))
    }

    @Test("Zero and negative sizes show no indicator")
    func zeroAndNegativeSizesShowNoIndicator() {
        #expect(placement(content: 400, viewport: 0, offset: 0) == nil)
        #expect(placement(content: 400, viewport: -200, offset: 0) == nil)
        #expect(placement(content: -400, viewport: 200, offset: 0) == nil)
        #expect(placement(content: 0, viewport: 0, offset: 0) == nil)
    }

    @Test("Values that are not numbers show no indicator")
    func valuesThatAreNotNumbersShowNoIndicator() {
        #expect(placement(content: .nan, viewport: 200, offset: 0) == nil)
        #expect(placement(content: .infinity, viewport: 200, offset: 0) == nil)
        #expect(placement(content: 400, viewport: .nan, offset: 0) == nil)
    }

    @Test("The indicator is as long a part of the viewport as the viewport is of the content")
    func theIndicatorKeepsTheProportionOfTheViewport() {
        let half = placement(content: 400, viewport: 200, offset: 0)
        #expect(half?.length == 100)

        let quarter = placement(content: 800, viewport: 200, offset: 0)
        #expect(quarter?.length == 50)
    }

    @Test("The indicator travels the viewport length that it leaves free")
    func theIndicatorTravelsTheFreeViewportLength() {
        #expect(placement(content: 400, viewport: 200, offset: 0)?.offset == 0)
        #expect(placement(content: 400, viewport: 200, offset: 100)?.offset == 50)
        #expect(placement(content: 400, viewport: 200, offset: 200)?.offset == 100)
    }

    @Test("A scroll position outside the content holds the indicator at that end")
    func aScrollPositionOutsideTheContentClamps() {
        #expect(placement(content: 400, viewport: 200, offset: -80)?.offset == 0)
        #expect(placement(content: 400, viewport: 200, offset: 4_000)?.offset == 100)
        #expect(placement(content: 400, viewport: 200, offset: .nan)?.offset == 0)
    }

    @Test("A long rail keeps the shortest indicator")
    func aLongRailKeepsTheShortestIndicator() {
        let long = placement(content: 10_000, viewport: 200, offset: 0)
        #expect(long?.length == RailScrollIndicator.minimumLength)

        let end = placement(content: 10_000, viewport: 200, offset: 9_800)
        #expect(end?.offset == 200 - RailScrollIndicator.minimumLength)
    }

    @Test("The indicator never passes the viewport length")
    func theIndicatorNeverPassesTheViewportLength() {
        let short = placement(content: 100, viewport: 10, offset: 5, minimumLength: 20)
        #expect(short?.length == 10)
        #expect(short?.offset == 0)
    }
}
