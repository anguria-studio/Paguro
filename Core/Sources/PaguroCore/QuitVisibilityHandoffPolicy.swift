import Foundation

/// The timing rules for the visibility handoff at quit.
///
/// Paguro reports every page as visible and blocks its `visibilitychange`
/// events. Many web apps save their state when the page becomes hidden, so at
/// quit Paguro ends the override and sends the event before it releases the
/// web views. The pages then need a short time to run their save handlers,
/// which can start asynchronous IndexedDB writes.
public enum QuitVisibilityHandoffPolicy {
    /// The longest time the whole handoff can hold the quit.
    public static let cap: Duration = .milliseconds(300)

    /// The shortest handoff when at least one page accepted the release.
    public static let minimumGrace: Duration = .milliseconds(150)

    /// The time to keep waiting after the release calls end.
    ///
    /// Without an accepted release no page has a save handler to run, so the
    /// handoff ends at once. The wait never goes past `cap`.
    public static func remainingGrace(
        elapsed: Duration,
        acceptedCount: Int,
        minimumGrace: Duration = minimumGrace,
        cap: Duration = cap
    ) -> Duration {
        guard acceptedCount > 0 else { return .zero }
        return max(.zero, min(minimumGrace, cap) - elapsed)
    }

    /// The time left for the release calls before the cap ends the handoff.
    /// Without a live page the handoff has nothing to wait for.
    public static func releaseTimeout(viewCount: Int, cap: Duration = cap) -> Duration {
        viewCount > 0 ? cap : .zero
    }
}
