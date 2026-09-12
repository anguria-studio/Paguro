import AppKit
import PaguroCore
import UserNotifications
import XCTest
@testable import Paguro

/// `UNNotificationAttachment` moves its file into the notification store.
/// Every notification must get its own copy of the service icon, or only the
/// first notification per web-view lifetime carries the icon.
final class NotificationAttachmentTests: XCTestCase {
    @MainActor
    func testNotificationsUseTheFaviconFetchedAfterThePresenterWasCreated() throws {
        let service = ModelFixtures.service(label: "Notification Test", catalogID: nil)
        let presenter = NotificationPresenter(
            serviceLabel: service.label,
            serviceIconURLProvider: { NotificationAttachmentStore.prepareServiceIcon(for: service) }
        )
        let event = try NotificationEvent.normalize(
            id: UUID(), serviceID: service.id,
            payload: NotificationPayload(title: "Hello", body: "Sample", tag: "test"),
            receivedAt: Date()
        )
        XCTAssertTrue(presenter.makeRequest(event: event, identifier: "before-fetch").content.attachments.isEmpty)

        service.fetchedIconData = try Data(contentsOf: makeIconURL())
        let storedIcon = try XCTUnwrap(NotificationAttachmentStore.prepareServiceIcon(for: service))
        addTeardownBlock { try? FileManager.default.removeItem(at: storedIcon) }
        for index in 1...2 {
            XCTAssertEqual(
                presenter.makeRequest(event: event, identifier: "after-fetch-\(index)").content.attachments.count,
                1, "New notifications use the fetched favicon without recreating the presenter"
            )
        }

        service.fetchedIconData = nil
        XCTAssertTrue(presenter.makeRequest(event: event, identifier: "after-removal").content.attachments.isEmpty)
    }

    @MainActor
    private func makeIconURL() throws -> URL {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.systemTeal.setFill()
            rect.fill()
            return true
        }
        let png = try ServiceIconImageProcessor.normalizedPNG(from: image)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("paguro-attachment-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let iconURL = directory.appendingPathComponent("icon.png")
        try png.write(to: iconURL)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return iconURL
    }

    private func makeContent(iconURL: URL) throws -> UNMutableNotificationContent {
        let event = try NotificationEvent.normalize(
            id: UUID(),
            serviceID: UUID(),
            payload: NotificationPayload(title: "New message", body: "Body", tag: "tag"),
            receivedAt: Date()
        )
        return NativeNotificationContentBuilder.makeContent(
            event: event,
            serviceLabel: "Slack",
            serviceIconURL: iconURL
        )
    }

    @MainActor
    func testEveryNotificationCarriesTheIcon() throws {
        let iconURL = try makeIconURL()
        let first = try makeContent(iconURL: iconURL)
        let second = try makeContent(iconURL: iconURL)
        XCTAssertEqual(first.attachments.count, 1, "First notification carries the icon")
        XCTAssertEqual(second.attachments.count, 1, "Second notification still carries the icon")
    }

    @MainActor
    func testThePreparedIconFileSurvivesAttachment() throws {
        let iconURL = try makeIconURL()
        _ = try makeContent(iconURL: iconURL)
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
