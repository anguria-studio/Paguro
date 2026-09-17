import Foundation

/// Enables privacy-limited notification diagnostics for provider testing.
enum NotificationProbeConfiguration {
    #if DEBUG
    static let launchArgument = "--paguro-notification-probe"
    #endif

    /// Release builds cannot enable the probe.
    nonisolated static func isEnabled(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        #if DEBUG
        arguments.contains(launchArgument)
        #else
        false
        #endif
    }
}
