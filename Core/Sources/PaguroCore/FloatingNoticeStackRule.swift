import Foundation

/// Which floating notices the window shows when more than a few arrive.
///
/// The newest notice takes the top place, like a macOS notification. A tall
/// stack would cover the content it reports on, so the window shows a few cards
/// and holds the rest back. A notice that waits for the user is never held back
/// for a notice that leaves on its own: the user would then never reach its
/// buttons.
public enum FloatingNoticeStackRule {
    /// The largest number of cards on screen at one time.
    public static let visibleLimit = 3

    /// The notices to show, in the order they arrive in.
    ///
    /// - Parameters:
    ///   - newestFirst: Every notice that applies, newest first.
    ///   - staysUntilActed: The notices that wait for the user.
    ///   - limit: How many cards the window shows.
    /// - Returns: The visible notices, in the order of `newestFirst`.
    public static func visible<ID: Hashable>(
        newestFirst: [ID],
        staysUntilActed: Set<ID>,
        limit: Int = visibleLimit
    ) -> [ID] {
        guard limit > 0 else { return [] }
        guard newestFirst.count > limit else { return newestFirst }

        var kept: Set<ID> = []
        // The notices that wait for the user take the places first, newest
        // first. Only another waiting notice can hold one of them back.
        for id in newestFirst where staysUntilActed.contains(id) {
            guard kept.count < limit else { break }
            kept.insert(id)
        }
        for id in newestFirst where !staysUntilActed.contains(id) {
            guard kept.count < limit else { break }
            kept.insert(id)
        }
        return newestFirst.filter(kept.contains)
    }
}
