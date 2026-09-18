import Foundation

/// Geometry for the floating notice cards above the web content.
///
/// The values use `Double` so this rule stays independent of SwiftUI and
/// AppKit. The app target converts the result to `CGFloat` at the view edge.
public enum FloatingNoticeLayout {
    /// The comfortable reading width of one card.
    public static let preferredWidth = 350.0

    /// The gap between a card and the edges of the web content.
    public static let edgeInset = 14.0

    /// The gap between two stacked cards.
    public static let cardSpacing = 9.0

    /// The height that the find bar and its own inset occupy at the top
    /// trailing corner. The card stack starts below it, so the two controls
    /// never cover each other.
    public static let findBarClearance = 52.0

    /// The width of one card in the space that the web content offers.
    ///
    /// A narrow window must not push the card past the opposite edge, so the
    /// card gives up its preferred width and keeps the margin on both sides.
    public static func width(availableWidth: Double) -> Double {
        let widthInsideMargins = availableWidth - (edgeInset * 2)
        return max(0, min(preferredWidth, widthInsideMargins))
    }

    /// The gap above the first card.
    public static func topInset(findBarIsVisible: Bool) -> Double {
        findBarIsVisible ? findBarClearance : edgeInset
    }
}
