import BlattaCore
import Testing

@Suite("Rail reorder rule")
struct RailReorderRuleTests {
    private let rule = RailReorderRule.self
    private let pitch = 30.0
    private let itemCount = 5

    private func target(startIndex: Int, translation: Double) -> Int {
        rule.targetIndex(
            startIndex: startIndex,
            translation: translation,
            pitch: pitch,
            itemCount: itemCount
        )
    }

    @Test("No movement keeps the start position")
    func noMovementKeepsTheStartPosition() {
        #expect(target(startIndex: 0, translation: 0) == 0)
        #expect(target(startIndex: 2, translation: 0) == 2)
        #expect(target(startIndex: 4, translation: 0) == 4)
    }

    @Test("One half pitch keeps the start position")
    func oneHalfPitchKeepsTheStartPosition() {
        #expect(target(startIndex: 2, translation: pitch / 2) == 2)
        #expect(target(startIndex: 2, translation: -pitch / 2) == 2)
        #expect(target(startIndex: 2, translation: 14) == 2)
        #expect(target(startIndex: 2, translation: -14) == 2)
    }

    @Test("A movement past one half pitch moves one position")
    func movementPastOneHalfPitchMovesOnePosition() {
        #expect(target(startIndex: 2, translation: (pitch / 2) + 0.5) == 3)
        #expect(target(startIndex: 2, translation: -(pitch / 2) - 0.5) == 1)
        #expect(target(startIndex: 2, translation: pitch) == 3)
        #expect(target(startIndex: 2, translation: -pitch) == 1)
    }

    @Test("Each further pitch moves one more position")
    func eachFurtherPitchMovesOneMorePosition() {
        #expect(target(startIndex: 0, translation: pitch * 1.5) == 1)
        #expect(target(startIndex: 0, translation: (pitch * 1.5) + 0.5) == 2)
        #expect(target(startIndex: 0, translation: pitch * 2) == 2)
        #expect(target(startIndex: 4, translation: -pitch * 2) == 2)
    }

    @Test("A movement past an end stays inside the list")
    func movementPastAnEndStaysInsideTheList() {
        #expect(target(startIndex: 0, translation: -pitch * 40) == 0)
        #expect(target(startIndex: 2, translation: -pitch * 40) == 0)
        #expect(target(startIndex: 4, translation: pitch * 40) == 4)
        #expect(target(startIndex: 2, translation: pitch * 40) == 4)
        #expect(target(startIndex: 2, translation: .infinity) == 2)
    }

    @Test("A complete reversal moves the first item to the last position")
    func completeReversalMovesTheFirstItemToTheLastPosition() {
        let ids = ["a", "b", "c", "d", "e"]
        let last = target(startIndex: 0, translation: pitch * 4)

        #expect(last == 4)
        #expect(
            rule.reordered(ids, movingFrom: 0, to: last)
                == ["b", "c", "d", "e", "a"]
        )

        let first = rule.targetIndex(
            startIndex: 4,
            translation: -pitch * 4,
            pitch: pitch,
            itemCount: itemCount
        )

        #expect(first == 0)
        #expect(
            rule.reordered(["b", "c", "d", "e", "a"], movingFrom: 4, to: first)
                == ids
        )
    }

    @Test("An empty group or an unusable pitch keeps the start position")
    func emptyGroupOrUnusablePitchKeepsTheStartPosition() {
        #expect(
            rule.targetIndex(
                startIndex: 0,
                translation: 200,
                pitch: pitch,
                itemCount: 0
            ) == 0
        )
        #expect(
            rule.targetIndex(
                startIndex: 1,
                translation: 200,
                pitch: 0,
                itemCount: 3
            ) == 1
        )
        #expect(
            rule.targetIndex(
                startIndex: 9,
                translation: 0,
                pitch: pitch,
                itemCount: 3
            ) == 2
        )
    }

    @Test("The offset keeps the dragged item under the pointer")
    func offsetKeepsTheDraggedItemUnderThePointer() {
        // The visible list has not changed yet, so the item follows the drag.
        #expect(
            rule.draggedOffset(
                translation: 12,
                startIndex: 2,
                liveIndex: 2,
                pitch: pitch
            ) == 12
        )

        // The list moved the item one position down. The offset removes the
        // one pitch that the new position added.
        #expect(
            rule.draggedOffset(
                translation: 40,
                startIndex: 2,
                liveIndex: 3,
                pitch: pitch
            ) == 10
        )

        // The same rule applies to a movement toward the start of the rail.
        #expect(
            rule.draggedOffset(
                translation: -40,
                startIndex: 2,
                liveIndex: 1,
                pitch: pitch
            ) == -10
        )
    }

    @Test("The dragged item stays still at each exact position")
    func draggedItemStaysStillAtEachExactPosition() {
        for step in 1...4 {
            let translation = pitch * Double(step)
            let live = target(startIndex: 0, translation: translation)
            let offset = rule.draggedOffset(
                translation: translation,
                startIndex: 0,
                liveIndex: live,
                pitch: pitch
            )

            #expect(live == step)
            #expect(offset == 0)
        }
    }

    @Test("A move to the same position keeps the list")
    func moveToTheSamePositionKeepsTheList() {
        let ids = ["a", "b", "c"]

        #expect(rule.reordered(ids, movingFrom: 1, to: 1) == ids)
        #expect(rule.reordered(ids, movingFrom: 1, to: 7) == ids)
        #expect(rule.reordered(ids, movingFrom: -1, to: 0) == ids)
        #expect(rule.reordered(ids, movingFrom: 0, to: 2) == ["b", "c", "a"])
        #expect(rule.reordered(ids, movingFrom: 2, to: 0) == ["c", "a", "b"])
    }

    @Test("The rail scrolls only near an edge")
    func railScrollsOnlyNearAnEdge() {
        let viewport = 400.0

        #expect(rule.autoscrollStep(pointerPosition: 200, viewportLength: viewport) == 0)
        #expect(rule.autoscrollStep(pointerPosition: 100, viewportLength: viewport) == 0)
        #expect(rule.autoscrollStep(pointerPosition: 10, viewportLength: viewport) < 0)
        #expect(rule.autoscrollStep(pointerPosition: 395, viewportLength: viewport) > 0)
    }

    @Test("The scroll speed increases near an edge")
    func scrollSpeedIncreasesNearAnEdge() {
        let viewport = 400.0
        let near = rule.autoscrollStep(pointerPosition: 20, viewportLength: viewport)
        let nearer = rule.autoscrollStep(pointerPosition: 4, viewportLength: viewport)

        #expect(nearer < near)
        #expect(nearer >= -rule.autoscrollMaximumStep)
        #expect(
            rule.autoscrollStep(pointerPosition: -80, viewportLength: viewport)
                == -rule.autoscrollMaximumStep
        )
        #expect(
            rule.autoscrollStep(pointerPosition: 900, viewportLength: viewport)
                == rule.autoscrollMaximumStep
        )
    }

    @Test("A short rail does not scroll")
    func shortRailDoesNotScroll() {
        #expect(rule.autoscrollStep(pointerPosition: 2, viewportLength: 40) == 0)
        #expect(rule.autoscrollStep(pointerPosition: 2, viewportLength: 0) == 0)
        #expect(rule.autoscrollStep(pointerPosition: .nan, viewportLength: 400) == 0)
    }
}
