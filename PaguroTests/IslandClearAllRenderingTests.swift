import AppKit
import PaguroCore
import XCTest
@testable import Paguro

@MainActor
final class IslandClearAllRenderingTests: XCTestCase {
    private let reducer = NotificationIslandReducer()

    func testCardsLeaveBeforeTheEmptySurfaceShrinks() async throws {
        let scheduler = ClearAnimationScheduler()
        let renderer = AppKitNotificationIslandPanelRenderer(
            clearAllScheduler: scheduler, reduceMotionEnabled: { false }
        )
        defer { renderer.stop() }
        let history = try recentState()
        show(history, in: renderer)
        try await Task.sleep(for: .milliseconds(60))
        let panel = try XCTUnwrap(NSApp.windows.first { $0.frame.midX == -20_000 })
        try saveSnapshot(panel, name: "before")
        let empty = reducer.reduce(history, action: .dismissAll)
        show(empty, in: renderer)
        let model = try XCTUnwrap(renderer.model)

        XCTAssertTrue(empty.recentEvents.isEmpty)
        XCTAssertEqual(model.recentContents.count, 3, "Only the outgoing presentation remains")
        XCTAssertTrue(model.isClearingAll)
        XCTAssertEqual(panel.frame.height, 274)
        XCTAssertEqual(scheduler.delays, [.milliseconds(310)])
        show(empty, in: renderer)
        XCTAssertEqual(scheduler.delays.count, 1, "Geometry refresh must not restart the animation")
        try await Task.sleep(for: .milliseconds(100))
        try saveSnapshot(panel, name: "stagger")
        try await Task.sleep(for: .milliseconds(240))
        try saveSnapshot(panel, name: "cards-gone")

        scheduler.fireNext()
        XCTAssertFalse(model.isClearingAll)
        XCTAssertTrue(model.recentContents.isEmpty)
        XCTAssertTrue(model.isCollapsingAfterClear, "Keep the surface until the frame reaches the notch")
        try await Task.sleep(for: .milliseconds(100))
        try saveSnapshot(panel, name: "shrinking")
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertFalse(model.isCollapsingAfterClear)
        XCTAssertEqual(panel.frame.height, 38, accuracy: 0.1)
        XCTAssertEqual(panel.frame.maxY, -500, accuracy: 0.1)
        try saveSnapshot(panel, name: "finished")
    }

    func testNewArrivalSurvivesBothClearAnimationStages() async throws {
        for duringShrink in [false, true] {
            let scheduler = ClearAnimationScheduler()
            let renderer = AppKitNotificationIslandPanelRenderer(
                clearAllScheduler: scheduler, reduceMotionEnabled: { false }
            )
            defer { renderer.stop() }
            let history = try recentState()
            show(history, in: renderer)
            let empty = reducer.reduce(history, action: .dismissAll)
            show(empty, in: renderer)
            if duringShrink { scheduler.fireNext() }

            let event = try makeEvent("A new arrival")
            let incoming = reducer.reduce(empty, action: .receive(event))
            show(incoming, in: renderer)
            scheduler.fireNext()
            try await Task.sleep(for: .milliseconds(350))

            XCTAssertEqual(renderer.model?.state.currentEvent?.id, event.id)
            XCTAssertEqual(renderer.model?.recentContents.map(\.event.id), [event.id])
            XCTAssertFalse(try XCTUnwrap(renderer.model).isClearingAll)
            XCTAssertFalse(try XCTUnwrap(renderer.model).isCollapsingAfterClear)
        }
    }

