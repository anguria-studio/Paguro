import AppKit
import AtollCore
import SwiftUI

/// Display content that belongs to one normalized island event.
struct NotificationIslandPanelContent: Equatable {
    let event: NotificationEvent
    let serviceLabel: String
    let serviceIconURL: URL?
}

/// Separates island state coordination from the AppKit panel.
@MainActor
protocol NotificationIslandPanelRendering: AnyObject {
    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        placement: NotificationIslandPlacement
    )

    func hide()
    func stop()
}

/// A scheduled island action that the controller can cancel.
@MainActor
protocol NotificationIslandScheduledAction: AnyObject {
    func cancel()
}

/// Schedules island transitions without putting timing rules in the renderer.
@MainActor
protocol NotificationIslandScheduling: AnyObject {
    func schedule(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any NotificationIslandScheduledAction
}

/// Runs production island transitions on the main actor.
@MainActor
private final class TaskNotificationIslandScheduler: NotificationIslandScheduling {
    func schedule(
        after delay: Duration,
        action: @escaping @MainActor () -> Void
    ) -> any NotificationIslandScheduledAction {
        TaskNotificationIslandScheduledAction(delay: delay, action: action)
    }
}

@MainActor
private final class TaskNotificationIslandScheduledAction:
    NotificationIslandScheduledAction
{
    private var task: Task<Void, Never>?

    init(
        delay: Duration,
        action: @escaping @MainActor () -> Void
    ) {
        task = Task { @MainActor in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// Coordinates island state, screen placement, and its optional panel.
@MainActor
final class IslandPanelController {
    private(set) var state: NotificationIslandState = .hidden

    private let screenGeometryProvider: any ScreenGeometryProvider
    private let renderer: any NotificationIslandPanelRendering
    private let reducer: NotificationIslandReducer
    private let scheduler: any NotificationIslandScheduling
    private let timing: NotificationIslandTiming
    private let isVoiceOverEnabled: @MainActor () -> Bool
    private var contentByEventID: [UUID: NotificationIslandPanelContent] = [:]
    private var selectedScreen: IslandScreenGeometry?
    private var geometryTask: Task<Void, Never>?
    private var alertAction: (any NotificationIslandScheduledAction)?
    private var dismissalAction: (any NotificationIslandScheduledAction)?
    private var hasStopped = false

    init(
        screenGeometryProvider: any ScreenGeometryProvider,
        renderer: (any NotificationIslandPanelRendering)? = nil,
        reducer: NotificationIslandReducer = NotificationIslandReducer(),
        scheduler: (any NotificationIslandScheduling)? = nil,
        timing: NotificationIslandTiming = .standard,
        isVoiceOverEnabled: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.isVoiceOverEnabled
        }
    ) {
        self.screenGeometryProvider = screenGeometryProvider
        self.renderer = renderer ?? AppKitNotificationIslandPanelRenderer()
        self.reducer = reducer
        self.scheduler = scheduler ?? TaskNotificationIslandScheduler()
        self.timing = timing
        self.isVoiceOverEnabled = isVoiceOverEnabled
    }

    func present(_ content: NotificationIslandPanelContent) {
        guard !hasStopped else { return }
        let previousEventID = state.currentEvent?.id
        contentByEventID[content.event.id] = content
        apply(.receive(content.event))
        if state.currentEvent?.id != previousEventID {
            scheduleAlertDismissalIfNeeded()
        }
        refreshScreenGeometry()
    }

    func showCollapsed() {
        guard !hasStopped else { return }
        apply(.showCollapsed)
        refreshScreenGeometry()
    }

    func expand() {
        apply(.expand)
        if state.phase == .expanded {
            cancelAlertAction()
        }
    }

    func collapse() {
        apply(.collapse)
        scheduleAlertDismissalIfNeeded()
    }

    func dismissCurrent() {
        cancelAlertAction()
        apply(.dismissCurrent)
        scheduleDismissalCompletionIfNeeded()
    }

    func finishDismissal() {
        cancelDismissalAction()
        apply(.finishDismissal)
        scheduleAlertDismissalIfNeeded()
    }

    func hide() {
        cancelScheduledActions()
        apply(.hide)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        cancelScheduledActions()
        geometryTask?.cancel()
        geometryTask = nil
        selectedScreen = nil
        state = reducer.reduce(state, action: .stop)
        contentByEventID.removeAll()
        renderer.stop()
    }

    private func scheduleAlertDismissalIfNeeded() {
        guard state.phase == .alert, let eventID = state.currentEvent?.id else {
            return
        }
        cancelAlertAction()
        let delay = timing.alertDuration(
            isVoiceOverEnabled: isVoiceOverEnabled()
        )
        alertAction = scheduler.schedule(after: delay) { [weak self] in
            guard let self,
                  self.state.phase == .alert,
                  self.state.currentEvent?.id == eventID else {
                return
            }
            self.alertAction = nil
            self.dismissCurrent()
        }
    }

    private func scheduleDismissalCompletionIfNeeded() {
        guard state.phase == .dismissed,
              let eventID = state.currentEvent?.id else {
            return
        }
        cancelDismissalAction()
        dismissalAction = scheduler.schedule(
            after: timing.dismissalDuration
        ) { [weak self] in
            guard let self,
                  self.state.phase == .dismissed,
                  self.state.currentEvent?.id == eventID else {
                return
            }
            self.dismissalAction = nil
            self.finishDismissal()
        }
    }

    private func cancelScheduledActions() {
        cancelAlertAction()
        cancelDismissalAction()
    }

    private func cancelAlertAction() {
        alertAction?.cancel()
        alertAction = nil
    }

    private func cancelDismissalAction() {
        dismissalAction?.cancel()
        dismissalAction = nil
    }

    private func apply(_ action: NotificationIslandAction) {
        guard !hasStopped else { return }
        state = reducer.reduce(state, action: action)
        removeUnusedContent()
        render()
    }

    private func refreshScreenGeometry() {
        geometryTask?.cancel()
        let provider = screenGeometryProvider
        geometryTask = Task { @MainActor [weak self] in
            let snapshot = await provider.currentSnapshot()
            guard !Task.isCancelled, let self, !self.hasStopped else { return }
            self.selectedScreen = snapshot.selectedScreen
            self.render()
        }
    }

    private func render() {
        guard state.phase != .hidden else {
            renderer.hide()
            return
        }
        guard let selectedScreen else { return }
        let size = desiredSize(for: state.phase, on: selectedScreen)
        guard let placement = NotificationIslandGeometryPolicy.placement(
            on: selectedScreen,
            desiredSize: size
        ) else {
            renderer.hide()
            return
        }

        let content = state.currentEvent.flatMap { event in
            contentByEventID[event.id]
        }
        renderer.show(
            state: state,
            content: content,
            placement: placement
        )
    }

    private func desiredSize(
        for phase: NotificationIslandPhase,
        on screen: IslandScreenGeometry
    ) -> IslandScreenSize {
        switch phase {
        case .hidden:
            return IslandScreenSize(width: 0, height: 0)
        case .collapsed:
            if let housing = screen.cameraHousingFrame {
                return housing.size
            }
            return IslandScreenSize(width: 220, height: 44)
        case .alert, .dismissed:
            return IslandScreenSize(width: 360, height: 96)
        case .expanded:
            return IslandScreenSize(width: 420, height: 300)
        }
    }

    private func removeUnusedContent() {
        let eventIDs = [state.currentEvent]
            .compactMap { $0?.id }
            + state.queuedEvents.map(\.id)
        let retainedEventIDs = Set(eventIDs)
        contentByEventID = contentByEventID.filter { eventID, _ in
            retainedEventIDs.contains(eventID)
        }
    }
}

/// Adds service display values before the shared panel controller receives an event.
@MainActor
final class IslandNotificationPresenter: NotificationEventPresenting {
    private let controller: IslandPanelController
    private let serviceLabel: String
    private let serviceIconURL: URL?

    init(
        controller: IslandPanelController,
        serviceLabel: String,
        serviceIconURL: URL?
    ) {
        self.controller = controller
        self.serviceLabel = serviceLabel
        self.serviceIconURL = serviceIconURL
    }

    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    ) {
        controller.present(
            NotificationIslandPanelContent(
                event: event,
                serviceLabel: serviceLabel,
                serviceIconURL: serviceIconURL
            )
        )
        AppLogger.notifications.info(
            "Notification trace \(traceID, privacy: .public): island accepted request \(requestID, privacy: .public)"
        )
    }
}

/// Owns the lazy, nonactivating AppKit panel.
@MainActor
private final class AppKitNotificationIslandPanelRenderer:
    NotificationIslandPanelRendering
{
    private var panel: NSPanel?

    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        placement: NotificationIslandPlacement
    ) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(
            rootView: NotificationIslandPanelView(
                state: state,
                content: content,
                placementStyle: placement.style
            )
        )
        panel.setFrame(placement.frame.appKitRect, display: true)
        panel.hasShadow = placement.style == .floating
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func stop() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        self.panel = panel
        return panel
    }
}

