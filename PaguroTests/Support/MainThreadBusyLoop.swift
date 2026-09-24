import Foundation

/// Keeps the main actor busy with blocks of synchronous work, and yields
/// between the blocks so other main-actor jobs can run in turn. A test uses it
/// to model a quit while pages and AppKit keep the main thread occupied.
@MainActor
final class MainThreadBusyLoop {
    private let blockLength: Duration
    private var task: Task<Void, Never>?

    init(blockLength: Duration) {
        self.blockLength = blockLength
    }

    func start() {
        let blockLength = blockLength
        task = Task { @MainActor in
            let clock = ContinuousClock()
            while !Task.isCancelled {
                let end = clock.now + blockLength
                while clock.now < end {}
                await Task.yield()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
