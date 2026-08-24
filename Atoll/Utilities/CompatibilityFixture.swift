import Foundation

/// Defines the narrow Debug-only boundary for the local WebKit fixture.
enum CompatibilityFixture {
    static let launchArgument = "--atoll-compatibility-fixture"
    private static let processFailureScheme = "atoll-fixture"
    private static let processFailureHost = "web-content-process-failure"
    private static let loopbackHosts: Set<String> = ["localhost", "127.0.0.1"]
    private static let fixturePorts: Set<Int> = [8443, 8444]

    /// Release builds cannot enable the fixture, even when they receive the argument.
    nonisolated static func isEnabled(arguments: [String] = ProcessInfo.processInfo.arguments) -> Bool {
        #if DEBUG
        arguments.contains(launchArgument)
        #else
        false
        #endif
    }

    /// Permits the short-lived self-signed fixture certificate on loopback only.
    nonisolated static func allowsUntrustedServerCertificate(
        host: String,
        port: Int,
        authenticationMethod: String,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        isEnabled(arguments: arguments)
            && authenticationMethod == NSURLAuthenticationMethodServerTrust
            && loopbackHosts.contains(host.lowercased())
            && fixturePorts.contains(port)
    }

    /// Identifies the fixture route that exercises the normal recovery handler.
    nonisolated static func isProcessFailureURL(
        _ url: URL,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        isEnabled(arguments: arguments)
            && url.scheme?.lowercased() == processFailureScheme
            && url.host?.lowercased() == processFailureHost
            && (url.path.isEmpty || url.path == "/")
    }
}
