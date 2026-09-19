import Foundation
import Network
import PaguroCore

/// Lightweight wrapper around NWPathMonitor exposing a SwiftUI-observable
/// `isOnline` flag. `ContentView` reads it for the offline card, and
/// `NotificationRuntime` uses `onChange` to suspend polling while the network is
/// unreachable and to resume it on reconnect.
@MainActor
@Observable
final class NetworkMonitor {
    /// Defaults to `true`. An initial offline path changes the value and shows
    /// the card. An initial online path does not call `onChange`, because the
    /// value did not change. A future consumer that needs an initial online
    /// callback should receive the first path status separately.
    private(set) var isOnline: Bool = true

    /// Whether the offline card has been put away for this loss of the
    /// connection. `OfflineNoticeState` in PaguroCore holds the rule.
    private var offlineNotice = OfflineNoticeState()

    private let monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "studio.anguria.paguro.NetworkMonitor")
    private var isStopped = false

    /// Callback fired whenever connectivity toggles. Lets `NotificationRuntime`
    /// pause/resume polling without polling the `isOnline` flag itself.
    var onChange: ((Bool) -> Void)?

    /// True while the offline card belongs on screen.
    var showsOfflineNotice: Bool {
        offlineNotice.showsNotice(isOnline: isOnline)
    }

    /// - Parameter monitorsPath: False builds a monitor that reads no real
    ///   network path, so a test can drive the transitions itself.
    init(monitorsPath: Bool = true) {
        guard monitorsPath else {
            monitor = nil
            return
        }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                self?.apply(isOnline: online)
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        monitor?.cancel()
    }

    /// Takes the offline card off the screen until the connection drops again.
    func dismissOfflineNotice() {
        offlineNotice.dismiss()
    }

    /// Applies a new path status.
    ///
    /// A status that repeats the current one changes nothing, so one loss of the
    /// connection raises the card one time.
    func apply(isOnline online: Bool) {
        guard !isStopped, isOnline != online else { return }
        isOnline = online
        offlineNotice.networkChanged(isOnline: online)
        onChange?(online)
    }

    func stop() {
        guard !isStopped else { return }
        isStopped = true
        onChange = nil
        monitor?.cancel()
    }
}
