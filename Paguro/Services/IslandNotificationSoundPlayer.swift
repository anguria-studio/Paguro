import Foundation
import UserNotifications

@MainActor
protocol IslandNotificationSoundDelivering: Sendable {
    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void)
    func remove(identifier: String)
}

private struct SystemIslandNotificationSoundCenter: IslandNotificationSoundDelivering {
    func add(_ request: UNNotificationRequest, completion: @escaping @Sendable (Error?) -> Void) {
        UNUserNotificationCenter.current().add(request, withCompletionHandler: completion)
    }

    func remove(identifier: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }
}

/// Uses the notification sound, which differs from the selected system alert.
@MainActor
final class IslandNotificationSoundPlayer {
    nonisolated private static let identifierPrefix = "paguro.island-sound."
    private let center: any IslandNotificationSoundDelivering
    private var identifier = identifierPrefix + UUID().uuidString
    private var hasSubmitted = false
    private var hasStopped = false

    init(center: (any IslandNotificationSoundDelivering)? = nil) {
        self.center = center ?? SystemIslandNotificationSoundCenter()
    }

    nonisolated static func isSoundRequest(_ request: UNNotificationRequest) -> Bool {
        request.identifier.hasPrefix(identifierPrefix)
    }

    func play() {
        guard !hasStopped else { return }
        let content = UNMutableNotificationContent()
        // No title, body, badge, or service data: macOS plays audio without
        // creating a banner or a Notification Center entry, even in background.
        content.sound = .default
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        let identifier = identifier
        let center = center
        hasSubmitted = true
        center.add(request) { [weak self] error in
            if let error {
                AppLogger.notifications.error("Island notification sound failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor [weak self] in
                // A request can be accepted after lock or quit cancelled it.
                // The next session has a new ID, so this cannot cancel its sound.
                if self?.identifier != identifier {
                    center.remove(identifier: identifier)
                }
            }
        }
    }

    func cancel() {
        let previousIdentifier = identifier
        identifier = Self.identifierPrefix + UUID().uuidString
        if hasSubmitted { center.remove(identifier: previousIdentifier) }
        hasSubmitted = false
    }

    func stop() {
        hasStopped = true
        cancel()
    }
}
