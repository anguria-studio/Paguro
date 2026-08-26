import AppKit
import AtollCore
import SwiftUI

/// Display content that belongs to one normalized island event.
struct NotificationIslandPanelContent: Equatable {
    let event: NotificationEvent
    let serviceLabel: String
    let serviceIconURL: URL?
}

/// Runs the one pointer action that the current island state permits.
typealias NotificationIslandPanelAction = @MainActor () -> Void

/// Keeps panel controls separate from notification state and display content.
struct NotificationIslandPanelActions {
    let primary: NotificationIslandPanelAction?
    let collapse: NotificationIslandPanelAction?
    let openEvent: (@MainActor (UUID) -> Void)?

    var acceptsPointerEvents: Bool {
        primary != nil || collapse != nil || openEvent != nil
    }

    static let none = NotificationIslandPanelActions(
        primary: nil,
        collapse: nil,
        openEvent: nil
    )
}

/// Separates island state coordination from the AppKit panel.
@MainActor
protocol NotificationIslandPanelRendering: AnyObject {
    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        placement: NotificationIslandPlacement,
        actions: NotificationIslandPanelActions
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
    var onServiceRequested: (@MainActor (UUID) -> Void)?
    var canPresentIsland: Bool {
        selectedScreen?.hasCameraHousing == true
    }

    private let screenGeometryProvider: any ScreenGeometryProvider
    private let renderer: any NotificationIslandPanelRendering
    private let reducer: NotificationIslandReducer
    private let scheduler: any NotificationIslandScheduling
    private let screenChangeMonitor: any IslandScreenChangeMonitoring
    private let timing: NotificationIslandTiming
    private let isVoiceOverEnabled: @MainActor () -> Bool
    private var contentByEventID: [UUID: NotificationIslandPanelContent] = [:]
    private var selectedScreen: IslandScreenGeometry?
    private var geometryTask: Task<Void, Never>?
    private var alertAction: (any NotificationIslandScheduledAction)?
    private var dismissalAction: (any NotificationIslandScheduledAction)?
    private var isTrackingGeometryChanges = false
    private var hasStopped = false

