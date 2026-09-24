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

        let race = FetchRace(stores: stores, fetch: fetch)
        let result = await race.run(timeout: timeout)
        let remaining = QuitStorageFlushPolicy.remainingMinimumWait(
            elapsed: clock.now - teardownFinishedAt,
            minimumWait: minimumWait
        )
        if remaining > .zero {
            try? await Task.sleep(for: remaining)
        }
        return Outcome(
            storeCount: stores.count,
            completedCount: result.completedCount,
            timedOut: result.timedOut,
            elapsed: clock.now - teardownFinishedAt
        )
    }

    static func log(_ outcome: Outcome) {
        let elapsedMs = QuitStorageFlushPolicy.milliseconds(outcome.elapsed)
        AppLogger.dataStore.notice(
            "Quit storage flush: stores=\(outcome.storeCount, privacy: .public) completed=\(outcome.completedCount, privacy: .public) timedOut=\(outcome.timedOut, privacy: .public) elapsedMs=\(elapsedMs, privacy: .public)"
        )
    }
}

/// Races the store fetches against one timer.
///
/// A task group cannot do this: it awaits every child before it returns, and a
/// fetch is not cancellable, so one store that never answers would hold the
/// quit. The fetches run as unstructured tasks instead. The first of "all
/// answered" and "timer ended" resumes the caller, and a late fetch only
/// increments a counter that nobody reads.
@MainActor
private final class FetchRace<Store: AnyObject> {
    struct Result {
        var completedCount: Int
        var timedOut: Bool
    }

    private let stores: [Store]
    private let fetch: @MainActor (Store) async -> Void
    private var completedCount = 0
    private var continuation: CheckedContinuation<Result, Never>?
    private var timer: Task<Void, Never>?

    init(stores: [Store], fetch: @escaping @MainActor (Store) async -> Void) {
        self.stores = stores
        self.fetch = fetch
    }

    func run(timeout: Duration) async -> Result {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            for index in stores.indices {
                Task { @MainActor in
                    await self.fetch(self.stores[index])
                    self.storeDidAnswer()
                }
            }
            timer = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.finish(timedOut: true)
            }
        }
    }

    private func storeDidAnswer() {
        completedCount += 1
        if completedCount == stores.count {
            finish(timedOut: false)
        }
    }

    private func finish(timedOut: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(returning: Result(completedCount: completedCount, timedOut: timedOut))
    }
}
