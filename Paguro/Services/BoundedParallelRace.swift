import Foundation

/// Runs one piece of work for each item in parallel and races it against one
/// timer. The quit path uses it, so no page or store can hold the quit.
///
/// A task group cannot do this: it awaits every child before it returns, and
/// WebKit calls are not cancellable, so one item that never answers would
/// hold the caller. The work runs as unstructured tasks instead. The first of
/// "all answered" and "timer ended" resumes the caller, and a late answer only
/// changes counters that nobody reads.
@MainActor
final class BoundedParallelRace<Item: AnyObject> {
    struct Result: Equatable, Sendable {
        /// The items whose work ended before the result.
        var answeredCount: Int
        /// The answered items whose work returned `true`.
        var acceptedCount: Int
        var timedOut: Bool
    }

    private let items: [Item]
    private let work: @MainActor (Item) async -> Bool
    private var answeredCount = 0
    private var acceptedCount = 0
    private var continuation: CheckedContinuation<Result, Never>?
    private var timer: Task<Void, Never>?

    init(items: [Item], work: @escaping @MainActor (Item) async -> Bool) {
        self.items = items
        self.work = work
    }

    /// Starts the work and returns when every item answers or `timeout` ends.
    /// Call it once.
    func run(timeout: Duration) async -> Result {
        guard !items.isEmpty else {
            return Result(answeredCount: 0, acceptedCount: 0, timedOut: false)
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for index in items.indices {
                Task { @MainActor in
                    let accepted = await self.work(self.items[index])
                    self.itemDidAnswer(accepted: accepted)
                }
            }
            timer = Task { @MainActor in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                self.finish(timedOut: true)
            }
        }
    }

    private func itemDidAnswer(accepted: Bool) {
        guard continuation != nil else { return }
        answeredCount += 1
        if accepted { acceptedCount += 1 }
        if answeredCount == items.count {
            finish(timedOut: false)
        }
    }

    private func finish(timedOut: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        timer = nil
        continuation.resume(returning: Result(
            answeredCount: answeredCount,
            acceptedCount: acceptedCount,
            timedOut: timedOut
        ))
    }
}
