import Foundation
import WebKit
import os
import BlattaCore

@MainActor
final class NotificationMessageHandler: NSObject, WKScriptMessageHandler {
    let serviceID: UUID
    let presentationRouter: NotificationPresentationRouter
    private var deduplicator = NotificationDeduplicator()

    init(
        serviceID: UUID,
        presentationRouter: NotificationPresentationRouter
    ) {
        self.serviceID = serviceID
        self.presentationRouter = presentationRouter
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "blattaNotification" else { return }
        let eventID = UUID()
        let requestID = eventID.uuidString
        let traceID = String(requestID.prefix(8)).lowercased()

        let frame = message.frameInfo
        let frameKind: String
        if frame.isMainFrame {
            frameKind = "main"
        } else {
            // The script also runs in subframes. The Core rule prevents a
            // cross-origin frame from spoofing its service's notifications.
            let origin = frame.securityOrigin
            let mainOrigin = message.webView?.url.flatMap { url -> NotificationOrigin? in
                guard let scheme = url.scheme, let host = url.host else { return nil }
                return NotificationOrigin(scheme: scheme, host: host, port: url.port)
            }
            let frameOrigin = NotificationOrigin(
                scheme: origin.protocol,
                host: origin.host,
                port: origin.port
            )
            guard NotificationOriginPolicy.accepts(
                isMainFrame: false,
                mainOrigin: mainOrigin,
                frameOrigin: frameOrigin
            ) else {
                AppLogger.notifications.warning(
                    "Notification trace \(traceID, privacy: .public): rejected cross-origin frame"
                )
                return
            }
            frameKind = "same-origin"
        }

        AppLogger.notifications.info(
            "Notification trace \(traceID, privacy: .public): bridge accepted frame=\(frameKind, privacy: .public)"
        )

        guard let jsonString = message.body as? String else {
            AppLogger.notifications.warning(
                "Notification trace \(traceID, privacy: .public): rejected non-string payload"
            )
            return
        }

        let payload: NotificationPayload
        do {
            payload = try NotificationPayload.decode(jsonString)
        } catch {
            AppLogger.notifications.error(
                "Notification trace \(traceID, privacy: .public): payload decode failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        let event: NotificationEvent
        do {
            event = try NotificationEvent.normalize(
                id: eventID,
                serviceID: serviceID,
                payload: payload,
                receivedAt: Date()
            )
        } catch {
            AppLogger.notifications.error(
                "Notification trace \(traceID, privacy: .public): event normalization failed: \(error.localizedDescription, privacy: .public)"
            )
            return
        }

        guard deduplicator.accepts(event) else {
            AppLogger.notifications.info(
                "Notification trace \(traceID, privacy: .public): rejected recent duplicate"
            )
            return
        }

        presentationRouter.present(
            event: event,
            requestID: requestID,
            traceID: traceID
        )
    }
}
