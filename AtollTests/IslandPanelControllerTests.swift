import AtollCore
import Foundation
import XCTest
@testable import Atoll

@MainActor
final class IslandPanelControllerTests: XCTestCase {
    func testControllerStartsHiddenWithoutCreatingVisibleContent() {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        XCTAssertEqual(controller.state, .hidden)
        XCTAssertTrue(renderer.shows.isEmpty)
        XCTAssertEqual(renderer.hideCount, 0)
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

    func testSecondEventWaitsBehindTheVisibleEvent() async throws {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)
        let firstEvent = try makeEvent(number: 1)
        let secondEvent = try makeEvent(number: 2)

        controller.present(panelContent(for: firstEvent))
        controller.present(panelContent(for: secondEvent))
        await waitForShow(in: renderer)

        XCTAssertEqual(controller.state.currentEvent, firstEvent)
        XCTAssertEqual(controller.state.queuedEvents, [secondEvent])
        XCTAssertEqual(renderer.shows.last?.state.pendingCount, 1)
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

        XCTAssertEqual(scheduler.pendingDelays, [.seconds(6)])
        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .dismissed)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])

        scheduler.fireNext()
        XCTAssertEqual(controller.state.phase, .collapsed)
        XCTAssertTrue(scheduler.pendingDelays.isEmpty)
    }

    func testQueuedAlertGetsItsOwnFullDisplayTime() async throws {
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

        XCTAssertEqual(scheduler.pendingDelays, [.seconds(6)])
        scheduler.fireNext()
        scheduler.fireNext()

        XCTAssertEqual(controller.state.currentEvent, secondEvent)
        XCTAssertEqual(controller.state.phase, .alert)
        XCTAssertEqual(scheduler.pendingDelays, [.seconds(6)])
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

    func testOpeningAnAlertRequestsItsServiceAndStartsDismissal() async throws {
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
        renderer.shows.last?.primaryAction?()

        XCTAssertEqual(requestedServiceIDs, [event.serviceID])
        XCTAssertEqual(controller.state.phase, .dismissed)
        XCTAssertEqual(scheduler.pendingDelays, [.milliseconds(180)])
    }

    func testCollapsedIslandHasNoPointerAction() async {
        let renderer = RecordingIslandPanelRenderer()
        let controller = makeController(renderer: renderer)

        controller.showCollapsed()
        await waitForShow(in: renderer)

        XCTAssertNil(renderer.shows.last?.primaryAction)
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

    private func makeController(
        renderer: RecordingIslandPanelRenderer,
        provider: (any ScreenGeometryProvider)? = nil,
        scheduler: RecordingIslandPanelScheduler? = nil,
        screenChangeMonitor: RecordingIslandScreenChangeMonitor? = nil,
        isVoiceOverEnabled: Bool = false
    ) -> IslandPanelController {
        IslandPanelController(
            screenGeometryProvider: provider ?? SimulatedScreenGeometryProvider(
                preset: .notched14Inch
            ),
            renderer: renderer,
            scheduler: scheduler,
            screenChangeMonitor: screenChangeMonitor,
            isVoiceOverEnabled: { isVoiceOverEnabled }
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
        let placement: NotificationIslandPlacement
        let primaryAction: NotificationIslandPanelAction?
    }

    private(set) var shows: [Show] = []
    private(set) var hideCount = 0
    private(set) var stopCount = 0

    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        placement: NotificationIslandPlacement,
        primaryAction: NotificationIslandPanelAction?
    ) {
        shows.append(
            Show(
                state: state,
                content: content,
                placement: placement,
                primaryAction: primaryAction
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
