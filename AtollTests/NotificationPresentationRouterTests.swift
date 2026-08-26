import AtollCore
import Foundation
import XCTest
@testable import Atoll

@MainActor
final class NotificationPresentationRouterTests: XCTestCase {
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

    func testExplicitSettingsCanPresentBothRoutes() throws {
        let systemPresenter = RecordingNotificationPresenter()
        let islandPresenter = RecordingNotificationPresenter()
        let router = makeRouter(
            systemPresenter: systemPresenter,
            islandPresenter: islandPresenter,
            islandEnabled: true
        )
        let event = try makeEvent()

        router.present(event: event, requestID: "request", traceID: "trace")

        XCTAssertEqual(systemPresenter.eventIDs, [event.id])
        XCTAssertEqual(islandPresenter.eventIDs, [event.id])
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
