import Foundation

/// The rules for the website storage flush at quit.
///
/// WebKit can lose the most recent local storage writes when the process exits
/// directly after the web views close, while cookies and IndexedDB keep theirs.
/// A data record fetch on each persistent store waits for the pending writes.
/// A short minimum wait covers the same risk when a fetch answers very fast.
/// The timeout makes sure that a store that never answers cannot hold the quit.
public enum QuitStorageFlushPolicy {
    /// The longest time the fetch step can hold the quit.
    public static let timeout: Duration = .milliseconds(500)

    /// The shortest time between the web-view teardown and the reply to AppKit.
    public static let minimumWait: Duration = .milliseconds(50)

    /// The time that is still necessary to reach `minimumWait` after
    /// `elapsed` has passed since the teardown. It is never negative.
    public static func remainingMinimumWait(
        elapsed: Duration,
        minimumWait: Duration = minimumWait
    ) -> Duration {
        max(.zero, minimumWait - elapsed)
    }

    /// The stores to flush, in first-seen order.
    ///
    /// A non-persistent store has no data on disk, so the flush skips it.
    /// Two web views can share one store, so each identifier occurs once.
    public static func storesToFlush<Store>(
        _ candidates: [Store],
        identifier: (Store) -> UUID?,
        isPersistent: (Store) -> Bool
    ) -> [Store] {
        var seen: Set<UUID?> = []
        return candidates.filter { store in
            isPersistent(store) && seen.insert(identifier(store)).inserted
        }
    }

    /// The whole milliseconds in `duration`, for a log line.
    public static func milliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        return Int(components.seconds) * 1_000
            + Int(components.attoseconds / 1_000_000_000_000_000)
    }
}
