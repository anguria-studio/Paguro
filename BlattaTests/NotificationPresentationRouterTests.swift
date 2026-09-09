import BlattaCore
import Foundation
import XCTest
@testable import Blatta

@MainActor
final class NotificationPresentationRouterTests: XCTestCase {
    func testLockChangesApplyToExistingRoutersAndDoNotReplayEvents() throws {
        for islandEnabled in [false, true] {
            let snapshot = AtomicBool(false)
            let system = RecordingNotificationPresenter()
            let island = RecordingNotificationPresenter()
            let router = NotificationPresentationRouter(
                systemPresenter: system,
                isLockedCheck: { snapshot.value },
                islandPresenter: island,
                isMutedCheck: { _ in false },
                isSystemEnabledCheck: { _ in true },
                isIslandEnabledCheck: { _ in islandEnabled },
                isDoNotDisturbCheck: { false }
            )
            snapshot.value = true
            router.present(event: try makeEvent(), requestID: "locked", traceID: "locked")
            XCTAssertTrue(system.eventIDs.isEmpty)
            XCTAssertTrue(island.eventIDs.isEmpty)
            snapshot.value = false
            let next = try makeEvent()
            router.present(event: next, requestID: "unlocked", traceID: "unlocked")
            XCTAssertEqual(system.eventIDs + island.eventIDs, [next.id])
        }
    }

    func testDefaultRoutePresentsOnlyTheSystemNotification() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(systemPresenter.eventIDs, [event.id])
        XCTAssertTrue(islandPresenter.eventIDs.isEmpty)
    }

    /// One event reaches one destination, even with both routes switched on.
    ///
    /// The system route stays enabled by default, so turning the island on used
    /// to mean every message arrived twice: once in the island, and once as a
    /// macOS banner that outlived it and had to be cleared by hand.
    func testTheIslandTakesTheEventInsteadOfPresentingItTwice() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            islandEnabled: true
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(islandPresenter.eventIDs, [event.id])
        XCTAssertTrue(
            systemPresenter.eventIDs.isEmpty,
            "macOS must not post its own banner for an event the island took"
        )
    }

    func testMuteSuppressesEveryPresenter() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            isMuted: true,
            islandEnabled: true
        )

        router.present(
            event: try makeEvent(),
            requestID: "request",
            traceID: "trace"
        )

        XCTAssertTrue(systemPresenter.eventIDs.isEmpty)
        XCTAssertTrue(islandPresenter.eventIDs.isEmpty)
    }

    func testUnavailableIslandRouteDoesNotSuppressTheSystemRoute() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: nil,
            systemEnabled: false,
            islandEnabled: true
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(systemPresenter.eventIDs, [event.id])
    }

    func testNonNotchedDisplayFallsBackWithoutPresentingTheIsland() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            systemEnabled: false,
            islandEnabled: true,
            islandAvailable: false
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(systemPresenter.eventIDs, [event.id])
        XCTAssertTrue(islandPresenter.eventIDs.isEmpty)
    }

    /// The user can move the window from a notched display to an external one
    /// while Blatta runs. The router must read island availability for each
    /// event, never once at startup.
    func testIslandAvailabilityIsReadForEachEvent() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let availability = MutableAvailability()
        let router = NotificationPresentationRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            isMutedCheck: { _ in false },
            isSystemEnabledCheck: { _ in false },
            isIslandEnabledCheck: { _ in true },
            isIslandAvailableCheck: { availability.isAvailable },
            isDoNotDisturbCheck: { false }
        )

        let notchedEvent = try makeEvent()
        router.present(event: notchedEvent, requestID: "a", traceID: "a")

        XCTAssertEqual(islandPresenter.eventIDs, [notchedEvent.id])
        XCTAssertTrue(systemPresenter.eventIDs.isEmpty)

        availability.isAvailable = false
        let externalEvent = try makeEvent()
        router.present(event: externalEvent, requestID: "b", traceID: "b")

        XCTAssertEqual(islandPresenter.eventIDs, [notchedEvent.id])
        XCTAssertEqual(systemPresenter.eventIDs, [externalEvent.id])
    }

    /// An island route that is on with the system route off must still reach
    /// the user on a display without a camera housing.
    func testDisabledIslandRouteOnANonNotchedDisplayStillUsesTheSystemRoute() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            systemEnabled: true,
            islandEnabled: false,
            islandAvailable: false
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(systemPresenter.eventIDs, [event.id])
        XCTAssertTrue(islandPresenter.eventIDs.isEmpty)
    }

    private func makeRouter(
        systemPresenter: RecordingNotificationPresenter,
        islandPresenter: RecordingNotificationPresenter?,
        isMuted: Bool = false,
        systemEnabled: Bool = true,
        islandEnabled: Bool = false,
        islandAvailable: Bool = true,
        doNotDisturb: Bool = false
    ) -> NotificationPresentationRouter {
        NotificationPresentationRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            isMutedCheck: { _ in isMuted },
            isSystemEnabledCheck: { _ in systemEnabled },
            isIslandEnabledCheck: { _ in islandEnabled },
            isIslandAvailableCheck: { islandAvailable },
            isDoNotDisturbCheck: { doNotDisturb }
        )
    }

    private func makeEvent() throws -> NotificationEvent {
        try NotificationEvent.normalize(
            id: UUID(),
            serviceID: UUID(),
            payload: NotificationPayload(title: "New message", body: "Body"),
            receivedAt: Date()
        )
    }
}

/// Stands in for a display change while Blatta runs.
@MainActor
private final class MutableAvailability {
    var isAvailable = true
}

@MainActor
private final class RecordingNotificationPresenter: NotificationEventPresenting {
    private(set) var eventIDs: [UUID] = []

    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    ) {
        eventIDs.append(event.id)
    }
}
