import Foundation

/// A notification click bound to one native service account.
public struct NotificationNavigationRequest: Equatable, Sendable {
    public let serviceID: UUID
    public let targetURLString: String?
    public let pageClickToken: UUID?

    public init(
        serviceID: UUID,
        targetURLString: String? = nil,
        pageClickToken: UUID? = nil
    ) {
        self.serviceID = serviceID
        self.targetURLString = targetURLString
        self.pageClickToken = pageClickToken
    }

    public init(
        serviceID: UUID,
        targetURL: URL?,
        pageClickToken: UUID? = nil
    ) {
        self.init(
            serviceID: serviceID,
            targetURLString: targetURL?.absoluteString,
            pageClickToken: pageClickToken
        )
    }
}

/// Approves notification destinations without loading them.
public enum NotificationDestinationPolicy {
    public static let maximumURLBytes = NotificationPayload.maximumTargetURLBytes

    /// Resolves an optional destination and keeps it inside its service.
    public static func approvedURL(
        _ rawValue: String?,
        serviceURL: URL
    ) -> URL? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value.utf8.count <= maximumURLBytes,
              !value.unicodeScalars.contains(where: {
                  $0.properties.generalCategory == .control
              }),
              let serviceHost = serviceURL.host,
              let resolvedURL = URL(string: value, relativeTo: serviceURL)?.absoluteURL,
              resolvedURL.absoluteString.utf8.count <= maximumURLBytes,
              let components = URLComponents(
                  url: resolvedURL,
                  resolvingAgainstBaseURL: true
              ),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let targetHost = components.host,
              WebRoutingPolicy.belongsToService(
                  targetHost,
                  serviceHost: serviceHost
              ) else {
            return nil
        }
        return components.url?.absoluteURL
    }
}
