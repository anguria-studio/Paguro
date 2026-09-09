import PaguroCore
import Foundation
import AppKit
import SwiftUI
import XCTest
@testable import Paguro

@MainActor
final class IslandPanelControllerTests: XCTestCase {
    func testKeyboardOpeningStaysOpenAwayFromPointerAndCollapsesQuietly() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(renderer: renderer, scheduler: scheduler)
        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        controller.openFromKeyboard()
        XCTAssertEqual(controller.state.phase, .expanded)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        controller.setHovering(false)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        controller.present(panelContent(for: try makeEvent(number: 2)))
        XCTAssertEqual(controller.state.phase, .expanded)
        controller.collapse()
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.unreviewedCount, 2)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testKeyboardOpeningRejectsEmptyLockedAndStoppedIsland() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        controller.openFromKeyboard()
        XCTAssertEqual(controller.state.phase, .hidden)
        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        controller.setLocked(true)
        controller.openFromKeyboard()
        XCTAssertEqual(controller.state.phase, .collapsed)
        controller.setLocked(false)
        controller.stop()
        controller.openFromKeyboard()
        XCTAssertEqual(controller.state.phase, .hidden)
    }

    func testHistoryAvailabilityUpdatesForMenuCommand() throws {
        let controller = makeController(renderer: RecordingIslandPanelRenderer())
        var availability: [Bool] = []
        controller.onHistoryAvailabilityChanged = { availability.append($0) }
        controller.present(panelContent(for: try makeEvent(number: 1)))
        controller.present(panelContent(for: try makeEvent(number: 2)))
        controller.dismissAll()
        XCTAssertEqual(availability, [true, false])
    }

    func testLockPreservesHistoryAndRejectsPreviewsUntilUnlock() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let original = try makeEvent(number: 1)
        controller.present(panelContent(for: original))
        await waitForShow(in: renderer)
        controller.setLocked(true)
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.recentEvents, [original])
        XCTAssertGreaterThan(renderer.hideCount, 0)
        controller.present(panelContent(for: try makeEvent(number: 2)))
        controller.showCollapsed()
        controller.dismissEvents(forService: original.serviceID)
        controller.dismissAll()
        XCTAssertEqual(controller.state.recentEvents, [original])
        controller.setLocked(false)
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.recentEvents, [original])
        controller.present(panelContent(for: try makeEvent(number: 3)))
        XCTAssertEqual(controller.state.unreviewedCount, 2)
    }

    func testDisablingIslandWhileLockedDiscardsRetainedHistory() throws {
        let controller = makeController(renderer: RecordingIslandPanelRenderer())
        controller.present(panelContent(for: try makeEvent(number: 1)))
        controller.setLocked(true)
        controller.hide()
        controller.setLocked(false)
        XCTAssertEqual(controller.state, .hidden)
    }

    func testDismissalRecognizesMacDeleteEvents() throws {
        for (keyCode, characters) in [(UInt16(51), "\u{7f}"), (UInt16(117), "\u{f728}")] {
            let event = try XCTUnwrap(NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, characters: characters,
                charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
            ))
            let character = try XCTUnwrap(event.charactersIgnoringModifiers?.first)
            XCTAssertTrue(IslandKeyboardInput.dismissalKeys.contains(KeyEquivalent(character)))
        }
        XCTAssertTrue(IslandKeyboardInput.dismissalKeys.contains(.delete))
        XCTAssertFalse(IslandKeyboardInput.dismissalKeys.contains(.return))
    }

    func testControllerStartsHiddenWithoutCreatingVisibleContent() {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertTrue(renderer.shows.isEmpty)
        XCTAssertEqual(renderer.hideCount, 0)
    }

    func testCollapsedIslandWaitsForTheLaunchActivationBeforeItIsOrdered() async {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(
            renderer: renderer,
            waitsForLaunchActivation: true
        )

        controller.showCollapsed()
        // The geometry snapshot resolves and renders on the main actor, so the
        // island has every chance to reach the renderer here.
        for _ in 0..<20 {
            await Task.yield()
        }

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertTrue(renderer.shows.isEmpty)

        controller.launchActivationDidSettle()
        await waitForShow(in: renderer)

        XCTAssertEqual(renderer.shows.last?.state.phase, .collapsed)
    }

    func testAnEventPresentedBeforeTheLaunchSettlesAppearsAfterIt() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(
            renderer: renderer,
            waitsForLaunchActivation: true
        )
        let event = try makeEvent(number: 1)

        controller.present(panelContent(for: event))
        for _ in 0..<20 {
            await Task.yield()
        }
        XCTAssertTrue(renderer.shows.isEmpty)

        controller.launchActivationDidSettle()
        await waitForShow(in: renderer)

        XCTAssertEqual(renderer.shows.last?.content?.event, event)
    }

    func testPresentingAnEventShowsTheResolvedAlert() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let event = try makeEvent(number: 1)

        controller.present(
            NotificationIslandPanelContent(
                event: event,
                serviceLabel: "Chat",
                serviceIconURL: nil
            )
        )
        await waitForShow(in: renderer)

        XCTAssertEqual(controller.state.phase, .alert)
        XCTAssertEqual(renderer.shows.last?.content?.event, event)
        XCTAssertEqual(renderer.shows.last?.placement.style, .cameraHousing)
    }

    func testSecondEventReplacesTheCompactPreview() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)

        controller.present(panelContent(for: firstEvent))
        controller.present(panelContent(for: secondEvent))
        await waitForShow(in: renderer)

        XCTAssertEqual(controller.state.currentEvent, secondEvent)
        XCTAssertEqual(controller.state.recentEvents, [secondEvent, firstEvent])
        XCTAssertEqual(renderer.shows.last?.state.unreviewedCount, 2)
    }

    func testStopHidesAndRejectsLaterEvents() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let event = try makeEvent(number: 1)

        controller.stop()
        controller.present(panelContent(for: event))
        await Task.yield()

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertEqual(renderer.stopCount, 1)
        XCTAssertTrue(renderer.shows.isEmpty)
    }

    func testAlertUsesTheStandardDelayAndReturnsToCollapsedState() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)

        XCTAssertEqual(scheduler.pendingDelays, [.seconds(4)])
        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .dismissed)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])

        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testNewestAlertRestartsOneCompactDisplayTime() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)

        controller.present(panelContent(for: firstEvent))
        controller.present(panelContent(for: secondEvent))
        await waitForShow(in: renderer)

        XCTAssertEqual(controller.state.currentEvent, secondEvent)
        XCTAssertEqual(scheduler.pendingDelays, [.seconds(4)])
        scheduler.fireNext()
        scheduler.fireNext()

        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertEqual(controller.state.unreviewedCount, 2)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testVoiceOverUsesTheLongerAlertDelay() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler,
            isVoiceOverEnabled: true
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)

        XCTAssertEqual(scheduler.pendingDelays, [.seconds(12)])
    }

    func testNewAlertCancelsAnOlderDismissalTransition() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)

        controller.present(panelContent(for: firstEvent))
        await waitForShow(in: renderer)
        scheduler.fireNext()
        controller.present(panelContent(for: secondEvent))

        XCTAssertEqual(controller.state.phase, .alert)
        XCTAssertEqual(controller.state.currentEvent, secondEvent)
        XCTAssertEqual(scheduler.pendingDelays, [.seconds(4)])
    }

    func testCollapsedIslandOpensTheExpandedState() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )
        renderer.shows.last?.actions.primary?()

        XCTAssertEqual(controller.state.phase, .expanded)
        XCTAssertNotNil(renderer.shows.last?.actions.collapse)
        XCTAssertNotNil(renderer.shows.last?.actions.openEvent)
        XCTAssertNotNil(renderer.shows.last?.actions.dismissEvent)
        XCTAssertNotNil(renderer.shows.last?.actions.dismissAll)
    }

    func testEmptyCollapsedIslandDoesNotOfferAnOpenAction() async {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        controller.showCollapsed()
        await waitForShow(in: renderer)

        XCTAssertNil(renderer.shows.last?.actions.primary)
        XCTAssertNotNil(renderer.shows.last?.actions.hoverChanged)
    }

    func testHoverOpensAPeekAndDelayedExitReturnsToCollapsed() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )
        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertEqual(
            renderer.shows.last?.placement.frame.size.width,
            NotificationIslandLayout.panelWidth(
                bodyWidth: NotificationIslandLayout.expandedWidth
            )
        )
        XCTAssertEqual(
            renderer.shows.last?.placement.frame.size.height,
            expandedHeight(eventCount: 1)
        )

        renderer.shows.last?.actions.hoverChanged?(false)

        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])
        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .collapsed)
    }

    func testExpandedHeightFollowsTheNumberOfRecentEvents() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)

        controller.present(panelContent(for: firstEvent))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.pin?()
        let oneEventHeight = renderer.shows.last?.placement.frame.size.height

        XCTAssertEqual(controller.state.phase, .expanded)
        XCTAssertEqual(oneEventHeight, expandedHeight(eventCount: 1))

        controller.present(panelContent(for: secondEvent))
        await Task.yield()
        let twoEventHeight = renderer.shows.last?.placement.frame.size.height

        XCTAssertEqual(controller.state.recentEvents.count, 2)
        XCTAssertEqual(twoEventHeight, expandedHeight(eventCount: 2))
        XCTAssertGreaterThan(twoEventHeight ?? 0, oneEventHeight ?? 0)

        renderer.shows.last?.actions.dismissEvent?(firstEvent.id)
        await Task.yield()

        XCTAssertEqual(controller.state.recentEvents.count, 1)
        XCTAssertEqual(
            renderer.shows.last?.placement.frame.size.height,
            expandedHeight(eventCount: 1)
        )
    }

    func testHoveringACompactAlertOpensTheCompleteRecentView() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        XCTAssertNotNil(renderer.shows.last?.actions.pin)
    }

    func testLeavingTheHoverViewClosesTheIslandCompletely() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let event = try makeEvent(number: 1)

        controller.present(panelContent(for: event))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.hoverChanged?(false)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])
        scheduler.fireNext()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.unreviewedCount, 1)
        XCTAssertEqual(controller.state.recentEvents, [event])
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testLeavingThePinnedExpandedIslandCollapsesIt() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let event = try makeEvent(number: 1)

        controller.present(panelContent(for: event))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.pin?()
        XCTAssertEqual(controller.state.phase, .expanded)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)

        renderer.shows.last?.actions.hoverChanged?(false)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])
        scheduler.fireNext()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNil(controller.state.currentEvent)
        XCTAssertEqual(controller.state.unreviewedCount, 1)
        XCTAssertEqual(controller.state.recentEvents, [event])
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testPointerOverTheIslandKeepsTheHoverViewOpen() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let pointer = RecordingPointerLocation(isInside: true)
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler,
            pointer: pointer
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.hoverChanged?(false)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])
        scheduler.fireNext()

        // The pointer is still over the island, so the island stays open.
        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(250)])

        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(250)])

        pointer.isInside = false
        scheduler.fireNext()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertEqual(controller.state.unreviewedCount, 1)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testPointerReturnCancelsTheHoverExitCheck() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let pointer = RecordingPointerLocation(isInside: true)
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler,
            pointer: pointer
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.hoverChanged?(false)
        scheduler.fireNext()
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(250)])

        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testStopCancelsTheHoverExitCheck() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let pointer = RecordingPointerLocation(isInside: true)
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler,
            pointer: pointer
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.hoverChanged?(false)
        scheduler.fireNext()
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(250)])

        controller.stop()

        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
        XCTAssertEqual(controller.state, .hidden)
    }

    func testHoverReentryKeepsTheExpandedIslandOpen() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.pin?()
        renderer.shows.last?.actions.hoverChanged?(false)
        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .expanded)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testClickingTheHoverViewPinsItOpen() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.pin?()

        XCTAssertEqual(controller.state.phase, .expanded)
    }

    func testReadingAServiceRemovesItsEventsAndLowersTheCounter() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let serviceID = UUID()
        let otherEvent = try makeEvent(number: 2)
        controller.present(
            panelContent(for: try makeEvent(number: 1, serviceID: serviceID))
        )
        controller.present(panelContent(for: otherEvent))
        controller.present(
            panelContent(for: try makeEvent(number: 3, serviceID: serviceID))
        )
        await waitForShow(in: renderer)

        controller.dismissEvents(forService: serviceID)

        XCTAssertEqual(controller.state.phase, .dismissed)
        XCTAssertEqual(controller.state.recentEvents, [otherEvent])
        XCTAssertEqual(controller.state.unreviewedCount, 1)
        XCTAssertEqual(scheduler.pendingDelays.count, 1)

        scheduler.fireNext()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertEqual(renderer.shows.last?.state.unreviewedCount, 1)
    }

    func testReadingAnotherServiceKeepsTheVisibleAlert() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let event = try makeEvent(number: 1)
        controller.present(panelContent(for: event))
        await waitForShow(in: renderer)
        let showCount = renderer.shows.count

        controller.dismissEvents(forService: UUID())

        XCTAssertEqual(controller.state.phase, .alert)
        XCTAssertEqual(controller.state.recentEvents, [event])
        XCTAssertEqual(controller.state.unreviewedCount, 1)
        XCTAssertEqual(renderer.shows.count, showCount)
        XCTAssertEqual(scheduler.pendingDelays.count, 1)
    }

    func testDismissAllClearsTheCounterAndHistory() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        controller.present(panelContent(for: try makeEvent(number: 1)))
        controller.present(panelContent(for: try makeEvent(number: 2)))
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.dismissAll?()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertEqual(controller.state.unreviewedCount, 0)
        XCTAssertTrue(controller.state.recentEvents.isEmpty)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testCollapsedIslandKeepsTheUnreviewedCounter() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )

        XCTAssertEqual(renderer.shows.last?.state.unreviewedCount, 1)
        XCTAssertGreaterThan(
            renderer.shows.last?.placement.frame.size.width ?? 0,
            renderer.shows.last?.cameraHousingSize?.width ?? 0
        )
    }

    /// The collapsed island must read as the camera housing, only wider.
    func testCollapsedIslandKeepsTheHousingHeightAndTopEdge() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )

        let show = try XCTUnwrap(renderer.shows.last)
        let housing = try XCTUnwrap(show.cameraHousingSize)
        let screen = try XCTUnwrap(
            SimulatedScreenGeometryProvider(preset: .notched14Inch)
                .scenario
                .snapshot
                .selectedScreen
        )
        XCTAssertEqual(show.placement.frame.size.height, housing.height)
        XCTAssertEqual(show.placement.frame.maxY, screen.frame.maxY)
        XCTAssertEqual(
            show.placement.frame.size.width,
            NotificationIslandLayout.panelWidth(bodyWidth: housing.width + 76)
        )
    }

    /// An idle island must measure exactly the camera housing.
    ///
    /// It used to carry 12 points of wing on each side. The collapsed surface
    /// is the same black as the housing, so on hardware that surplus does not
    /// read as an island at all — it reads as a notch that got wider when
    /// Paguro launched.
    func testCollapsedIslandWithoutACountAddsNoWidthToTheHousing() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        controller.showCollapsed()
        await waitForShow(in: renderer)

        let show = try XCTUnwrap(renderer.shows.last)
        let housing = try XCTUnwrap(show.cameraHousingSize)
        XCTAssertEqual(
            show.placement.frame.size.width,
            NotificationIslandLayout.panelWidth(bodyWidth: housing.width),
            "an idle island must be exactly as wide as the housing"
        )
        XCTAssertEqual(
            show.placement.frame.size.height,
            housing.height,
            "and exactly as tall, so the notch keeps its shape"
        )
    }

    func testHoverReentryCancelsThePendingPeekExit() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )
        renderer.shows.last?.actions.hoverChanged?(true)
        renderer.shows.last?.actions.hoverChanged?(false)
        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .peek)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testHoverDoesNotOpenAnEmptyNotificationList() async {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        controller.showCollapsed()
        await waitForShow(in: renderer)
        renderer.shows.last?.actions.hoverChanged?(true)

        XCTAssertEqual(controller.state.phase, .collapsed)
    }

    func testPointerTestFrameKeepsTheSideAndBottomMargin() {
        let panelFrame = CGRect(x: 500, y: 1000, width: 400, height: 100)

        let frame = IslandPanelController.pointerTestFrame(
            panelFrame: panelFrame,
            screenTopY: 1100
        )

        XCTAssertEqual(frame.minX, 494)
        XCTAssertEqual(frame.maxX, 906)
        XCTAssertEqual(frame.minY, 994)
        XCTAssertEqual(frame.maxY, 1100)
    }

    func testPointerTestFrameReachesTheTopScreenEdge() {
        let panelFrame = CGRect(x: 500, y: 980, width: 400, height: 100)

        let frame = IslandPanelController.pointerTestFrame(
            panelFrame: panelFrame,
            screenTopY: 1100
        )

        XCTAssertEqual(frame.maxY, 1100)
        XCTAssertEqual(frame.minY, 974)
    }

    func testPointerAtTheTopScreenEdgeCountsAsInsideTheIsland() {
        let panelFrame = CGRect(x: 500, y: 980, width: 400, height: 100)

        XCTAssertTrue(
            IslandPanelController.pointerIsInside(
                CGPoint(x: 700, y: 1100),
                panelFrame: panelFrame,
                screenTopY: 1100
            )
        )
    }

    func testPointerOutsideTheMarginCountsAsOutsideTheIsland() {
        let panelFrame = CGRect(x: 500, y: 1000, width: 400, height: 100)

        XCTAssertTrue(
            IslandPanelController.pointerIsInside(
                CGPoint(x: 494, y: 994),
                panelFrame: panelFrame,
                screenTopY: 1100
            )
        )
        XCTAssertFalse(
            IslandPanelController.pointerIsInside(
                CGPoint(x: 493, y: 1050),
                panelFrame: panelFrame,
                screenTopY: 1100
            )
        )
        XCTAssertFalse(
            IslandPanelController.pointerIsInside(
                CGPoint(x: 700, y: 993),
                panelFrame: panelFrame,
                screenTopY: 1100
            )
        )
    }

    func testPointerTestFrameWithoutAScreenUsesThePanelTop() {
        let panelFrame = CGRect(x: 500, y: 1000, width: 400, height: 100)

        let frame = IslandPanelController.pointerTestFrame(
            panelFrame: panelFrame,
            screenTopY: nil
        )

        XCTAssertEqual(frame.maxY, 1100)
    }

    func testAppearanceChangesReachTheVisibleIsland() async {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let appearance = NotificationIslandAppearance(
            glassStyle: .clear,
            transparency: 0.4
        )

        controller.showCollapsed()
        await waitForShow(in: renderer)
        controller.updateAppearance(appearance)

        XCTAssertEqual(renderer.shows.last?.appearance, appearance)
    }

    func testExpandedIslandKeepsAndOpensARecentEvent() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )
        let event = try makeEvent(number: 1)
        var requestedServiceIDs: [UUID] = []
        controller.onServiceRequested = { requestedServiceIDs.append($0) }

        controller.present(panelContent(for: event))
        await waitForShow(in: renderer)
        scheduler.fireNext()
        scheduler.fireNext()
        renderer.shows.last?.actions.primary?()
        renderer.shows.last?.actions.openEvent?(event.id)

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertTrue(renderer.shows.last?.recentContents.isEmpty == true)
        XCTAssertEqual(requestedServiceIDs, [event.serviceID])
    }

    func testClosingExpandedIslandReturnsToCollapsed() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let scheduler = RecordingIslandPanelScheduler()
        let controller = makeController(
            renderer: renderer,
            scheduler: scheduler
        )

        try await prepareCollapsedHistory(
            controller: controller,
            scheduler: scheduler,
            renderer: renderer
        )
        renderer.shows.last?.actions.primary?()
        renderer.shows.last?.actions.collapse?()

        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertNotNil(renderer.shows.last?.actions.primary)
    }

    func testVisibleIslandHidesOffNotchAndReturnsOnNotchedScreen() async {
        let renderer = RecordingIslandPanelRenderer()
        let monitor = RecordingIslandScreenChangeMonitor()
        let provider = MutableIslandScreenGeometryProvider(
            snapshot: SimulatedScreenGeometryPreset.notched14Inch.scenario.snapshot
        )
        let controller = makeController(
            renderer: renderer,
            provider: provider,
            screenChangeMonitor: monitor
        )

        controller.showCollapsed()
        await waitForShow(in: renderer)
        controller.showCollapsed()
        XCTAssertEqual(renderer.shows.last?.placement.screenIdentifier, "notched-14-inch")
        XCTAssertEqual(monitor.startCount, 1)

        provider.snapshot = SimulatedScreenGeometryPreset.externalDisplay
            .scenario
            .snapshot
        let hideCount = renderer.hideCount
        monitor.sendChange()
        await waitForHide(after: hideCount, in: renderer)

        XCTAssertFalse(controller.canPresentIsland)

        provider.snapshot = SimulatedScreenGeometryPreset.notched16Inch
            .scenario
            .snapshot
        monitor.sendChange()
        await waitForPlacement(on: "notched-16-inch", in: renderer)

        XCTAssertTrue(controller.canPresentIsland)
        XCTAssertEqual(renderer.shows.last?.placement.screenIdentifier, "notched-16-inch")
    }

    func testHideStopsScreenTracking() async {
        let renderer = RecordingIslandPanelRenderer()
        let monitor = RecordingIslandScreenChangeMonitor()
        let controller = makeController(
            renderer: renderer,
            screenChangeMonitor: monitor
        )

        controller.showCollapsed()
        await waitForShow(in: renderer)
        controller.hide()
        let showCount = renderer.shows.count
        monitor.sendChange()
        await Task.yield()

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(renderer.shows.count, showCount)
        XCTAssertEqual(controller.state, .hidden)
    }

    func testStopRemovesScreenTrackingAndRejectsLaterChanges() async {
        let renderer = RecordingIslandPanelRenderer()
        let monitor = RecordingIslandScreenChangeMonitor()
        let controller = makeController(
            renderer: renderer,
            screenChangeMonitor: monitor
        )

        controller.showCollapsed()
        await waitForShow(in: renderer)
        controller.stop()
        let showCount = renderer.shows.count
        monitor.sendChange()
        await Task.yield()

        XCTAssertEqual(monitor.stopCount, 1)
        XCTAssertEqual(renderer.shows.count, showCount)
        XCTAssertEqual(renderer.stopCount, 1)
    }

    /// Gives the panel height that the layout rule expects on the test screen.
    private func expandedHeight(eventCount: Int) -> Double {
        NotificationIslandLayout.expandedHeight(
            eventCount: eventCount,
            cameraHousingHeight: 38
        )
    }

    private func makeController(
        renderer: RecordingIslandPanelRenderer,
        provider: (any ScreenGeometryProvider)? = nil,
        scheduler: RecordingIslandPanelScheduler? = nil,
        screenChangeMonitor: RecordingIslandScreenChangeMonitor? = nil,
        isVoiceOverEnabled: Bool = false,
        pointer: RecordingPointerLocation = RecordingPointerLocation(),
        waitsForLaunchActivation: Bool = false
    ) -> IslandPanelController {
        IslandPanelController(
            screenGeometryProvider: provider ?? SimulatedScreenGeometryProvider(
                preset: .notched14Inch
            ),
            renderer: renderer,
            scheduler: scheduler,
            screenChangeMonitor: screenChangeMonitor,
            isVoiceOverEnabled: { isVoiceOverEnabled },
            pointerIsInsideIsland: { pointer.isInside },
            waitsForLaunchActivation: waitsForLaunchActivation
        )
    }

    private func panelContent(
        for event: NotificationEvent
    ) -> NotificationIslandPanelContent {
        NotificationIslandPanelContent(
            event: event,
            serviceLabel: "Chat",
            serviceIconURL: nil
        )
    }

    private func prepareCollapsedHistory(
        controller: IslandPanelController,
        scheduler: RecordingIslandPanelScheduler,
        renderer: RecordingIslandPanelRenderer
    ) async throws {
        controller.present(panelContent(for: try makeEvent(number: 1)))
        await waitForShow(in: renderer)
        scheduler.fireNext()
        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertEqual(controller.state.recentEvents.count, 1)
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

    private func waitForShow(
        in renderer: RecordingIslandPanelRenderer
    ) async {
        for _ in 0..<20 where renderer.shows.isEmpty {
            await Task.yield()
        }
    }

    private func waitForPlacement(
        on screenIdentifier: String,
        in renderer: RecordingIslandPanelRenderer
    ) async {
        for _ in 0..<20
        where renderer.shows.last?.placement.screenIdentifier != screenIdentifier {
            await Task.yield()
        }
    }

    private func waitForHide(
        after previousCount: Int,
        in renderer: RecordingIslandPanelRenderer
    ) async {
        for _ in 0..<20 where renderer.hideCount == previousCount {
            await Task.yield()
        }
    }
}

