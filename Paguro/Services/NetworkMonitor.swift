import Foundation
import Network

/// Lightweight wrapper around NWPathMonitor exposing a SwiftUI-observable
/// `isOnline` flag. `ContentView` reads it to show the offline banner;
/// `NotificationRuntime` uses `onChange` to suspend polling while the network is
/// unreachable and to resume it on reconnect.
@MainActor
@Observable
final class NetworkMonitor {
    /// Defaults to `true`. An initial offline path changes the value and shows
    /// the banner. An initial online path does not call `onChange`, because the
    /// value did not change. A future consumer that needs an initial online
    /// callback should receive the first path status separately.
    private(set) var isOnline: Bool = true

    private let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "studio.anguria.paguro.NetworkMonitor")
    private var isStopped = false

    /// Callback fired whenever connectivity toggles. Lets `NotificationRuntime`
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
