import Foundation

/// One normalized notification event from an accepted service signal.
public struct NotificationEvent: Equatable, Sendable {
    public let id: UUID
    public let serviceID: UUID
    public let source: NotificationEventSource
    public let title: String
    public let body: String?
    public let tag: String?
    public let targetURL: URL?
    public let receivedAt: Date

    /// Creates an event from a validated page notification signal.
    public static func normalize(
        id: UUID,
        serviceID: UUID,
        payload: NotificationPayload,
        targetURL: URL? = nil,
        receivedAt: Date
    ) throws -> NotificationEvent {
        try normalize(
            id: id,
            serviceID: serviceID,
            source: .pageNotification,
            title: payload.title,
            body: payload.body,
            tag: payload.tag,
            targetURL: targetURL,
            receivedAt: receivedAt
        )
    }

    /// Creates one event shape for all accepted signal sources.
    public static func normalize(
        id: UUID,
        serviceID: UUID,
        source: NotificationEventSource,
        title: String,
        body: String? = nil,
        tag: String? = nil,
        targetURL: URL? = nil,
        receivedAt: Date
    ) throws -> NotificationEvent {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw NotificationEventNormalizationError.emptyTitle
        }

        var normalizedBody = nonEmptyTrimmed(body)
        if normalizedBody == normalizedTitle {
            normalizedBody = nil
        }

        return NotificationEvent(
            id: id,
            serviceID: serviceID,
            source: source,
            title: normalizedTitle,
            body: normalizedBody,
            tag: nonEmptyTrimmed(tag),
            targetURL: targetURL,
            receivedAt: receivedAt
        )
    }

    public var deduplicationKey: NotificationDeduplicationKey {
        NotificationDeduplicationKey(
            serviceID: serviceID,
            tag: tag,
            title: title,
            body: body
        )
    }

    private init(
        id: UUID,
        serviceID: UUID,
        source: NotificationEventSource,
        title: String,
        body: String?,
        tag: String?,
        targetURL: URL?,
        receivedAt: Date
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

    private static func nonEmptyTrimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The detector that produced a notification event.
public enum NotificationEventSource: String, Equatable, Sendable {
    case pageNotification
    case documentBadge
    case serviceRecipe
}

/// Why a validated signal could not become a notification event.
public enum NotificationEventNormalizationError: Error, Equatable, Sendable {
    case emptyTitle
}

extension NotificationEventNormalizationError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyTitle:
            return "The notification title is empty."
        }
    }
}

/// A stable event identity for short-lived duplicate detection.
public struct NotificationDeduplicationKey: Hashable, Sendable {
    public let serviceID: UUID
    public let tag: String?
    public let title: String
    public let body: String?

    public init(
        serviceID: UUID,
        tag: String?,
        title: String,
        body: String?
    ) {
        self.serviceID = serviceID
        self.tag = tag
        self.title = title
        self.body = body
    }
}

/// Keeps a bounded, short-lived set of accepted notification events.
public struct NotificationDeduplicator: Sendable {
    public static let defaultWindow: TimeInterval = 5
    public static let defaultMaximumEntries = 256

    public let window: TimeInterval
    public let maximumEntries: Int

    private var acceptedEntries: [NotificationDeduplicationKey: AcceptedEntry] = [:]
    private var nextSequence = 0

    public init(
        window: TimeInterval = defaultWindow,
        maximumEntries: Int = defaultMaximumEntries
    ) {
        self.window = max(0, window)
        self.maximumEntries = max(1, maximumEntries)
    }

    /// Returns `true` once for an event key inside the duplicate time window.
    public mutating func accepts(_ event: NotificationEvent) -> Bool {
        guard window > 0 else { return true }

        removeExpiredEntries(relativeTo: event.receivedAt)
        let key = event.deduplicationKey

        if let previousEntry = acceptedEntries[key] {
            let elapsed = event.receivedAt.timeIntervalSince(previousEntry.date)
            if elapsed < window {
                return false
            }
        }

        makeSpaceIfNeeded()
        acceptedEntries[key] = AcceptedEntry(
            date: event.receivedAt,
            sequence: nextSequence
        )
        nextSequence += 1
        return true
    }

    private mutating func removeExpiredEntries(relativeTo date: Date) {
        acceptedEntries = acceptedEntries.filter { _, entry in
            date.timeIntervalSince(entry.date) < window
        }
    }

    private mutating func makeSpaceIfNeeded() {
        guard acceptedEntries.count >= maximumEntries,
              let oldestKey = acceptedEntries.min(by: { lhs, rhs in
                  if lhs.value.date == rhs.value.date {
                      return lhs.value.sequence < rhs.value.sequence
                  }
                  return lhs.value.date < rhs.value.date
              })?.key else {
            return
        }
        acceptedEntries.removeValue(forKey: oldestKey)
    }

    private struct AcceptedEntry: Sendable {
        let date: Date
        let sequence: Int
    }
}
