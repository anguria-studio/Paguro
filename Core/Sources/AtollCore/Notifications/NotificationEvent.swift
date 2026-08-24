import Foundation

/// Describes how Atoll detected a notification event.
public enum NotificationSource: String, Codable, Sendable {
    case webNotification
    case documentTitle
    case serviceRecipe
}

/// Contains notification data after Atoll validates the web signal.
public struct NotificationEvent: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let serviceID: ServiceID
    public let source: NotificationSource
    public let title: String
    public let body: String?
    public let tag: String?
    public let targetURL: URL?
    public let receivedAt: Date

    public init(
        id: UUID = UUID(),
        serviceID: ServiceID,
        source: NotificationSource,
        title: String,
        body: String? = nil,
        tag: String? = nil,
        targetURL: URL? = nil,
        receivedAt: Date = Date()
    ) {
        self.id = id
        self.serviceID = serviceID
        self.source = source
        self.title = title
        self.body = body
        self.tag = tag
        self.targetURL = targetURL
        self.receivedAt = receivedAt
    }
}
