import Foundation

/// The visible state of the notification island.
public enum NotificationIslandPhase: Equatable, Sendable {
    case hidden
    case collapsed
    case alert
    case expanded
    case dismissed
}

/// One action that can change the notification island.
public enum NotificationIslandAction: Equatable, Sendable {
    case showCollapsed
    case hide
    case receive(NotificationEvent)
    case expand
    case collapse
    case removeRecentEvent(UUID)
    case dismissCurrent
    case finishDismissal
    case stop
}

/// The current event and bounded pending queue for the notification island.
public struct NotificationIslandState: Equatable, Sendable {
    public let phase: NotificationIslandPhase
    public let currentEvent: NotificationEvent?
    public let queuedEvents: [NotificationEvent]
    public let recentEvents: [NotificationEvent]
    public let pendingCount: Int

    public static let hidden = NotificationIslandState(
        phase: .hidden,
        currentEvent: nil,
        queuedEvents: [],
        recentEvents: [],
        pendingCount: 0
    )

    fileprivate init(
        phase: NotificationIslandPhase,
        currentEvent: NotificationEvent?,
        queuedEvents: [NotificationEvent],
        recentEvents: [NotificationEvent],
        pendingCount: Int
    ) {
        self.phase = phase
        self.currentEvent = currentEvent
        self.queuedEvents = queuedEvents
        self.recentEvents = recentEvents
        self.pendingCount = max(0, pendingCount)
    }
}

/// Formats the bounded visual form of the island burst count.
public enum NotificationIslandCounterLabel {
    public static let maximumDisplayedCount = 99

    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > maximumDisplayedCount {
            return "\(maximumDisplayedCount)+"
        }
        return "+\(count)"
    }
}

/// Applies deterministic island state and queue rules.
public struct NotificationIslandReducer: Sendable {
    public static let defaultMaximumQueuedEvents = 4
    public static let defaultMaximumRecentEvents = 4

    public let maximumQueuedEvents: Int
    public let maximumRecentEvents: Int

    public init(
        maximumQueuedEvents: Int = defaultMaximumQueuedEvents,
        maximumRecentEvents: Int = defaultMaximumRecentEvents
    ) {
        self.maximumQueuedEvents = max(0, maximumQueuedEvents)
        self.maximumRecentEvents = max(0, maximumRecentEvents)
    }

    public func reduce(
        _ state: NotificationIslandState,
        action: NotificationIslandAction
    ) -> NotificationIslandState {
        switch action {
        case .showCollapsed:
            return showCollapsed(from: state)
        case .hide, .stop:
            return .hidden
        case let .receive(event):
            return receive(event, in: state)
        case .expand:
            return expand(state)
        case .collapse:
            return collapse(state)
        case let .removeRecentEvent(eventID):
            return removeRecentEvent(eventID, from: state)
        case .dismissCurrent:
            return dismissCurrent(in: state)
        case .finishDismissal:
            return finishDismissal(in: state)
        }
    }

    private func showCollapsed(
        from state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .hidden else { return state }
        return makeState(phase: .collapsed)
    }

    private func receive(
        _ event: NotificationEvent,
        in state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.currentEvent != nil else {
            let phase: NotificationIslandPhase = state.phase == .expanded
                ? .expanded
                : .alert
            return makeState(
                phase: phase,
                currentEvent: event,
                recentEvents: recent(event, after: state.recentEvents)
            )
        }

        return makeState(
            phase: state.phase,
            currentEvent: state.currentEvent,
            queuedEvents: queue(event, after: state.queuedEvents),
            recentEvents: recent(event, after: state.recentEvents),
            pendingCount: incremented(state.pendingCount)
        )
    }

    private func expand(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .collapsed || state.phase == .alert else {
            return state
        }
        return makeState(
            phase: .expanded,
            currentEvent: state.currentEvent,
            queuedEvents: state.queuedEvents,
            recentEvents: state.recentEvents,
            pendingCount: state.pendingCount
        )
    }

    private func collapse(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .expanded else { return state }
        return makeState(
            phase: state.currentEvent == nil ? .collapsed : .alert,
            currentEvent: state.currentEvent,
            queuedEvents: state.queuedEvents,
            recentEvents: state.recentEvents,
            pendingCount: state.pendingCount
        )
    }

    private func dismissCurrent(
        in state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .alert || state.phase == .expanded else {
            return state
        }
        guard state.currentEvent != nil else {
            return makeState(
                phase: .collapsed,
                recentEvents: state.recentEvents
            )
        }
        return makeState(
            phase: .dismissed,
            currentEvent: state.currentEvent,
            queuedEvents: state.queuedEvents,
            recentEvents: state.recentEvents,
            pendingCount: state.pendingCount
        )
    }

    private func removeRecentEvent(
        _ eventID: UUID,
        from state: NotificationIslandState
    ) -> NotificationIslandState {
        let queuedEvents = state.queuedEvents.filter { $0.id != eventID }
        let removedPendingCount = state.queuedEvents.count - queuedEvents.count
        return makeState(
            phase: state.phase,
            currentEvent: state.currentEvent,
            queuedEvents: queuedEvents,
            recentEvents: state.recentEvents.filter { $0.id != eventID },
            pendingCount: max(0, state.pendingCount - removedPendingCount)
        )
    }

    private func finishDismissal(
        in state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .dismissed else { return state }
        guard let nextEvent = state.queuedEvents.first else {
            return makeState(
                phase: .collapsed,
                recentEvents: state.recentEvents
            )
        }
        return makeState(
            phase: .alert,
            currentEvent: nextEvent,
            queuedEvents: Array(state.queuedEvents.dropFirst()),
            recentEvents: state.recentEvents,
            pendingCount: max(0, state.queuedEvents.count - 1)
        )
    }

    private func queue(
        _ event: NotificationEvent,
        after existingEvents: [NotificationEvent]
    ) -> [NotificationEvent] {
        guard maximumQueuedEvents > 0 else { return [] }
        return Array(([event] + existingEvents).prefix(maximumQueuedEvents))
    }

    private func recent(
        _ event: NotificationEvent,
        after existingEvents: [NotificationEvent]
    ) -> [NotificationEvent] {
        guard maximumRecentEvents > 0 else { return [] }

        let olderEvents = existingEvents.filter { $0.id != event.id }
        return Array(([event] + olderEvents).prefix(maximumRecentEvents))
    }

    private func makeState(
        phase: NotificationIslandPhase,
        currentEvent: NotificationEvent? = nil,
        queuedEvents: [NotificationEvent] = [],
        recentEvents: [NotificationEvent] = [],
        pendingCount: Int = 0
    ) -> NotificationIslandState {
        NotificationIslandState(
            phase: phase,
            currentEvent: currentEvent,
            queuedEvents: queuedEvents,
            recentEvents: recentEvents,
            pendingCount: pendingCount
        )
    }

    private func incremented(_ count: Int) -> Int {
        count == Int.max ? Int.max : count + 1
    }
}
