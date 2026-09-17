import Foundation
import WebKit
import os
import PaguroCore

@MainActor
final class NotificationMessageHandler: NSObject, WKScriptMessageHandler {
    let serviceID: UUID
    let presentationRouter: NotificationPresentationRouter
    private let serviceURLProvider: @MainActor () -> URL?
    private let probeEnabled: Bool
    private let probeServiceKind: String
    private var deduplicator = NotificationDeduplicator()

    init(
        serviceID: UUID,
        serviceURLProvider: @escaping @MainActor () -> URL?,
        presentationRouter: NotificationPresentationRouter,
        probeEnabled: Bool,
        probeServiceKind: String
    ) {
        self.serviceID = serviceID
        self.serviceURLProvider = serviceURLProvider
        self.presentationRouter = presentationRouter
        self.probeEnabled = probeEnabled
        self.probeServiceKind = probeServiceKind
        super.init()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "paguroNotification" else { return }
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

        #if DEBUG
        if probeEnabled {
            let source = payload.probe?.source.rawValue ?? "unavailable"
            let dataShape = payload.probe?.dataShape ?? "unavailable"
            let destination = payload.targetURL.isEmpty ? "absent" : "present"
            AppLogger.notifications.info(
                "Provider probe: service=\(self.probeServiceKind, privacy: .public) source=\(source, privacy: .public) data=\(dataShape, privacy: .public) destination=\(destination, privacy: .public)"
            )
        }
        #endif

        let event: NotificationEvent
        do {
            let targetURL = serviceURLProvider().flatMap {
                NotificationDestinationPolicy.approvedURL(
                    payload.targetURL,
                    serviceURL: $0
                )
            }
            if !payload.targetURL.isEmpty, targetURL == nil {
                AppLogger.notifications.warning(
                    "Notification trace \(traceID, privacy: .public): rejected unsafe destination"
                )
            }
            event = try NotificationEvent.normalize(
                id: eventID,
                serviceID: serviceID,
                payload: payload,
                targetURL: targetURL,
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