private struct NotificationIslandPanelView: View {
    let state: NotificationIslandState
    let content: NotificationIslandPanelContent?
    let placementStyle: NotificationIslandPlacementStyle

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        Group {
            if let content {
                HStack(spacing: 12) {
                    serviceIcon(for: content)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(content.serviceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(content.event.title)
                            .font(.headline)
                            .lineLimit(1)
                        if let body = content.event.body {
                            Text(body)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)

                    if let countLabel = NotificationIslandCounterLabel.text(
                        for: state.pendingCount
                    ) {
                        Text(countLabel)
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: .capsule)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else {
                Image(systemName: "bell.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(placementStyle == .cameraHousing ? .black : .clear)
        }
        .glassEffect(.regular, in: shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private func serviceIcon(for content: NotificationIslandPanelContent) -> some View {
        if let iconURL = content.serviceIconURL,
           let image = NSImage(contentsOf: iconURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .clipShape(.rect(cornerRadius: 8))
        } else {
            Image(systemName: "bell.fill")
                .frame(width: 34, height: 34)
                .background(.quaternary, in: .rect(cornerRadius: 8))
        }
    }

    private var accessibilityLabel: String {
        guard let content else { return "Atoll notification island" }
        if let body = content.event.body {
            return "\(content.serviceLabel), \(content.event.title), \(body)"
        }
        return "\(content.serviceLabel), \(content.event.title)"
    }
}

private extension IslandScreenRect {
    var appKitRect: CGRect {
        CGRect(x: minX, y: minY, width: size.width, height: size.height)
    }
}
