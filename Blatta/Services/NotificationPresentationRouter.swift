import BlattaCore
import Foundation

/// A destination that can present one normalized notification event.
@MainActor
protocol NotificationEventPresenting: AnyObject {
    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    )
}

/// Applies presentation policy and dispatches one event to each allowed route.
@MainActor
final class NotificationPresentationRouter {
    private let systemPresenter: any NotificationEventPresenting
    private let isLockedCheck: @MainActor () -> Bool
    private let islandPresenter: (any NotificationEventPresenting)?
    private let isMutedCheck: @MainActor (UUID) -> Bool
    private let isSystemEnabledCheck: @MainActor (UUID) -> Bool
    private let isIslandEnabledCheck: @MainActor (UUID) -> Bool
    private let isIslandAvailableCheck: @MainActor () -> Bool
    private let isDoNotDisturbCheck: @MainActor () -> Bool

    init(
        systemPresenter: any NotificationEventPresenting,
        isLockedCheck: @escaping @MainActor () -> Bool = { false },
        islandPresenter: (any NotificationEventPresenting)? = nil,
        isMutedCheck: @escaping @MainActor (UUID) -> Bool,
        isSystemEnabledCheck: @escaping @MainActor (UUID) -> Bool,
        isIslandEnabledCheck: @escaping @MainActor (UUID) -> Bool = { _ in false },
        isIslandAvailableCheck: @escaping @MainActor () -> Bool = { true },
        isDoNotDisturbCheck: @escaping @MainActor () -> Bool
    ) {
        self.systemPresenter = systemPresenter
        self.isLockedCheck = isLockedCheck
        self.islandPresenter = islandPresenter
        self.isMutedCheck = isMutedCheck
        self.isSystemEnabledCheck = isSystemEnabledCheck
        self.isIslandEnabledCheck = isIslandEnabledCheck
        self.isIslandAvailableCheck = isIslandAvailableCheck
        self.isDoNotDisturbCheck = isDoNotDisturbCheck
    }

    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    ) {
        let wantsIsland = isIslandEnabledCheck(event.serviceID)
        let islandIsAvailable = islandPresenter != nil
            && isIslandAvailableCheck()
        if wantsIsland, !islandIsAvailable {
            AppLogger.notifications.warning(
                "Notification trace \(traceID, privacy: .public): island unavailable; using system fallback"
            )
        }

        let plan = NotificationPresentationPolicy.plan(
            for: NotificationPresentationOptions(
                isLocked: isLockedCheck(),
                isMuted: isMutedCheck(event.serviceID),
                isDoNotDisturbActive: isDoNotDisturbCheck(),
                isSystemNotificationEnabled: isSystemEnabledCheck(event.serviceID),
                isIslandEnabled: wantsIsland,
                isIslandAvailable: islandIsAvailable
            )
        )

        guard !plan.routes.isEmpty else {
            let reason = plan.suppressionReason?.rawValue ?? "unknown"
            AppLogger.notifications.info(
                "Notification trace \(traceID, privacy: .public): suppressed by presentation policy reason=\(reason, privacy: .public)"
            )
            return
        }

        for route in plan.routes {
            switch route {
            case .systemNotification:
                systemPresenter.present(
                    event: event,
                    requestID: requestID,
                    traceID: traceID
                )
            case .island:
                islandPresenter?.present(
                    event: event,
                    requestID: requestID,
                    traceID: traceID
                )
            }
        }
    }
}
