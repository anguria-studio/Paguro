import PaguroCore
import Foundation
import UserNotifications

/// Builds and delivers native notifications from normalized events.
@MainActor
final class NotificationPresenter: NotificationEventPresenting {
    private let serviceLabel: String
    private let serviceIconURL: URL?
    private let center: UNUserNotificationCenter
    private let lockSnapshot: AtomicBool

    init(
        serviceLabel: String,
        serviceIconURL: URL?,
        center: UNUserNotificationCenter = .current(),
        lockSnapshot: AtomicBool = AtomicBool(false)
    ) {
        self.serviceLabel = serviceLabel
        self.serviceIconURL = serviceIconURL
        self.center = center
        self.lockSnapshot = lockSnapshot
    }

    func makeRequest(
        event: NotificationEvent,
        identifier: String
    ) -> UNNotificationRequest {
        let content = NativeNotificationContentBuilder.makeContent(
            event: event,
            serviceLabel: serviceLabel,
            serviceIconURL: serviceIconURL
        )
        return UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
    }

    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    ) {
        guard !lockSnapshot.value else { return }
        let request = makeRequest(event: event, identifier: requestID)

        #if DEBUG
        if CompatibilityFixture.isEnabled() {
            center.getNotificationSettings { settings in
                AppLogger.notifications.info(
                    "Notification trace \(traceID, privacy: .public): center settings authorization=\(settings.authorizationStatus.rawValue, privacy: .public) alerts=\(settings.alertSetting.rawValue, privacy: .public) sounds=\(settings.soundSetting.rawValue, privacy: .public)"
                )
            }
        }
        #endif

        let lockSnapshot = lockSnapshot
        let center = center
        center.add(request) { error in
            // A request accepted during a lock transition must not remain visible.
            if lockSnapshot.value {
                center.removePendingNotificationRequests(withIdentifiers: [requestID])
                center.removeDeliveredNotifications(withIdentifiers: [requestID])
            }
            if let error {
                AppLogger.notifications.error(
                    "Notification trace \(traceID, privacy: .public): center add failed: \(error.localizedDescription, privacy: .public)"
                )
            } else {
                AppLogger.notifications.info(
                    "Notification trace \(traceID, privacy: .public): center accepted request"
                )
            }
        }
    }
}