/// Answers the island pointer question with a value that a test controls.
@MainActor
final class RecordingPointerLocation {
    var isInside: Bool

    init(isInside: Bool = false) {
        self.isInside = isInside
    }
}

@MainActor
private final class MutableIslandScreenGeometryProvider: ScreenGeometryProvider {
    var snapshot: IslandScreenSnapshot

    init(snapshot: IslandScreenSnapshot) {
        self.snapshot = snapshot
    }

    func currentSnapshot() async -> IslandScreenSnapshot {
        snapshot
    }
}

@MainActor
private final class RecordingIslandScreenChangeMonitor: IslandScreenChangeMonitoring {
    private var onChange: (@MainActor () -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        startCount += 1
    }

    func stop() {
        onChange = nil
        stopCount += 1
    }

    func sendChange() {
        onChange?()
    }
}

@MainActor
private final class RecordingIslandPanelScheduler: NotificationIslandScheduling {
    private var actions: [RecordingIslandPanelScheduledAction] = []

    var pendingDelays: [Duration] {
        actions.filter { !$0.isCancelled }.map(\.delay)
    }

    func schedule(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any NotificationIslandScheduledAction {
        let scheduledAction = RecordingIslandPanelScheduledAction(
            delay: delay,
            action: action
        )
        actions.append(scheduledAction)
        return scheduledAction
    }

    func fireNext() {
        guard let index = actions.firstIndex(where: { !$0.isCancelled }) else {
            return
        }
        let scheduledAction = actions.remove(at: index)
        scheduledAction.fire()
    }
}

@MainActor
private final class RecordingIslandPanelScheduledAction:
    NotificationIslandScheduledAction
{
    let delay: Duration
    private(set) var isCancelled = false
    private var action: (@MainActor () -> Void)?

    init(
        delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        self.delay = delay
        self.action = action
    }

    func cancel() {
        isCancelled = true
        action = nil
    }

    func fire() {
        guard !isCancelled else { return }
        let action = action
        self.action = nil
        action?()
    }
}

@MainActor
private final class RecordingIslandPanelRenderer: NotificationIslandPanelRendering {
    struct Show {
        let state: NotificationIslandState
        let content: NotificationIslandPanelContent?
        let recentContents: [NotificationIslandPanelContent]
        let appearance: NotificationIslandAppearance
        let cameraHousingSize: IslandScreenSize?
        let placement: NotificationIslandPlacement
        let actions: NotificationIslandPanelActions
    }

    private(set) var shows: [Show] = []
    private(set) var hideCount = 0
    private(set) var stopCount = 0

    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        appearance: NotificationIslandAppearance,
        cameraHousingSize: IslandScreenSize?,
        placement: NotificationIslandPlacement,
        actions: NotificationIslandPanelActions
    ) {
        shows.append(
            Show(
                state: state,
                content: content,
                recentContents: recentContents,
                appearance: appearance,
                cameraHousingSize: cameraHousingSize,
                placement: placement,
                actions: actions
            )
        )
    }

    func hide() {
        hideCount += 1
    }

    func stop() {
        stopCount += 1
    }
}