    init(
        screenGeometryProvider: any ScreenGeometryProvider,
        renderer: (any NotificationIslandPanelRendering)? = nil,
        reducer: NotificationIslandReducer = NotificationIslandReducer(),
        scheduler: (any NotificationIslandScheduling)? = nil,
        screenChangeMonitor: (any IslandScreenChangeMonitoring)? = nil,
        timing: NotificationIslandTiming = .standard,
        isVoiceOverEnabled: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.isVoiceOverEnabled
        }
    ) {
        self.screenGeometryProvider = screenGeometryProvider
        self.renderer = renderer ?? AppKitNotificationIslandPanelRenderer()
        self.reducer = reducer
        self.scheduler = scheduler ?? TaskNotificationIslandScheduler()
        self.screenChangeMonitor = screenChangeMonitor
            ?? IslandScreenChangeMonitor()
        self.timing = timing
        self.isVoiceOverEnabled = isVoiceOverEnabled
    }

    func present(_ content: NotificationIslandPanelContent) {
        guard !hasStopped else { return }
        startGeometryTracking()
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
        startGeometryTracking()
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

    func openCurrentService() {
        guard !hasStopped,
              state.phase == .alert,
              let event = state.currentEvent else {
            return
        }
        onServiceRequested?(event.serviceID)
        apply(.removeRecentEvent(event.id))
        dismissCurrent()
    }

    func openRecentEvent(_ eventID: UUID) {
        guard !hasStopped,
              state.phase == .expanded,
              let event = state.recentEvents.first(where: { $0.id == eventID })
        else { return }
        onServiceRequested?(event.serviceID)
        apply(.removeRecentEvent(eventID))
        if state.currentEvent?.id == eventID {
            dismissCurrent()
        } else {
            collapse()
        }
    }

    func hide() {
        cancelScheduledActions()
        stopGeometryTracking()
        apply(.hide)
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        cancelScheduledActions()
        stopGeometryTracking()
        state = reducer.reduce(state, action: .stop)
        contentByEventID.removeAll()
        renderer.stop()
    }

    private func startGeometryTracking() {
        guard !isTrackingGeometryChanges else { return }
        isTrackingGeometryChanges = true
        screenChangeMonitor.start { [weak self] in
            self?.refreshScreenGeometry()
        }
    }

    private func stopGeometryTracking() {
        guard isTrackingGeometryChanges else { return }
        isTrackingGeometryChanges = false
        screenChangeMonitor.stop()
        geometryTask?.cancel()
        geometryTask = nil
        selectedScreen = nil
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
        guard selectedScreen.hasCameraHousing else {
            renderer.hide()
            return
        }
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
        let recentContents = state.recentEvents.compactMap { event in
            contentByEventID[event.id]
        }
        renderer.show(
            state: state,
            content: content,
            recentContents: recentContents,
            placement: placement,
            actions: panelActions
        )
    }

    private var panelActions: NotificationIslandPanelActions {
        switch state.phase {
        case .collapsed:
            return NotificationIslandPanelActions(
                primary: { [weak self] in self?.expand() },
                collapse: nil,
                openEvent: nil
            )
        case .alert where state.currentEvent != nil:
            return NotificationIslandPanelActions(
                primary: { [weak self] in self?.openCurrentService() },
                collapse: nil,
                openEvent: nil
            )
        case .expanded:
            return NotificationIslandPanelActions(
                primary: nil,
                collapse: { [weak self] in self?.collapse() },
                openEvent: { [weak self] eventID in
                    self?.openRecentEvent(eventID)
                }
            )
        case .hidden, .alert, .dismissed:
            return .none
        }
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
            return IslandScreenSize(width: 420, height: 360)
        }
    }

    private func removeUnusedContent() {
        let eventIDs = [state.currentEvent]
            .compactMap { $0?.id }
            + state.queuedEvents.map(\.id)
            + state.recentEvents.map(\.id)
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
    private var panel: NotificationIslandPanel?

    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        placement: NotificationIslandPlacement,
        actions: NotificationIslandPanelActions
    ) {
        let panel = panel ?? makePanel()
        panel.contentView = NSHostingView(
            rootView: NotificationIslandPanelView(
                state: state,
                content: content,
                recentContents: recentContents,
                actions: actions
            )
        )
        panel.setFrame(placement.frame.appKitRect, display: true)
        panel.hasShadow = false
        panel.ignoresMouseEvents = !actions.acceptsPointerEvents
        if state.phase != .expanded, panel.isKeyWindow {
            panel.resignKey()
        }
        panel.acceptsKeyWindow = state.phase == .expanded
        panel.becomesKeyOnlyIfNeeded = state.phase != .expanded
        if state.phase == .expanded {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func stop() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
    }

    private func makePanel() -> NotificationIslandPanel {
        let panel = NotificationIslandPanel(
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
        panel.becomesKeyOnlyIfNeeded = true
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

/// Accepts keyboard focus only after the user opens the expanded island.
private final class NotificationIslandPanel: NSPanel {
    var acceptsKeyWindow = false

    override var canBecomeKey: Bool { acceptsKeyWindow }
    override var canBecomeMain: Bool { false }
}

private struct NotificationIslandPanelView: View {
    private enum FocusTarget: Hashable {
        case close
        case event(UUID)
    }

    let state: NotificationIslandState
    let content: NotificationIslandPanelContent?
    let recentContents: [NotificationIslandPanelContent]
    let actions: NotificationIslandPanelActions

    @FocusState private var focusedControl: FocusTarget?

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
    }

    var body: some View {
        Group {
            if state.phase == .expanded {
                expandedContent
            } else {
                compactContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            shape.fill(.black)
        }
        .glassEffect(.regular, in: shape)
        .onExitCommand {
            actions.collapse?()
        }
    }

    @ViewBuilder
    private var compactContent: some View {
        if let primaryAction = actions.primary {
            Button(action: primaryAction) {
                compactLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help(openHelp)
            .accessibilityLabel(compactAccessibilityLabel)
        } else {
            compactLabel
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compactAccessibilityLabel)
        }
    }

    @ViewBuilder
    private var compactLabel: some View {
        if let content {
            HStack(spacing: 12) {
                serviceIcon(for: content, size: 34)

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

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Recent notifications")
                    .font(.headline)

                Spacer(minLength: 8)

                Button(action: { actions.collapse?() }) {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .focusable()
                .focused($focusedControl, equals: .close)
                .background(
                    focusedControl == .close
                        ? Color.white.opacity(0.22)
                        : Color.white.opacity(0.10),
                    in: .circle
                )
                .help("Close recent notifications")
                .accessibilityLabel("Close recent notifications")
            }

            if recentContents.isEmpty {
                ContentUnavailableView(
                    "No Recent Notifications",
                    systemImage: "bell.slash",
                    description: Text("New Atoll alerts appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(recentContents, id: \.event.id) { recentContent in
                        recentEventButton(recentContent)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .onAppear {
            focusFirstExpandedControl()
        }
        .onKeyPress(.return) {
            activateFocusedControl() ? .handled : .ignored
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Atoll recent notifications")
    }

    private func recentEventButton(
        _ recentContent: NotificationIslandPanelContent
    ) -> some View {
        Button {
            actions.openEvent?(recentContent.event.id)
        } label: {
            HStack(spacing: 10) {
                serviceIcon(for: recentContent, size: 30)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(recentContent.serviceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(recentContent.event.receivedAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(recentContent.event.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    if let body = recentContent.event.body {
                        Text(body)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.up.forward")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .focusable()
        .focused(
            $focusedControl,
            equals: .event(recentContent.event.id)
        )
        .background(
            focusedControl == .event(recentContent.event.id)
                ? Color.white.opacity(0.22)
                : Color.white.opacity(0.10),
            in: .rect(cornerRadius: 12)
        )
        .help("Open \(recentContent.serviceLabel)")
        .accessibilityLabel(recentAccessibilityLabel(for: recentContent))
    }

    @ViewBuilder
    private func serviceIcon(
        for content: NotificationIslandPanelContent,
        size: CGFloat
    ) -> some View {
        if let iconURL = content.serviceIconURL,
           let image = NSImage(contentsOf: iconURL) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size / 4))
        } else {
            Image(systemName: "bell.fill")
                .frame(width: size, height: size)
                .background(.quaternary, in: .rect(cornerRadius: size / 4))
        }
    }

    private var compactAccessibilityLabel: String {
        guard let content else { return "Atoll notification island" }
        if let body = content.event.body {
            return "\(content.serviceLabel), \(content.event.title), \(body)"
        }
        return "\(content.serviceLabel), \(content.event.title)"
    }

    private var openHelp: String {
        guard let content else { return "Open recent notifications" }
        return "Open \(content.serviceLabel)"
    }

    private func recentAccessibilityLabel(
        for content: NotificationIslandPanelContent
    ) -> String {
        if let body = content.event.body {
            return "\(content.serviceLabel), \(content.event.title), \(body)"
        }
        return "\(content.serviceLabel), \(content.event.title)"
    }

    private func focusFirstExpandedControl() {
        let target = recentContents.first.map {
            FocusTarget.event($0.event.id)
        } ?? .close
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            focusedControl = target
        }
    }

    private func activateFocusedControl() -> Bool {
        switch focusedControl {
        case .close:
            guard let collapse = actions.collapse else { return false }
            collapse()
            return true
        case let .event(eventID):
            guard let openEvent = actions.openEvent else { return false }
            openEvent(eventID)
            return true
        case nil:
            return false
        }
    }
}

private extension IslandScreenRect {
    var appKitRect: CGRect {
        CGRect(x: minX, y: minY, width: size.width, height: size.height)
    }
}
