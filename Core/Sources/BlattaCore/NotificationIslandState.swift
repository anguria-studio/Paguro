import Foundation

/// The visible state of the notification island.
public enum NotificationIslandPhase: Equatable, Sendable {
    case hidden
    case collapsed
    case peek
    case alert
    case expanded
    case dismissed
}

/// One action that can change the notification island.
public enum NotificationIslandAction: Equatable, Sendable {
    case showCollapsed
    case suspendPresentation
    case hide
    case receive(NotificationEvent)
    case beginPeek
    case endPeek
    case expand
    case collapse
    case expireCurrent
    case dismissEvent(UUID)
    case dismissEvents(serviceID: UUID)
    case dismissAll
    case finishDismissal
    case stop
}

/// The current preview and in-memory history for the notification island.
public struct NotificationIslandState: Equatable, Sendable {
    public let phase: NotificationIslandPhase
    public let currentEvent: NotificationEvent?
    public let recentEvents: [NotificationEvent]
    public let unreviewedCount: Int

    public static let hidden = NotificationIslandState(
        phase: .hidden,
        currentEvent: nil,
        recentEvents: [],
        unreviewedCount: 0
    )

    fileprivate init(
        phase: NotificationIslandPhase,
        currentEvent: NotificationEvent?,
        recentEvents: [NotificationEvent],
        unreviewedCount: Int
    ) {
        self.phase = phase
        self.currentEvent = currentEvent
        self.recentEvents = recentEvents
        self.unreviewedCount = max(0, unreviewedCount)
    }
}

/// Formats the compact visual form of the island unreviewed count.
public enum NotificationIslandCounterLabel {
    public static let maximumDisplayedCount = 99

    public static func text(for count: Int) -> String? {
        guard count > 0 else { return nil }
        if count > maximumDisplayedCount {
            return "\(maximumDisplayedCount)+"
        }
        return "\(count)"
    }
}

/// Applies deterministic island state and history rules.
public struct NotificationIslandReducer: Sendable {
    public init() {}

