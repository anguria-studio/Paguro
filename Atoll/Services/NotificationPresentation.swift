import AppKit
import AtollCore
import Foundation
import UserNotifications

/// Prepares the service image that macOS can show with a notification.
/// macOS keeps the Atoll app icon as the sender identity.
@MainActor
enum NotificationAttachmentStore {
    static func prepareServiceIcon(for service: ServiceInstance) -> URL? {
        do {
            guard let pngData = try normalizedIconData(for: service) else { return nil }
            let directory = try attachmentDirectory()
            let fileURL = directory
                .appendingPathComponent(service.id.uuidString, isDirectory: false)
                .appendingPathExtension("png")

            if (try? Data(contentsOf: fileURL)) != pngData {
                try pngData.write(to: fileURL, options: .atomic)
            }
            return fileURL
        } catch {
            AppLogger.notifications.warning(
                "Could not prepare the service icon for notification presentation: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private static func normalizedIconData(for service: ServiceInstance) throws -> Data? {
        if let data = service.customIconData {
            return try ServiceIconImageProcessor.normalizedPNG(from: data)
        }

        if let catalogID = service.catalogEntryID,
           let image = NSImage(named: "brand-\(catalogID)") {
            return try ServiceIconImageProcessor.normalizedPNG(from: image)
        }

        guard let data = service.fetchedIconData else { return nil }
        return try ServiceIconImageProcessor.normalizedPNG(from: data)
    }

    /// Copies a prepared icon to a unique file for one notification.
    ///
    /// `UNNotificationAttachment` moves its file into the notification store.
    /// An attachment built from the shared per-service file would take that
    /// file with it, and every later notification would lose its icon.
    nonisolated static func disposableCopy(of iconURL: URL) throws -> URL {
        let copyURL = try attachmentDirectory()
            .appendingPathComponent(UUID().uuidString, isDirectory: false)
            .appendingPathExtension("png")
        try FileManager.default.copyItem(at: iconURL, to: copyURL)
        return copyURL
    }

    nonisolated private static func attachmentDirectory() throws -> URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = caches.appendingPathComponent("NotificationAttachments", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

enum NativeNotificationContentBuilder {
    static func makeContent(
        event: NotificationEvent,
        serviceLabel: String,
        serviceIconURL: URL?
    ) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.subtitle = serviceLabel
        content.body = event.body ?? ""
        content.userInfo = ["serviceID": event.serviceID.uuidString]
        content.sound = .default

        // Each notification gets its own copy: the attachment consumes its file.
        if let serviceIconURL,
           let copyURL = try? NotificationAttachmentStore.disposableCopy(of: serviceIconURL) {
            do {
                let attachment = try UNNotificationAttachment(
                    identifier: "service-icon",
                    url: copyURL
                )
                content.attachments = [attachment]
            } catch {
                try? FileManager.default.removeItem(at: copyURL)
            }
        }

        return content
    }
}
