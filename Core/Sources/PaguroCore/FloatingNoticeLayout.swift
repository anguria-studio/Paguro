import Foundation

/// Geometry for the floating notice cards at the top trailing corner of the
/// window.
///
/// The values use `Double` so this rule stays independent of SwiftUI and
/// AppKit. The app target converts the result to `CGFloat` at the view edge.
public enum FloatingNoticeLayout {
    /// The comfortable reading width of one card.
    public static let preferredWidth = 350.0

    /// The gap between a card and the edges of the content it floats over.
    public static let edgeInset = 14.0

    /// The gap between two stacked cards.
    public static let cardSpacing = 9.0

    /// The height that the find bar and its own inset occupy at the top
    /// trailing corner. The card stack starts below it, so the two controls
    /// never cover each other.
    public static let findBarClearance = 52.0

    /// The band at the top of the window that the hidden title bar keeps.
    ///
    /// The window controls sit in it and a drag in it moves the window. A screen
    /// that draws no header and no bar, such as the first-run screen, therefore
    /// starts its cards below this band alone.
    public static let titleBarBand = 28.0

    /// The width of one card in the space that the content offers.
    ///
    /// A narrow window must not push the card past the opposite edge, so the
    /// card gives up its preferred width and keeps the margin on both sides.
    public static func width(availableWidth: Double) -> Double {
        let widthInsideMargins = availableWidth - (edgeInset * 2)
        return max(0, min(preferredWidth, widthInsideMargins))
    }

    /// The gap above the first card.
    ///
    /// `chromeHeight` is what the window draws above the content at the top
    /// trailing corner: the content header of the sidebar layout, or the bar of
    /// a layout that puts a rail along the top. The stack starts below that
    /// chrome, so a card keeps one place over the content in every layout. A
    /// screen with no chrome passes `titleBarBand`.
    public static func topInset(chromeHeight: Double, findBarIsVisible: Bool) -> Double {
        max(0, chromeHeight) + (findBarIsVisible ? findBarClearance : edgeInset)
    }
}
