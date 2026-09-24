import Foundation
import WebKit
import os
import PaguroCore

/// Waits for WebKit to write recent website storage before Paguro exits.
///
/// A controlled test on macOS 27 lost the last local storage writes in some
/// quick exits after the web-view teardown. A data record fetch on the store,
/// or a wait of 50 ms, prevented the loss. This step does both, with a
/// timeout. `QuitStorageFlushPolicy` holds the numbers and the store selection.
@MainActor
enum QuitStorageFlush {
    struct Outcome: Equatable, Sendable {
        var storeCount: Int
        var completedCount: Int
        var timedOut: Bool
        /// The time from the teardown to the end of the flush.
        var elapsed: Duration
        /// The time from the end of the fetches to the moment the caller
        /// could run again on the main thread.
        var mainThreadDelay: Duration = .zero
    }

    /// The production fetch. `cookies` alone did not work as a barrier in the
    /// test, so the fetch asks for every data type.
    static func fetchAllRecords(_ store: WKWebsiteDataStore) async {
        _ = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
    }

    /// Fetches from every store in parallel, and returns when all stores
    /// answer or when `timeout` ends. Then it waits until `minimumWait` has
    /// passed since `teardownFinishedAt`.
    ///
    /// Without a store there is no web content to flush, so it returns at once.
    static func run<Store: AnyObject>(
        stores: [Store],
        teardownFinishedAt: ContinuousClock.Instant,
        timeout: Duration = QuitStorageFlushPolicy.timeout,
        minimumWait: Duration = QuitStorageFlushPolicy.minimumWait,
        fetch: @escaping @MainActor (Store) async -> Void
    ) async -> Outcome {
        let clock = ContinuousClock()
        guard !stores.isEmpty else {
            return Outcome(
                storeCount: 0,
                completedCount: 0,
                timedOut: false,
                elapsed: clock.now - teardownFinishedAt
            )
        }

        let race = BoundedParallelRace(items: stores) { store in
            await fetch(store)
            return true
        }
        let result = await race.run(until: clock.now + timeout)
        let now = clock.now
        let mainThreadDelay = now - result.decidedAt
        let remaining = QuitStorageFlushPolicy.remainingMinimumWait(
            elapsed: now - teardownFinishedAt,
            minimumWait: minimumWait
        )
        if remaining > .zero {
            try? await Task.sleep(until: now + remaining, tolerance: .milliseconds(2), clock: .continuous)
        }
        return Outcome(
            storeCount: stores.count,
            completedCount: result.answeredCount,
            timedOut: result.timedOut,
            elapsed: clock.now - teardownFinishedAt,
            mainThreadDelay: mainThreadDelay
        )
    }

    static func log(_ outcome: Outcome) {
        let elapsedMs = QuitStorageFlushPolicy.milliseconds(outcome.elapsed)
        AppLogger.dataStore.notice(
            "Quit storage flush: stores=\(outcome.storeCount, privacy: .public) completed=\(outcome.completedCount, privacy: .public) timedOut=\(outcome.timedOut, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
        if QuitStorageFlushPolicy.isNotableMainThreadDelay(outcome.mainThreadDelay) {
            let delayMs = QuitStorageFlushPolicy.milliseconds(outcome.mainThreadDelay)
            AppLogger.dataStore.notice(
                "Quit storage flush delayed by the main thread: delayMs=\(delayMs, privacy: .public)"
            )
        }
    }
}
