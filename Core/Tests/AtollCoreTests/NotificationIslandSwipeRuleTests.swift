import AtollCore
import Testing

@Suite("Notification island swipe rule")
struct NotificationIslandSwipeRuleTests {
    private let cardWidth = 400.0

    @Test("The first movement gives the drag direction")
    func firstMovementGivesTheDragDirection() {
        let rule = NotificationIslandSwipeRule.self

        #expect(rule.isHorizontal(translationX: 12, translationY: 3))
        #expect(rule.isHorizontal(translationX: -12, translationY: 3))
        #expect(!rule.isHorizontal(translationX: 3, translationY: 12))
        #expect(!rule.isHorizontal(translationX: -3, translationY: -12))
        #expect(!rule.isHorizontal(translationX: 8, translationY: 8))
    }

    @Test("The card follows each movement to the right")
    func cardFollowsEachMovementToTheRight() {
        let rule = NotificationIslandSwipeRule.self

        #expect(rule.displayOffset(dragX: 0, cardWidth: cardWidth) == 0)
        #expect(rule.displayOffset(dragX: 30, cardWidth: cardWidth) == 30)
        #expect(rule.displayOffset(dragX: 260, cardWidth: cardWidth) == 260)
    }

    @Test("A movement to the left gives resistance")
    func movementToTheLeftGivesResistance() {
        let rule = NotificationIslandSwipeRule.self
        let offset = rule.displayOffset(dragX: -100, cardWidth: cardWidth)

        #expect(offset == -100 * rule.leftRubberBand)
        #expect(offset > -100)
        #expect(offset < 0)
    }

    @Test("Reduce Motion holds a card for a movement to the left")
    func reduceMotionHoldsACardForAMovementToTheLeft() {
        let rule = NotificationIslandSwipeRule.self

        #expect(
            rule.displayOffset(
                dragX: -100,
                cardWidth: cardWidth,
                reduceMotion: true
            ) == 0
        )
        #expect(
            rule.displayOffset(
                dragX: 100,
                cardWidth: cardWidth,
                reduceMotion: true
            ) == 100
        )
    }

    @Test("The card becomes lighter while it goes away")
    func cardBecomesLighterWhileItGoesAway() {
        let rule = NotificationIslandSwipeRule.self

        #expect(rule.displayOpacity(offset: 0, cardWidth: cardWidth) == 1)
        #expect(
            abs(
                rule.displayOpacity(offset: cardWidth / 2, cardWidth: cardWidth)
                    - 0.7
            ) < 0.0001
        )
        #expect(
            abs(
                rule.displayOpacity(offset: cardWidth, cardWidth: cardWidth)
                    - 0.4
            ) < 0.0001
        )
        #expect(
            rule.displayOpacity(offset: cardWidth * 2, cardWidth: cardWidth)
                == rule.displayOpacity(offset: cardWidth, cardWidth: cardWidth)
        )
        #expect(
            rule.displayOpacity(offset: -cardWidth, cardWidth: cardWidth)
                == rule.displayOpacity(offset: cardWidth, cardWidth: cardWidth)
        )
    }

    @Test("The card opacity never grows with the movement")
    func cardOpacityNeverGrowsWithTheMovement() {
        let rule = NotificationIslandSwipeRule.self
        var previous = 1.0

        for step in 0...20 {
            let offset = cardWidth * Double(step) / 10
            let opacity = rule.displayOpacity(
                offset: offset,
                cardWidth: cardWidth
            )
            #expect(opacity <= previous)
            #expect(opacity >= 0.4)
            previous = opacity
        }
    }

    @Test("Reduce Motion keeps the complete card opacity")
    func reduceMotionKeepsTheCompleteCardOpacity() {
        #expect(
            NotificationIslandSwipeRule.displayOpacity(
                offset: 200,
                cardWidth: cardWidth,
                reduceMotion: true
            ) == 1
        )
    }

    @Test("A card without a width keeps its opacity")
    func cardWithoutAWidthKeepsItsOpacity() {
        #expect(
            NotificationIslandSwipeRule.displayOpacity(
                offset: 40,
                cardWidth: 0
            ) == 1
        )
    }

    @Test("The drag rule keeps its tuned values")
    func dragRuleKeepsItsTunedValues() {
        let rule = NotificationIslandSwipeRule.self

        #expect(rule.minimumDistance == 8)
        #expect(rule.dismissFraction == 0.25)
        #expect(rule.dismissVelocity == 400)
        #expect(rule.leftRubberBand == 0.35)
        // One quarter of a 400 point card is 100 points.
        #expect(
            rule.shouldDismiss(dragX: 100, velocityX: 0, cardWidth: 400)
        )
        #expect(
            !rule.shouldDismiss(dragX: 99, velocityX: 0, cardWidth: 400)
        )
        #expect(
            rule.shouldDismiss(dragX: 20, velocityX: 400, cardWidth: 400)
        )
    }

    @Test("A long movement to the right dismisses the card")
    func longMovementToTheRightDismissesTheCard() {
        let rule = NotificationIslandSwipeRule.self
        let threshold = rule.dismissFraction * cardWidth

        #expect(
            rule.shouldDismiss(
                dragX: threshold,
                velocityX: 0,
                cardWidth: cardWidth
            )
        )
        #expect(
            rule.shouldDismiss(
                dragX: threshold + 20,
                velocityX: 0,
                cardWidth: cardWidth
            )
        )
        #expect(
            !rule.shouldDismiss(
                dragX: threshold - 1,
                velocityX: 0,
                cardWidth: cardWidth
            )
        )
    }

    @Test("A fast movement to the right dismisses the card")
    func fastMovementToTheRightDismissesTheCard() {
        let rule = NotificationIslandSwipeRule.self

        #expect(
            rule.shouldDismiss(
                dragX: rule.minimumDistance + 1,
                velocityX: rule.dismissVelocity,
                cardWidth: cardWidth
            )
        )
        #expect(
            !rule.shouldDismiss(
                dragX: rule.minimumDistance,
                velocityX: rule.dismissVelocity,
                cardWidth: cardWidth
            )
        )
        #expect(
            !rule.shouldDismiss(
                dragX: rule.minimumDistance + 1,
                velocityX: rule.dismissVelocity - 1,
                cardWidth: cardWidth
            )
        )
    }

    @Test("A movement to the left never dismisses the card")
    func movementToTheLeftNeverDismissesTheCard() {
        let rule = NotificationIslandSwipeRule.self

        #expect(
            !rule.shouldDismiss(
                dragX: -cardWidth,
                velocityX: -2_000,
                cardWidth: cardWidth
            )
        )
        #expect(
            !rule.shouldDismiss(dragX: 0, velocityX: 0, cardWidth: cardWidth)
        )
        #expect(
            !rule.shouldDismiss(
                dragX: -20,
                velocityX: 2_000,
                cardWidth: cardWidth
            )
        )
    }

    @Test("The card leaves past the complete card width")
    func cardLeavesPastTheCompleteCardWidth() {
        let rule = NotificationIslandSwipeRule.self

        #expect(rule.releaseOffset(cardWidth: cardWidth) > cardWidth)
        #expect(rule.releaseOffset(cardWidth: cardWidth) == cardWidth + 40)
        #expect(rule.releaseOffset(cardWidth: -10) == 40)
    }
}
