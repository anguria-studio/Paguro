/// Rules for the thin overflow indicator of a rail that scrolls.
///
/// A rail hides the system scroll indicator, because a legacy scroller takes
/// width from the scroll view content. That width moves every icon off the rail
/// centerline as soon as the rail overflows. The rail draws this indicator in an
/// overlay instead, which changes no layout.
///
/// The rules use `Double` values along the scroll axis, so this type stays
/// independent of SwiftUI and AppKit.
public enum RailScrollIndicator: Sendable {
    /// Thickness of the indicator, across the scroll axis.
    public static let thickness = 3.0

    /// Distance from the indicator to the rail surface edge.
    public static let edgeGap = 2.0

    /// Shortest indicator. A rail with many items keeps a visible handle.
    public static let minimumLength = 20.0

    /// Time without a scroll change that hides the indicator again.
    public static let idleSeconds = 0.9

    /// Duration of the fade that shows and hides the indicator.
    public static let fadeSeconds = 0.18

    /// Overflow under this length counts as no overflow. It absorbs the rounding
    /// of a measured content length.
    public static let overflowTolerance = 0.5

    /// The drawn indicator, along the scroll axis.
    public struct Placement: Equatable, Sendable {
        /// Length of the indicator, in points.
        public let length: Double

        /// Distance from the start of the viewport to the indicator, in points.
        public let offset: Double

        public init(length: Double, offset: Double) {
            self.length = length
            self.offset = offset
        }
    }

    /// Says whether the content is longer than the viewport that shows it.
    ///
    /// - Parameters:
    ///   - contentLength: Length of the complete content, in points.
    ///   - viewportLength: Length of the visible rail, in points.
    /// - Returns: True when the rail can scroll.
    public static func overflows(contentLength: Double, viewportLength: Double) -> Bool {
        guard contentLength.isFinite, viewportLength.isFinite, viewportLength > 0 else {
            return false
        }
        return contentLength - viewportLength > overflowTolerance
    }

    /// Gives the length and the position of the indicator.
    ///
    /// The indicator is as long a part of the viewport as the viewport is of the
    /// content, and it travels the remaining viewport length. A scroll position
    /// outside the content, which a rubber-band scroll reports, holds the
    /// indicator at the end it passed.
    ///
    /// - Parameters:
    ///   - contentLength: Length of the complete content, in points.
    ///   - viewportLength: Length of the visible rail, in points.
    ///   - offset: Current scroll position, in points.
    ///   - minimumLength: Shortest indicator, in points.
    /// - Returns: The indicator to draw, or nil when the rail shows all of its
    ///   content and needs none.
    public static func placement(
        contentLength: Double,
        viewportLength: Double,
        offset: Double,
        minimumLength: Double = minimumLength
    ) -> Placement? {
        guard overflows(contentLength: contentLength, viewportLength: viewportLength) else {
            return nil
        }

        let proportional = viewportLength * viewportLength / contentLength
        let floor = max(0, min(minimumLength, viewportLength))
        let length = min(viewportLength, max(floor, proportional))

        let travel = max(0, viewportLength - length)
        let maximumOffset = contentLength - viewportLength
        let progress = offset.isFinite ? min(1, max(0, offset / maximumOffset)) : 0

        return Placement(length: length, offset: travel * progress)
    }
}
