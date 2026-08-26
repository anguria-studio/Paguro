import AppKit
import UserNotifications
import XCTest
@testable import Atoll

/// `UNNotificationAttachment` moves its file into the notification store.
/// Every notification must get its own copy of the service icon, or only the
/// first notification per web-view lifetime carries the icon.
final class NotificationAttachmentTests: XCTestCase {
    @MainActor
    private func makeIconURL() throws -> URL {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = try ServiceIconImageProcessor.normalizedPNG(from: image)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atoll-attachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let iconURL = directory.appendingPathComponent("icon.png")
        try png.write(to: iconURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return iconURL
    }

    private func makeContent(iconURL: URL) -> UNMutableNotificationContent {
        let payload = NotificationPayload(
            title: "New message",
            body: "Body",
            icon: "",
            tag: "tag",
            serviceID: UUID().uuidString
        )
        return NativeNotificationContentBuilder.makeContent(
            payload: payload,
            serviceID: UUID(),
            serviceLabel: "Slack",
            serviceIconURL: iconURL
        )
    }

    @MainActor
    func testEveryNotificationCarriesTheIcon() throws {
        let iconURL = try makeIconURL()
        let first = makeContent(iconURL: iconURL)
        let second = makeContent(iconURL: iconURL)
        XCTAssertEqual(first.attachments.count, 1, "First notification carries the icon")
        XCTAssertEqual(second.attachments.count, 1, "Second notification still carries the icon")
    }

    @MainActor
    func testThePreparedIconFileSurvivesAttachment() throws {
        let iconURL = try makeIconURL()
        _ = makeContent(iconURL: iconURL)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: iconURL.path),
            "The shared per-service icon must not be consumed by the attachment"
        )
    }

    @MainActor
    func testDisposableCopiesAreDistinctFiles() throws {
        let iconURL = try makeIconURL()
        let first = try NotificationAttachmentStore.disposableCopy(of: iconURL)
        let second = try NotificationAttachmentStore.disposableCopy(of: iconURL)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), try Data(contentsOf: iconURL))
    }
}