    public func reduce(
        _ state: NotificationIslandState,
        action: NotificationIslandAction
    ) -> NotificationIslandState {
        switch action {
        case .showCollapsed:
            return showCollapsed(from: state)
        case .suspendPresentation:
            guard state.phase != .hidden else { return state }
            return makeState(
                phase: .collapsed,
                recentEvents: state.recentEvents,
                unreviewedCount: state.unreviewedCount
            )
        case .hide, .stop:
            return .hidden
        case let .receive(event):
            return receive(event, in: state)
        case .beginPeek:
            return beginPeek(state)
        case .endPeek:
            return endPeek(state)
        case .expand:
            return expand(state)
        case .collapse:
            return collapse(state)
        case .expireCurrent:
            return expireCurrent(in: state)
        case let .dismissEvent(eventID):
            return dismissEvent(eventID, from: state)
        case let .dismissEvents(serviceID):
            return dismissEvents(of: serviceID, from: state)
        case .dismissAll:
            return dismissAll(from: state)
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
        let phase: NotificationIslandPhase
        switch state.phase {
        case .peek:
            phase = .peek
        case .expanded:
            phase = .expanded
        case .hidden, .collapsed, .alert, .dismissed:
            phase = .alert
        }

        return makeState(
            phase: phase,
            currentEvent: event,
            recentEvents: recent(event, after: state.recentEvents),
            unreviewedCount: incremented(state.unreviewedCount)
        )
    }

    private func beginPeek(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .collapsed || state.phase == .alert,
              !state.recentEvents.isEmpty else { return state }
        return makeState(
            phase: .peek,
            currentEvent: state.currentEvent,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func endPeek(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .peek else { return state }
        return makeState(
            phase: state.currentEvent == nil ? .collapsed : .alert,
            currentEvent: state.currentEvent,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func expand(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        switch state.phase {
        case .collapsed, .peek, .alert:
            guard !state.recentEvents.isEmpty else { return state }
        case .hidden, .expanded, .dismissed:
            return state
        }
        return makeState(
            phase: .expanded,
            currentEvent: state.currentEvent,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func collapse(
        _ state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .expanded else { return state }
        return makeState(
            phase: state.currentEvent == nil ? .collapsed : .alert,
            currentEvent: state.currentEvent,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func expireCurrent(
        in state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .alert, state.currentEvent != nil else {
            return state
        }
        return makeState(
            phase: .dismissed,
            currentEvent: state.currentEvent,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func dismissEvent(
        _ eventID: UUID,
        from state: NotificationIslandState
    ) -> NotificationIslandState {
        let isCurrent = state.currentEvent?.id == eventID
        let isRecent = state.recentEvents.contains { $0.id == eventID }
        guard isCurrent || isRecent else { return state }

        let recentEvents = state.recentEvents.filter { $0.id != eventID }
        let unreviewedCount = recentEvents.isEmpty
            ? 0
            : max(0, state.unreviewedCount - 1)

        if isCurrent, state.phase == .alert {
            return makeState(
                phase: .dismissed,
                currentEvent: state.currentEvent,
                recentEvents: recentEvents,
                unreviewedCount: unreviewedCount
            )
        }

        let phase: NotificationIslandPhase
        if recentEvents.isEmpty {
            phase = .collapsed
        } else {
            phase = state.phase
        }
        return makeState(
            phase: phase,
            currentEvent: isCurrent ? nil : state.currentEvent,
            recentEvents: recentEvents,
            unreviewedCount: unreviewedCount
        )
    }

    /// Removes every event of one service account.
    ///
    /// The user reads that conversation in Blatta, so its island events are no
    /// longer new. The rule keeps the exit transition of a compact alert that
    /// belongs to the same service account.
    private func dismissEvents(
        of serviceID: UUID,
        from state: NotificationIslandState
    ) -> NotificationIslandState {
        let isCurrent = state.currentEvent?.serviceID == serviceID
        let recentEvents = state.recentEvents.filter {
            $0.serviceID != serviceID
        }
        let removedCount = state.recentEvents.count - recentEvents.count
        guard isCurrent || removedCount > 0 else { return state }

        let unreviewedCount = recentEvents.isEmpty
            ? 0
            : max(0, state.unreviewedCount - removedCount)

        if isCurrent, state.phase == .alert || state.phase == .dismissed {
            return makeState(
                phase: .dismissed,
                currentEvent: state.currentEvent,
                recentEvents: recentEvents,
                unreviewedCount: unreviewedCount
            )
        }

        return makeState(
            phase: recentEvents.isEmpty ? .collapsed : state.phase,
            currentEvent: isCurrent ? nil : state.currentEvent,
            recentEvents: recentEvents,
            unreviewedCount: unreviewedCount
        )
    }

    private func dismissAll(
        from state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase != .hidden else { return state }
        return makeState(phase: .collapsed)
    }

    private func finishDismissal(
        in state: NotificationIslandState
    ) -> NotificationIslandState {
        guard state.phase == .dismissed else { return state }
        return makeState(
            phase: .collapsed,
            recentEvents: state.recentEvents,
            unreviewedCount: state.unreviewedCount
        )
    }

    private func recent(
        _ event: NotificationEvent,
        after existingEvents: [NotificationEvent]
    ) -> [NotificationEvent] {
        let olderEvents = existingEvents.filter { $0.id != event.id }
        return [event] + olderEvents
    }

    private func makeState(
        phase: NotificationIslandPhase,
        currentEvent: NotificationEvent? = nil,
        recentEvents: [NotificationEvent] = [],
        unreviewedCount: Int = 0
    ) -> NotificationIslandState {
        NotificationIslandState(
            phase: phase,
            currentEvent: currentEvent,
            recentEvents: recentEvents,
            unreviewedCount: unreviewedCount
        )
    }

    private func incremented(_ count: Int) -> Int {
        count == Int.max ? Int.max : count + 1
    }
}
