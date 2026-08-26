import Foundation
import Testing
@testable import AtollCore

struct NotificationIslandStateTests {
    private let reducer = NotificationIslandReducer()

    @Test
    func showsAQuietCollapsedState() {
        let state = reducer.reduce(.hidden, action: .showCollapsed)

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.queuedEvents.isEmpty)
    }

    @Test
    func receivingAnEventShowsAnAlert() throws {
        let event = try makeEvent(number: 1)

        let state = reducer.reduce(.hidden, action: .receive(event))

        #expect(state.phase == .alert)
        #expect(state.currentEvent == event)
        #expect(state.pendingCount == 0)
    }

    @Test
    func receivingAnotherEventQueuesIt() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))

        state = reducer.reduce(state, action: .receive(secondEvent))

        #expect(state.phase == .alert)
        #expect(state.currentEvent == firstEvent)
        #expect(state.queuedEvents == [secondEvent])
    }

    @Test
    func expansionAndCollapseKeepTheCurrentAlert() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))

        state = reducer.reduce(state, action: .expand)
        #expect(state.phase == .expanded)
        #expect(state.currentEvent == event)

        state = reducer.reduce(state, action: .collapse)
        #expect(state.phase == .alert)
        #expect(state.currentEvent == event)
    }

    @Test
    func finishingDismissalPromotesTheNextEvent() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .receive(secondEvent))

        state = reducer.reduce(state, action: .dismissCurrent)
        #expect(state.phase == .dismissed)
        #expect(state.currentEvent == firstEvent)

        state = reducer.reduce(state, action: .finishDismissal)
        #expect(state.phase == .alert)
        #expect(state.currentEvent == secondEvent)
        #expect(state.queuedEvents.isEmpty)
    }

    @Test
    func finishingTheLastDismissalReturnsToCollapsed() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))
        state = reducer.reduce(state, action: .dismissCurrent)

        state = reducer.reduce(state, action: .finishDismissal)

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.queuedEvents.isEmpty)
    }

    @Test
    func queueKeepsTheNewestPendingEventsAtItsLimit() throws {
        let limitedReducer = NotificationIslandReducer(maximumQueuedEvents: 2)
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        let thirdEvent = try makeEvent(number: 3)
        let fourthEvent = try makeEvent(number: 4)
        var state = limitedReducer.reduce(.hidden, action: .receive(firstEvent))
        state = limitedReducer.reduce(state, action: .receive(secondEvent))
        state = limitedReducer.reduce(state, action: .receive(thirdEvent))

        state = limitedReducer.reduce(state, action: .receive(fourthEvent))

        #expect(state.currentEvent == firstEvent)
        #expect(state.queuedEvents == [thirdEvent, fourthEvent])
        #expect(state.pendingCount == 3)
    }

    @Test
    func burstCountCanExceedThePayloadQueueLimit() throws {
        let limitedReducer = NotificationIslandReducer(maximumQueuedEvents: 2)
        var state = limitedReducer.reduce(
            .hidden,
            action: .receive(try makeEvent(number: 1))
        )

        for number in 2...8 {
            state = limitedReducer.reduce(
                state,
                action: .receive(try makeEvent(number: number))
            )
        }

        #expect(state.pendingCount == 7)
        #expect(state.queuedEvents.map(\.title) == ["Event 7", "Event 8"])
    }

    @Test
    func promotedEventCountsOnlyItsRetainedPendingPreviews() throws {
        let limitedReducer = NotificationIslandReducer(maximumQueuedEvents: 2)
        var state = limitedReducer.reduce(
            .hidden,
            action: .receive(try makeEvent(number: 1))
        )
        for number in 2...5 {
            state = limitedReducer.reduce(
                state,
                action: .receive(try makeEvent(number: number))
            )
        }

        state = limitedReducer.reduce(state, action: .dismissCurrent)
        state = limitedReducer.reduce(state, action: .finishDismissal)

        #expect(state.currentEvent?.title == "Event 4")
        #expect(state.queuedEvents.map(\.title) == ["Event 5"])
        #expect(state.pendingCount == 1)
    }

    @Test
    func counterLabelUsesACompactUpperLimit() {
        #expect(NotificationIslandCounterLabel.text(for: 0) == nil)
        #expect(NotificationIslandCounterLabel.text(for: 4) == "+4")
        #expect(NotificationIslandCounterLabel.text(for: 99) == "+99")
        #expect(NotificationIslandCounterLabel.text(for: 100) == "99+")
    }

    @Test
    func eventReceivedDuringDismissalWaitsInTheQueue() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .dismissCurrent)

        state = reducer.reduce(state, action: .receive(secondEvent))
        state = reducer.reduce(state, action: .finishDismissal)

        #expect(state.phase == .alert)
        #expect(state.currentEvent == secondEvent)
    }

    @Test
    func stopClearsAllEventContent() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .receive(secondEvent))

        state = reducer.reduce(state, action: .stop)

        #expect(state == .hidden)
    }

    @Test
    func invalidTransitionsDoNotChangeState() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))
        state = reducer.reduce(state, action: .dismissCurrent)

        #expect(reducer.reduce(state, action: .expand) == state)
        #expect(reducer.reduce(state, action: .collapse) == state)
        #expect(reducer.reduce(.hidden, action: .finishDismissal) == .hidden)
    }

    private func makeEvent(number: Int) throws -> NotificationEvent {
        try NotificationEvent.normalize(
            id: UUID(),
            serviceID: UUID(),
            source: .pageNotification,
            title: "Event \(number)",
            body: "Body \(number)",
            receivedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }
}
