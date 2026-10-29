import Foundation

public enum ExtensionRuntimeProfile: String, Codable, CaseIterable, Sendable {
    case standard
    case firefox

    /// The Firefox token is fixed so every surface reports the same value.
    /// Raise it with Firefox releases, because some sites warn about old browsers.
    public var applicationNameForUserAgent: String? {
        switch self {
        case .standard: nil
        case .firefox: "Firefox/143.0"
        }
    }

    /// Use WebKit's generated identity with the same suffix on every surface.
    public func customUserAgent(defaultValue: String) -> String? {
        self == .firefox ? nil : defaultValue
    }
}
