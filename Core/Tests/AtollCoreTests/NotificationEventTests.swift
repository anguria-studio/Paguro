import Foundation
import Testing
@testable import AtollCore

struct NotificationEventTests {
    private let serviceID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let eventID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    private let receivedAt = Date(timeIntervalSince1970: 1_000)

    @Test
    func normalizesOptionalTextAndRemovesARepeatedBody() throws {
        let event = try NotificationEvent.normalize(
            id: eventID,
            serviceID: serviceID,
            source: .serviceRecipe,
            title: "  New message  ",
            body: "\nNew message\t",
            tag: "  conversation-1 ",
            receivedAt: receivedAt
        )

        #expect(event.title == "New message")
        #expect(event.body == nil)
        #expect(event.tag == "conversation-1")
        #expect(event.source == .serviceRecipe)
    }

    @Test
    func normalizesAValidatedPagePayload() throws {
        let event = try NotificationEvent.normalize(
            id: eventID,
            serviceID: serviceID,
            payload: NotificationPayload(
                title: "  New message ",
                body: " Body ",
                tag: " "
            ),
            receivedAt: receivedAt
        )

        #expect(event.title == "New message")
        #expect(event.body == "Body")
        #expect(event.tag == nil)
        #expect(event.source == .pageNotification)
    }

    @Test
    func rejectsAnEmptyTitle() {
        #expect(throws: NotificationEventNormalizationError.emptyTitle) {
            try NotificationEvent.normalize(
                id: eventID,
                serviceID: serviceID,
                source: .pageNotification,
                title: " \n ",
                receivedAt: receivedAt
            )
        }
    }

    @Test
    func deduplicationKeyIgnoresEventMetadataAndDetectorSource() throws {
        let first = try event(
            id: eventID,
            source: .pageNotification,
            receivedAt: receivedAt
        )
        let second = try event(
            id: UUID(),
            source: .serviceRecipe,
            receivedAt: receivedAt.addingTimeInterval(1)
        )

        #expect(first.deduplicationKey == second.deduplicationKey)
    }

    @Test
    func deduplicatorRejectsOnlyTheSameRecentContent() throws {
        var deduplicator = NotificationDeduplicator(window: 5)
        let first = try event(receivedAt: receivedAt)
        let duplicate = try event(receivedAt: receivedAt.addingTimeInterval(4.99))
        let changedBody = try event(
            body: "Different body",
            receivedAt: receivedAt.addingTimeInterval(1)
        )
        let boundary = try event(receivedAt: receivedAt.addingTimeInterval(5))

        let acceptedFirst = deduplicator.accepts(first)
        let acceptedDuplicate = deduplicator.accepts(duplicate)
        let acceptedChangedBody = deduplicator.accepts(changedBody)
        let acceptedBoundary = deduplicator.accepts(boundary)

        #expect(acceptedFirst)
        #expect(!acceptedDuplicate)
        #expect(acceptedChangedBody)
        #expect(acceptedBoundary)
    }

    @Test
    func deduplicatorKeepsServiceAccountsSeparate() throws {
        var deduplicator = NotificationDeduplicator(window: 5)
        let first = try event(receivedAt: receivedAt)
        let second = try event(
            serviceID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            receivedAt: receivedAt.addingTimeInterval(1)
        )

        let acceptedFirst = deduplicator.accepts(first)
        let acceptedSecond = deduplicator.accepts(second)

        #expect(acceptedFirst)
        #expect(acceptedSecond)
    }

    @Test
    func zeroWindowDisablesDeduplication() throws {
        var deduplicator = NotificationDeduplicator(window: 0)
        let notification = try event(receivedAt: receivedAt)

        let acceptedFirst = deduplicator.accepts(notification)
        let acceptedSecond = deduplicator.accepts(notification)

        #expect(acceptedFirst)
        #expect(acceptedSecond)
    }

    @Test
    func entryLimitEvictsTheOldestAcceptedKey() throws {
        var deduplicator = NotificationDeduplicator(window: 60, maximumEntries: 2)
        let first = try event(title: "First", receivedAt: receivedAt)
        let second = try event(
            title: "Second",
            receivedAt: receivedAt.addingTimeInterval(1)
        )
        let third = try event(
            title: "Third",
            receivedAt: receivedAt.addingTimeInterval(2)
        )
        let repeatedFirst = try event(
            title: "First",
            receivedAt: receivedAt.addingTimeInterval(3)
        )

        let acceptedFirst = deduplicator.accepts(first)
        let acceptedSecond = deduplicator.accepts(second)
        let acceptedThird = deduplicator.accepts(third)
        let acceptedRepeatedFirst = deduplicator.accepts(repeatedFirst)

        #expect(acceptedFirst)
        #expect(acceptedSecond)
        #expect(acceptedThird)
        #expect(acceptedRepeatedFirst)
    }

    private func event(
        id: UUID = UUID(),
        serviceID: UUID? = nil,
        source: NotificationEventSource = .pageNotification,
        title: String = "New message",
        body: String? = "Body",
        tag: String? = "conversation-1",
        receivedAt: Date
    ) throws -> NotificationEvent {
        try NotificationEvent.normalize(
            id: id,
            serviceID: serviceID ?? self.serviceID,
            source: source,
            title: title,
            body: body,
            tag: tag,
            receivedAt: receivedAt
        )
    }
}
