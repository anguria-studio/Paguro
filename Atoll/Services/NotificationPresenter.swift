import AtollCore
import Foundation
import UserNotifications

/// Builds and delivers native notifications from validated page payloads.
@MainActor
final class NotificationPresenter {
    private let serviceID: UUID
    private let serviceLabel: String
    private let serviceIconURL: URL?
    private let center: UNUserNotificationCenter

    init(
        serviceID: UUID,
        serviceLabel: String,
        serviceIconURL: URL?,
        center: UNUserNotificationCenter = .current()
    ) {
        self.serviceID = serviceID
        self.serviceLabel = serviceLabel
        self.serviceIconURL = serviceIconURL
        self.center = center
    }

    func makeRequest(
        payload: NotificationPayload,
        identifier: String
    ) -> UNNotificationRequest {
        let content = NativeNotificationContentBuilder.makeContent(
            payload: payload,
            serviceID: serviceID,
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
        payload: NotificationPayload,
        requestID: String,
        traceID: String
    ) {
        let request = makeRequest(payload: payload, identifier: requestID)

        #if DEBUG
        if CompatibilityFixture.isEnabled() {
            center.getNotificationSettings { settings in
                AppLogger.notifications.info(
                    "Notification trace \(traceID, privacy: .public): center settings authorization=\(settings.authorizationStatus.rawValue, privacy: .public) alerts=\(settings.alertSetting.rawValue, privacy: .public) sounds=\(settings.soundSetting.rawValue, privacy: .public)"
                )
            }
        }
        #endif

        center.add(request) { error in
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
