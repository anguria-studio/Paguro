import Foundation

/// The platform-neutral facts about one web navigation.
public struct NavigationRequestContext: Equatable, Sendable {
    public let url: URL?
    public let isLinkActivated: Bool
    public let shouldDownload: Bool
    public let hasCommandModifier: Bool
    public let targetsMainFrame: Bool
    public let currentHost: String?

    public init(
        url: URL?,
        isLinkActivated: Bool,
        shouldDownload: Bool,
        hasCommandModifier: Bool,
        targetsMainFrame: Bool,
        currentHost: String?
    ) {
        self.url = url
        self.isLinkActivated = isLinkActivated
        self.shouldDownload = shouldDownload
        self.hasCommandModifier = hasCommandModifier
        self.targetsMainFrame = targetsMainFrame
        self.currentHost = currentHost
    }
}

/// Where an external navigation must go.
public enum NavigationExternalRoute: Equatable, Sendable {
    case system
    case matchingServiceOrSystem
}

/// The complete deterministic decision for a web navigation.
public enum NavigationDecision: Equatable, Sendable {
    case allow
    case openExternally(NavigationExternalRoute)
    case download
    case cancel

    private static let webSchemes: Set<String> = [
        "http", "https", "about", "blob", "data",
    ]

    /// Classifies a navigation before WebKit or AppKit performs an action.
    public static func decide(_ request: NavigationRequestContext) -> NavigationDecision {
        guard let url = request.url else { return .cancel }

        if let scheme = url.scheme,
           !webSchemes.contains(scheme.lowercased()) {
            guard request.isLinkActivated,
                  WebRoutingPolicy.isSafeForExternalOpen(url) else {
                return .cancel
            }
            return .openExternally(.system)
        }

        // A server can mark a cross-service URL as a download. Keep this check
        // before Command-click and external service routing.
        if request.shouldDownload { return .download }

        if request.isLinkActivated, request.hasCommandModifier {
            guard WebRoutingPolicy.isSafeForExternalOpen(url) else { return .cancel }
            return .openExternally(.system)
        }

        if request.isLinkActivated,
           request.targetsMainFrame,
           let currentHost = request.currentHost,
           let targetHost = url.host,
           !WebRoutingPolicy.belongsToService(targetHost, serviceHost: currentHost),
           !WebRoutingPolicy.isAuthenticationHost(targetHost) {
            return .openExternally(.matchingServiceOrSystem)
        }

        return .allow
    }
}
