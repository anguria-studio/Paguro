import Foundation
import Network

/// Lightweight wrapper around NWPathMonitor exposing a SwiftUI-observable
/// `isOnline` flag. `ContentView` reads it to show the offline banner;
/// `AppState` uses `onChange` to suspend polling while the network is
/// unreachable and to resume it on reconnect.
@MainActor
@Observable
final class NetworkMonitor {
    /// Defaults to `true` and `onChange` fires only on an actual transition, so
    /// there is no initial-state callback. That suits the current consumers
    /// (AppState resumes polling on reconnect; the banner reads `isOnline`
    /// directly) — a device that launches offline still shows the banner from
    /// this default. A future consumer that needs an authoritative first value
    /// should emit the initial path status once at start.
    private(set) var isOnline: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "com.tommasolaterza.Atoll.NetworkMonitor")
    private var isStopped = false

    /// Callback fired whenever connectivity toggles. Lets `AppState`
    /// pause/resume polling without polling the `isOnline` flag itself.
    var onChange: ((Bool) -> Void)?

    init() {
        self.monitor = NWPathMonitor()
        self.monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard self.isOnline != online else { return }
                self.isOnline = online
                self.onChange?(online)
            }
        }
        self.monitor.start(queue: queue)
    }

    deinit {
        monitor.cancel()
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        onChange = nil
        monitor.cancel()
    }
}
