import Foundation
import Synchronization

/// The result of one `BoundedParallelRace`.
struct BoundedRaceResult: Equatable, Sendable {
    /// The items whose work ended before the result.
    var answeredCount: Int
    /// The answered items whose work returned `true`.
    var acceptedCount: Int
    var timedOut: Bool
    /// When the race ended: the last answer or the deadline. The caller
    /// resumes later if the main thread is busy at that moment.
    var decidedAt: ContinuousClock.Instant
}

/// Runs one piece of work for each item in parallel and races it against a
/// deadline. The quit path uses it, so no page or store can hold the quit.
///
/// A task group cannot do this: it awaits every child before it returns, and
/// WebKit calls are not cancellable, so one item that never answers would
/// hold the caller. The work runs as unstructured tasks instead. The first of
/// "all answered" and "deadline passed" resumes the caller, and a late answer
/// changes nothing.
///
/// The timer runs off the main actor. A timer on the main actor started late
/// and woke late while the main thread was busy, and the resumed caller then
/// waited for the main thread again. On hardware this put a 300 ms cap at
/// 556 ms. Now the main thread can delay the caller only once, when the
/// caller resumes, and nothing can make the caller resume earlier than that.
@MainActor
final class BoundedParallelRace<Item: AnyObject> {
    typealias Result = BoundedRaceResult

    private let items: [Item]
    private let work: @MainActor (Item) async -> Bool

    init(items: [Item], work: @escaping @MainActor (Item) async -> Bool) {
        self.items = items
        self.work = work
    }

    /// Starts the work and returns when every item answers or `deadline`
    /// passes. Call it once.
    func run(until deadline: ContinuousClock.Instant) async -> Result {
        guard !items.isEmpty else {
            return Result(answeredCount: 0, acceptedCount: 0, timedOut: false, decidedAt: .now)
        }
        let gate = RaceGate(itemCount: items.count)
        return await withCheckedContinuation { continuation in
            gate.arm(continuation)
            let timer = Task.detached(priority: .userInitiated) {
                try? await Task.sleep(until: deadline, tolerance: .milliseconds(2), clock: .continuous)
                gate.finish(timedOut: true)
            }
            gate.attach(timer)
            for index in items.indices {
                Task { @MainActor in
                    let accepted = await self.work(self.items[index])
                    gate.itemDidAnswer(accepted: accepted)
                }
            }
        }
    }
}

/// The thread-safe state of one race. The timer calls it from a background
/// thread and the work calls it from the main actor.
private final class RaceGate: Sendable {
    private struct State: ~Copyable {
        var continuation: CheckedContinuation<BoundedRaceResult, Never>?
        var timer: Task<Void, Never>?
        var answeredCount = 0
        var acceptedCount = 0
        var isFinished = false
    }

    private let itemCount: Int
    private let state = Mutex(State())

    init(itemCount: Int) {
        self.itemCount = itemCount
    }

    func arm(_ continuation: CheckedContinuation<BoundedRaceResult, Never>) {
        state.withLock { $0.continuation = continuation }
    }

    /// Keeps the timer so an early finish can cancel it. A timer that arrives
    /// after the finish is cancelled at once.
    func attach(_ timer: Task<Void, Never>) {
        let isFinished = state.withLock { state in
            if !state.isFinished { state.timer = timer }
            return state.isFinished
        }
        if isFinished { timer.cancel() }
    }

    func itemDidAnswer(accepted: Bool) {
        let allAnswered = state.withLock { state in
            guard !state.isFinished else { return false }
            state.answeredCount += 1
            if accepted { state.acceptedCount += 1 }
            return state.answeredCount == itemCount
        }
        if allAnswered { finish(timedOut: false) }
    }

    func finish(timedOut: Bool) {
        let ending = state.withLock { state -> (CheckedContinuation<BoundedRaceResult, Never>, BoundedRaceResult, Task<Void, Never>?)? in
            guard !state.isFinished, let continuation = state.continuation else { return nil }
            state.isFinished = true
            state.continuation = nil
            let timer = state.timer
            state.timer = nil
            let result = BoundedRaceResult(
                answeredCount: state.answeredCount,
                acceptedCount: state.acceptedCount,
                timedOut: timedOut,
                decidedAt: .now
            )
            return (continuation, result, timer)
        }
        guard let (continuation, result, timer) = ending else { return }
        timer?.cancel()
        continuation.resume(returning: result)
    }
}