    func testHideAndStopCancelThePendingClearPresentation() throws {
        let scheduler = ClearAnimationScheduler()
        let renderer = AppKitNotificationIslandPanelRenderer(clearAllScheduler: scheduler)
        defer { renderer.stop() }
        let history = try recentState()
        show(history, in: renderer)
        let panel = try XCTUnwrap(NSApp.windows.first { $0.frame.midX == -20_000 })
        let empty = reducer.reduce(history, action: .dismissAll)
        show(empty, in: renderer)
        renderer.hide() // Lock and disabling the island use this path.
        XCTAssertTrue(scheduler.delays.isEmpty)
        scheduler.fireNext()
        XCTAssertFalse(panel.isVisible)
        show(empty, in: renderer)
        XCTAssertTrue(try XCTUnwrap(renderer.model).recentContents.isEmpty)

        show(history, in: renderer)
        show(empty, in: renderer)
        renderer.stop()
        scheduler.fireNext()
        XCTAssertTrue(scheduler.delays.isEmpty)
        XCTAssertNil(renderer.model)
        XCTAssertFalse(panel.isVisible)
    }

    func testReduceMotionUsesFadeThenAnImmediateResize() throws {
        let scheduler = ClearAnimationScheduler()
        let renderer = AppKitNotificationIslandPanelRenderer(
            clearAllScheduler: scheduler, reduceMotionEnabled: { true }
        )
        defer { renderer.stop() }
        let history = try recentState()
        show(history, in: renderer)
        show(reducer.reduce(history, action: .dismissAll), in: renderer)
        XCTAssertEqual(scheduler.delays, [.milliseconds(160)])
        scheduler.fireNext()
        let model = try XCTUnwrap(renderer.model)
        XCTAssertTrue(model.recentContents.isEmpty)
        XCTAssertFalse(model.isClearingAll)
        XCTAssertFalse(model.isCollapsingAfterClear)
    }

    private func recentState() throws -> NotificationIslandState {
        var state = NotificationIslandState.hidden
        for title in ["Coffee break", "The review is ready", "Lunch tomorrow?"] {
            state = reducer.reduce(state, action: .receive(try makeEvent(title)))
        }
        return reducer.reduce(state, action: .beginPeek)
    }

    private func makeEvent(_ title: String) throws -> NotificationEvent {
        try NotificationEvent.normalize(
            id: UUID(), serviceID: UUID(), source: .pageNotification,
            title: title, body: "A sample notification", receivedAt: Date()
        )
    }

    private func show(_ state: NotificationIslandState, in renderer: AppKitNotificationIslandPanelRenderer) {
        let contents = state.recentEvents.map {
            NotificationIslandPanelContent(event: $0, serviceLabel: "Notification Test", serviceIconURL: nil)
        }
        let empty = state.phase == .collapsed && state.recentEvents.isEmpty
        let width = empty ? 176.0 : 432.0
        let height = empty ? 38.0 : 274.0
        renderer.show(
            state: state, content: contents.first, recentContents: contents,
            appearance: NotificationIslandAppearance(glassStyle: .off, transparency: 1),
            cameraHousingSize: IslandScreenSize(width: 164, height: 38),
            placement: NotificationIslandPlacement(
                screenIdentifier: "offscreen-test", style: .cameraHousing,
                frame: IslandScreenRect(x: -20_000 - width / 2, y: -500 - height, width: width, height: height)
            ), actions: .none
        )
    }

    private func saveSnapshot(_ panel: NSWindow, name: String) throws {
        let view = try XCTUnwrap(panel.contentView)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Paguro-clear-all")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(name).png")
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        print("Clear All snapshot: \(url.path)")
    }
}

@MainActor
private final class ClearAnimationScheduler: NotificationIslandScheduling {
    private var pending: [Action] = []
    var delays: [Duration] { pending.filter { $0.body != nil }.map(\.delay) }

    func schedule(after delay: Duration, action: @escaping @MainActor () -> Void) -> any NotificationIslandScheduledAction {
        let scheduled = Action(delay: delay, body: action)
        pending.append(scheduled)
        return scheduled
    }

    func fireNext() {
        guard let index = pending.firstIndex(where: { $0.body != nil }) else { return }
        let action = pending.remove(at: index)
        action.body?()
    }

    private final class Action: NotificationIslandScheduledAction {
        let delay: Duration
        var body: (@MainActor () -> Void)?
        init(delay: Duration, body: @escaping @MainActor () -> Void) { self.delay = delay; self.body = body }
        func cancel() { body = nil }
    }
}
