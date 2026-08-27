/// Rules for the drag that dismisses one card of the notification stack.
///
/// A person moves a card to the right to dismiss it. A movement to the left
/// gives resistance and returns. The rules use `Double` values, so this type
/// stays independent of SwiftUI and AppKit.
public enum NotificationIslandSwipeRule: Sendable {
    /// Movement that starts the drag.
    ///
    /// A shorter movement stays a click, so a card keeps its open action.
    public static let minimumDistance = 8.0

    /// Part of the card width that dismisses the card.
    public static let dismissFraction = 0.25

    /// Movement speed in points each second that dismisses the card.
    public static let dismissVelocity = 400.0

    /// Part of a movement to the left that the card follows.
    public static let leftRubberBand = 0.35

    /// Distance past the card width where the card leaves the list.
    private static let releaseMargin = 40.0

    /// Smallest opacity of a card at the complete card width.
    private static let minimumOpacity = 0.4

    /// Tells if a drag moves the card and not the list.
    ///
    /// The first movement gives the direction. The drag keeps that direction
    /// until the person lifts the pointer.
    ///
    /// - Parameters:
    ///   - translationX: Horizontal movement of the drag.
    ///   - translationY: Vertical movement of the drag.
    /// - Returns: `true` for a horizontal drag.
    public static func isHorizontal(
        translationX: Double,
        translationY: Double
    ) -> Bool {
        abs(translationX) > abs(translationY)
    }

    /// Gives the horizontal position of the card during a drag.
    ///
    /// The card follows each movement to the right. A movement to the left
    /// gives resistance, because only a movement to the right dismisses the
    /// card. Reduce Motion holds the card for a movement to the left.
    ///
    /// - Parameters:
    ///   - dragX: Horizontal movement of the drag.
    ///   - cardWidth: Width of the card.
    ///   - reduceMotion: `true` when the system limits motion.
    /// - Returns: The horizontal card position in points.
    public static func displayOffset(
        dragX: Double,
        cardWidth: Double,
        reduceMotion: Bool = false
    ) -> Double {
        guard dragX < 0 else { return dragX }
        guard !reduceMotion else { return 0 }
        return dragX * leftRubberBand
    }

    /// Gives the card opacity during a drag.
    ///
    /// The card becomes lighter while it goes away. Reduce Motion keeps the
    /// complete opacity.
    ///
    /// - Parameters:
    ///   - offset: Horizontal card position from `displayOffset`.
    ///   - cardWidth: Width of the card.
    ///   - reduceMotion: `true` when the system limits motion.
    /// - Returns: A value from `minimumOpacity` through 1.
    public static func displayOpacity(
        offset: Double,
        cardWidth: Double,
        reduceMotion: Bool = false
    ) -> Double {
        guard !reduceMotion, cardWidth > 0 else { return 1 }
        let travelled = clamped(abs(offset) / cardWidth)
        return 1 - ((1 - minimumOpacity) * travelled)
    }

    /// Tells if the drag dismisses the card.
    ///
    /// A long movement or a fast movement to the right dismisses the card.
    /// A movement to the left never dismisses it.
    ///
    /// - Parameters:
    ///   - dragX: Horizontal movement of the drag.
    ///   - velocityX: Horizontal speed in points each second.
    ///   - cardWidth: Width of the card.
    /// - Returns: `true` when the card must leave the list.
    public static func shouldDismiss(
        dragX: Double,
        velocityX: Double,
        cardWidth: Double
    ) -> Bool {
        guard dragX > 0 else { return false }
        if cardWidth > 0, dragX >= dismissFraction * cardWidth {
            return true
        }
        return velocityX >= dismissVelocity && dragX > minimumDistance
    }

    /// Gives the position where the card leaves the list.
    public static func releaseOffset(cardWidth: Double) -> Double {
        max(0, cardWidth) + releaseMargin
    }

    private static func clamped(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
