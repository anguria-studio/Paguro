import Foundation
import Testing
@testable import PaguroCore

struct NotificationIslandStateTests {
    private let reducer = NotificationIslandReducer()

    @Test
    func showsAQuietCollapsedState() {
        let state = reducer.reduce(.hidden, action: .showCollapsed)

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)
    }

    @Test
    func receivingAnEventShowsTheNewestAlert() throws {
        let event = try makeEvent(number: 1)

        let state = reducer.reduce(.hidden, action: .receive(event))

        #expect(state.phase == .alert)
        #expect(state.currentEvent == event)
        #expect(state.recentEvents == [event])
        #expect(state.unreviewedCount == 1)
    }

    @Test
    func aBurstReplacesTheCompactPreviewAndKeepsTheCount() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))

        state = reducer.reduce(state, action: .receive(secondEvent))

        #expect(state.phase == .alert)
        #expect(state.currentEvent == secondEvent)
        #expect(state.recentEvents == [secondEvent, firstEvent])
        #expect(state.unreviewedCount == 2)
    }

    @Test
    func recentHistoryKeepsAllSessionDetails() throws {
        var state = NotificationIslandState.hidden

        for number in 1...6 {
            state = reducer.reduce(
                state,
                action: .receive(try makeEvent(number: number))
            )
        }

        #expect(state.recentEvents.map(\.title) == [
            "Event 6",
            "Event 5",
            "Event 4",
            "Event 3",
            "Event 2",
            "Event 1"
        ])
        #expect(state.unreviewedCount == 6)
    }

    @Test
    func hoverOpensTheCompleteRecentViewFromCollapsed() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))
        state = reducer.reduce(state, action: .expireCurrent)
        state = reducer.reduce(state, action: .finishDismissal)

        state = reducer.reduce(state, action: .beginPeek)

        #expect(state.phase == .peek)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents == [event])
        #expect(state.unreviewedCount == 1)

        state = reducer.reduce(state, action: .endPeek)

        #expect(state.phase == .collapsed)
        #expect(state.unreviewedCount == 1)
    }

    @Test
    func hoverTemporarilyExpandsAVisibleAlert() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))

        state = reducer.reduce(state, action: .beginPeek)

        #expect(state.phase == .peek)
        #expect(state.currentEvent == event)

        state = reducer.reduce(state, action: .endPeek)

        #expect(state.phase == .alert)
        #expect(state.currentEvent == event)
    }

    @Test
    func clickingTheTransientViewPinsItOpen() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))
        state = reducer.reduce(state, action: .beginPeek)

        state = reducer.reduce(state, action: .expand)

        #expect(state.phase == .expanded)
        #expect(state.currentEvent == event)

        state = reducer.reduce(state, action: .collapse)

        #expect(state.phase == .alert)
    }

    @Test
    func hoverDoesNotOpenAnEmptyNotificationList() {
        let state = reducer.reduce(.hidden, action: .showCollapsed)

        #expect(reducer.reduce(state, action: .beginPeek) == state)
        #expect(reducer.reduce(state, action: .expand) == state)
    }

    @Test
    func anEventReceivedWhilePeekingKeepsTheRecentViewOpen() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .beginPeek)

        state = reducer.reduce(state, action: .receive(secondEvent))

        #expect(state.phase == .peek)
        #expect(state.currentEvent == secondEvent)
        #expect(state.recentEvents == [secondEvent, firstEvent])
        #expect(state.unreviewedCount == 2)
    }

    @Test
    func alertExpiryKeepsHistoryAndTheUnreviewedCount() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))

        state = reducer.reduce(state, action: .expireCurrent)
        #expect(state.phase == .dismissed)
        #expect(state.currentEvent == event)

        state = reducer.reduce(state, action: .finishDismissal)

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents == [event])
        #expect(state.unreviewedCount == 1)
    }

    @Test
    func dismissingAVisibleEventDecrementsTheCount() throws {
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .receive(secondEvent))
        state = reducer.reduce(state, action: .beginPeek)

        state = reducer.reduce(
            state,
            action: .dismissEvent(firstEvent.id)
        )

        #expect(state.phase == .peek)
        #expect(state.recentEvents == [secondEvent])
        #expect(state.unreviewedCount == 1)
    }

    @Test
    func dismissingTheCompactAlertUsesTheExitTransition() throws {
        let event = try makeEvent(number: 1)
        var state = reducer.reduce(.hidden, action: .receive(event))

        state = reducer.reduce(state, action: .dismissEvent(event.id))

        #expect(state.phase == .dismissed)
        #expect(state.currentEvent == event)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)

        state = reducer.reduce(state, action: .finishDismissal)
        #expect(state.phase == .collapsed)
    }

    @Test
    func dismissAllClearsAllSessionEvents() throws {
        var state = NotificationIslandState.hidden
        for number in 1...6 {
            state = reducer.reduce(
                state,
                action: .receive(try makeEvent(number: number))
            )
        }
        state = reducer.reduce(state, action: .beginPeek)

        state = reducer.reduce(state, action: .dismissAll)

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)
    }

    @Test
    func dismissingEveryEventClearsTheCount() throws {
        var state = NotificationIslandState.hidden
        for number in 1...6 {
            state = reducer.reduce(
                state,
                action: .receive(try makeEvent(number: number))
            )
        }
        state = reducer.reduce(state, action: .beginPeek)
        let eventIDs = state.recentEvents.map(\.id)

        for eventID in eventIDs {
            state = reducer.reduce(state, action: .dismissEvent(eventID))
        }

        #expect(state.phase == .collapsed)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)
    }

    @Test
    func readingAServiceRemovesOnlyItsEvents() throws {
        let serviceID = UUID()
        let otherServiceID = UUID()
        let firstEvent = try makeEvent(number: 1, serviceID: serviceID)
        let secondEvent = try makeEvent(number: 2, serviceID: otherServiceID)
        let thirdEvent = try makeEvent(number: 3, serviceID: serviceID)
        var state = reducer.reduce(.hidden, action: .receive(firstEvent))
        state = reducer.reduce(state, action: .receive(secondEvent))
        state = reducer.reduce(state, action: .receive(thirdEvent))
        state = reducer.reduce(state, action: .expand)

        state = reducer.reduce(
            state,
            action: .dismissEvents(serviceID: serviceID)
        )

        #expect(state.phase == .expanded)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents == [secondEvent])
        #expect(state.unreviewedCount == 1)
    }

    @Test
    func readingTheServiceOfTheCompactAlertUsesTheExitTransition() throws {
        let serviceID = UUID()
        let event = try makeEvent(number: 1, serviceID: serviceID)
        var state = reducer.reduce(.hidden, action: .receive(event))

        state = reducer.reduce(
            state,
            action: .dismissEvents(serviceID: serviceID)
        )

        #expect(state.phase == .dismissed)
        #expect(state.currentEvent == event)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)

        state = reducer.reduce(state, action: .finishDismissal)
        #expect(state.phase == .collapsed)
    }

    @Test
    func readingAServiceWithoutEventsKeepsTheState() throws {
        var state = reducer.reduce(
            .hidden,
            action: .receive(try makeEvent(number: 1))
        )
        state = reducer.reduce(state, action: .beginPeek)

        let nextState = reducer.reduce(
            state,
            action: .dismissEvents(serviceID: UUID())
        )

        #expect(nextState == state)
    }

    @Test
    func readingTheLastServiceCollapsesTheIslandAndClearsTheCount() throws {
        let serviceID = UUID()
        var state = NotificationIslandState.hidden
        for number in 1...4 {
            state = reducer.reduce(
                state,
                action: .receive(try makeEvent(number: number, serviceID: serviceID))
            )
        }
        state = reducer.reduce(state, action: .beginPeek)

        state = reducer.reduce(
            state,
            action: .dismissEvents(serviceID: serviceID)
        )

        #expect(state.phase == .collapsed)
        #expect(state.currentEvent == nil)
        #expect(state.recentEvents.isEmpty)
        #expect(state.unreviewedCount == 0)
    }

    @Test
    func counterLabelUsesACompactUpperLimit() {
        #expect(NotificationIslandCounterLabel.text(for: 0) == nil)
        #expect(NotificationIslandCounterLabel.text(for: 4) == "4")
        #expect(NotificationIslandCounterLabel.text(for: 99) == "99")
        #expect(NotificationIslandCounterLabel.text(for: 100) == "99+")
    }

    @Test
    func stopClearsAllEventContent() throws {
        var state = reducer.reduce(
            .hidden,
            action: .receive(try makeEvent(number: 1))
        )

        state = reducer.reduce(state, action: .stop)

        #expect(state == .hidden)
    }

    @Test
    func invalidTransitionsDoNotChangeState() throws {
        let state = reducer.reduce(
            .hidden,
            action: .receive(try makeEvent(number: 1))
        )

        #expect(reducer.reduce(state, action: .collapse) == state)
        #expect(reducer.reduce(.hidden, action: .finishDismissal) == .hidden)
        #expect(reducer.reduce(.hidden, action: .dismissAll) == .hidden)
    }

    private func makeEvent(
        number: Int,
        serviceID: UUID = UUID()
    ) throws -> NotificationEvent {
        try NotificationEvent.normalize(
            id: UUID(),
            serviceID: serviceID,
            source: .pageNotification,
            title: "Event \(number)",
            body: "Body \(number)",
            receivedAt: Date(timeIntervalSince1970: TimeInterval(number))
        )
    }
}
