import Foundation
import XCTest
@testable import AtollCore

final class NotificationEventTests: XCTestCase {
    func testCodableRoundTripPreservesEvent() throws {
        let event = NotificationEvent(
            id: UUID(uuidString: "37A62093-9E46-4B35-9424-06DD2A1010C3")!,
            serviceID: ServiceID(
                rawValue: UUID(uuidString: "A39473C2-EDE7-463B-86C8-21471EF15D77")!
            ),
            source: .webNotification,
            title: "New message",
            body: "Open the service to read the message.",
            tag: "message-42",
            targetURL: URL(string: "https://example.com/messages/42"),
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NotificationEvent.self, from: data)

        XCTAssertEqual(decoded, event)
    }

    func testNewServiceIDsAreDifferent() {
        XCTAssertNotEqual(ServiceID(), ServiceID())
    }
}
