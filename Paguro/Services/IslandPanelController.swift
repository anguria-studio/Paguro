import AppKit
import PaguroCore
import Observation
import SwiftUI

/// Display content that belongs to one normalized island event.
struct NotificationIslandPanelContent: Equatable {
    /// Largest thumbnail side. The card draws the icon at 30 points.
    private static let iconThumbnailSide = 64.0

    let event: NotificationEvent
    let serviceLabel: String
    let serviceIconURL: URL?

    /// The service icon as a small bitmap.
    ///
    /// The view must not read the icon file, because a scroll movement draws
    /// the card again. This value therefore holds one thumbnail that the app
    /// makes one time for each event.
    let serviceIcon: NSImage?

    init(
        event: NotificationEvent,
        serviceLabel: String,
        serviceIconURL: URL?
    ) {
        self.event = event
        self.serviceLabel = serviceLabel
        self.serviceIconURL = serviceIconURL
        self.serviceIcon = Self.thumbnail(for: serviceIconURL)
    }

    /// Compares the display values. The icon comes from the icon address.
    static func == (
        lhs: NotificationIslandPanelContent,
        rhs: NotificationIslandPanelContent
    ) -> Bool {
        lhs.event == rhs.event
            && lhs.serviceLabel == rhs.serviceLabel
            && lhs.serviceIconURL == rhs.serviceIconURL
    }

    /// Reads the icon file one time and gives a small bitmap.
    private static func thumbnail(for iconURL: URL?) -> NSImage? {
        guard let iconURL, let icon = NSImage(contentsOf: iconURL) else {
            return nil
        }
        let side = iconThumbnailSide
        let thumbnailSize = NSSize(width: side, height: side)
        let iconSize = icon.size
        guard iconSize.width > 0, iconSize.height > 0 else { return nil }
        let scale = min(side / iconSize.width, side / iconSize.height)
        let drawnSize = NSSize(
            width: iconSize.width * scale,
            height: iconSize.height * scale
        )
        let drawnOrigin = NSPoint(
            x: (side - drawnSize.width) / 2,
            y: (side - drawnSize.height) / 2
        )
        let thumbnail = NSImage(size: thumbnailSize)
        thumbnail.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(
            in: NSRect(origin: drawnOrigin, size: drawnSize),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        thumbnail.unlockFocus()
        return thumbnail
    }
}

/// The shared Paguro appearance values that apply to the island surface.
struct NotificationIslandAppearance: Equatable {
    let glassStyle: ShellGlassStyle
    let transparency: Double

    static let defaultValue = NotificationIslandAppearance(
        glassStyle: GlassLabDefaults.style,
        transparency: GlassLabDefaults.transparency
    )

    init(glassStyle: ShellGlassStyle, transparency: Double) {
        self.glassStyle = glassStyle
        self.transparency = GlassIntensityScale.normalized(transparency)
    }
}

/// Runs the one pointer action that the current island state permits.
typealias NotificationIslandPanelAction = @MainActor () -> Void

/// Keeps panel controls separate from notification state and display content.
struct NotificationIslandPanelActions {
    let primary: NotificationIslandPanelAction?
    let pin: NotificationIslandPanelAction?
    let collapse: NotificationIslandPanelAction?
    let openEvent: (@MainActor (UUID) -> Void)?
    let dismissEvent: (@MainActor (UUID) -> Void)?
    let dismissAll: NotificationIslandPanelAction?
    let hoverChanged: (@MainActor (Bool) -> Void)?

    var acceptsPointerEvents: Bool {
        primary != nil
            || pin != nil
            || collapse != nil
            || openEvent != nil
            || dismissEvent != nil
            || dismissAll != nil
            || hoverChanged != nil
    }

    static let none = NotificationIslandPanelActions(
        primary: nil,
        pin: nil,
        collapse: nil,
        openEvent: nil,
        dismissEvent: nil,
        dismissAll: nil,
        hoverChanged: nil
    )
}

/// Separates island state coordination from the AppKit panel.
@MainActor
protocol NotificationIslandPanelRendering: AnyObject {
    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        appearance: NotificationIslandAppearance,
        cameraHousingSize: IslandScreenSize?,
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
    private(set) var appearance: NotificationIslandAppearance
    var onServiceRequested: (@MainActor (UUID) -> Void)?
    var onHistoryAvailabilityChanged: (@MainActor (Bool) -> Void)?
    private var openedFromKeyboard = false
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
    private var currentPlacement: NotificationIslandPlacement?
    private var geometryTask: Task<Void, Never>?
    private var alertAction: (any NotificationIslandScheduledAction)?
    private var dismissalAction: (any NotificationIslandScheduledAction)?
    private var hoverExitAction: (any NotificationIslandScheduledAction)?
    private var isTrackingGeometryChanges = false
    private var hasStopped = false

    /// Tells whether the island may put its panel on screen.
    ///
    /// The panel is a non-activating panel at the status-bar level. Ordering it
    /// while AppKit is still bringing the main window forward joins the launch
    /// activation and can leave that window behind the application that started
    /// Paguro, so the island holds every render until the launch settles.
    private var hasLaunchActivationSettled: Bool

    /// Answers if the pointer is over the island at this moment.
    ///
    /// SwiftUI reports one pointer exit while the panel frame moves and at the
    /// top screen edge. The island asks this question again before it closes.
    private let pointerIsInsideIsland: (@MainActor () -> Bool)?

    init(
        screenGeometryProvider: any ScreenGeometryProvider,
        renderer: (any NotificationIslandPanelRendering)? = nil,
        reducer: NotificationIslandReducer = NotificationIslandReducer(),
        scheduler: (any NotificationIslandScheduling)? = nil,
        screenChangeMonitor: (any IslandScreenChangeMonitoring)? = nil,
        timing: NotificationIslandTiming = .standard,
        appearance: NotificationIslandAppearance = .defaultValue,
        isVoiceOverEnabled: @escaping @MainActor () -> Bool = {
            NSWorkspace.shared.isVoiceOverEnabled
        },
        pointerIsInsideIsland: (@MainActor () -> Bool)? = nil,
        waitsForLaunchActivation: Bool = false
    ) {
        self.hasLaunchActivationSettled = !waitsForLaunchActivation
        self.pointerIsInsideIsland = pointerIsInsideIsland
        self.screenGeometryProvider = screenGeometryProvider
        self.renderer = renderer ?? AppKitNotificationIslandPanelRenderer()
        self.reducer = reducer
        self.scheduler = scheduler ?? TaskNotificationIslandScheduler()
        self.screenChangeMonitor = screenChangeMonitor
            ?? IslandScreenChangeMonitor()
        self.timing = timing
        self.appearance = appearance
        self.isVoiceOverEnabled = isVoiceOverEnabled
    }

    /// Reports that the application launch activation has finished.
    ///
    /// The island draws the state it already holds, so a collapsed island
    /// requested during `startAfterLaunch` appears here rather than during the
    /// launch itself.
    func launchActivationDidSettle() {
        guard !hasLaunchActivationSettled else { return }
        hasLaunchActivationSettled = true
        guard !hasStopped else { return }
        render()
    }

    func updateAppearance(_ appearance: NotificationIslandAppearance) {
        guard !hasStopped else { return }
        self.appearance = appearance
        render()
    }

    func present(_ content: NotificationIslandPanelContent) {
        guard !hasStopped, !isLocked else { return }
        cancelHoverExitAction()
        cancelDismissalAction()
        startGeometryTracking()
        contentByEventID[content.event.id] = content
        apply(.receive(content.event))
        scheduleAlertDismissalIfNeeded()
        refreshScreenGeometry()
    }

    func showCollapsed() {
        guard !hasStopped, !isLocked else { return }
        startGeometryTracking()
        apply(.showCollapsed)
        refreshScreenGeometry()
    }

    func expand() {
        guard !isLocked else { return }
        cancelHoverExitAction()
        apply(.expand)
        if state.phase == .expanded {
            cancelAlertAction()
        }
    }

    func openFromKeyboard() {
        guard !hasStopped, !isLocked, canPresentIsland,
              !state.recentEvents.isEmpty else { return }
        cancelScheduledActions()
        if state.phase == .dismissed {
            reduce(.suspendPresentation)
        }
        openedFromKeyboard = true
        apply(.expand)
    }

    func collapse() {
        if openedFromKeyboard {
            cancelScheduledActions()
            apply(.suspendPresentation)
            return
        }
        openedFromKeyboard = false
        cancelHoverExitAction()
        if state.phase == .peek {
            apply(.endPeek)
        } else {
            apply(.collapse)
        }
        scheduleAlertDismissalIfNeeded()
    }

    func setHovering(_ isHovering: Bool) {
        guard !hasStopped else { return }
        if isHovering {
            cancelHoverExitAction()
            cancelAlertAction()
            apply(.beginPeek)
        } else {
            scheduleHoverExitIfNeeded()
        }
    }

    func expireCurrent() {
        cancelAlertAction()
        apply(.expireCurrent)
        scheduleDismissalCompletionIfNeeded()
    }

    func dismissEvent(_ eventID: UUID) {
        guard !isLocked else { return }
        cancelAlertAction()
        apply(.dismissEvent(eventID))
        scheduleDismissalCompletionIfNeeded()
    }

    /// Removes every island event of one service account.
    ///
    /// The user reads that conversation in Paguro, so those events are no longer
    /// new. The island lowers its unreviewed count by the number of events that
    /// it removes.
    func dismissEvents(forService serviceID: UUID) {
        guard !hasStopped, !isLocked else { return }
        let holdsCurrentEvent = state.currentEvent?.serviceID == serviceID
        let holdsRecentEvent = state.recentEvents.contains {
            $0.serviceID == serviceID
        }
        guard holdsCurrentEvent || holdsRecentEvent else { return }

        if holdsCurrentEvent {
            cancelAlertAction()
        }
        apply(.dismissEvents(serviceID: serviceID))
        scheduleDismissalCompletionIfNeeded()
    }

    func dismissAll() {
        guard !isLocked else { return }
        cancelScheduledActions()
        apply(.dismissAll)
    }

    func finishDismissal() {
        cancelDismissalAction()
        apply(.finishDismissal)
        scheduleAlertDismissalIfNeeded()
    }

    func openRecentEvent(_ eventID: UUID) {
        guard !hasStopped,
              state.phase == .peek || state.phase == .expanded,
              let event = state.recentEvents.first(where: { $0.id == eventID })
        else { return }
        let openingPhase = state.phase
        onServiceRequested?(event.serviceID)
        dismissEvent(eventID)
        if openingPhase == .peek, state.phase == .peek {
            collapse()
        } else if openingPhase == .expanded, state.phase == .expanded {
            collapse()
        }
    }

    func hide() {
        cancelScheduledActions()
        stopGeometryTracking()
        apply(.hide)
    }

    private var isLocked = false

    func setLocked(_ locked: Bool) {
        guard !hasStopped, locked != isLocked else { return }
        isLocked = locked
        if locked {
            cancelScheduledActions()
            stopGeometryTracking()
            reduce(.suspendPresentation)
            renderer.hide()
        } else if state.phase != .hidden {
            startGeometryTracking()
            refreshScreenGeometry()
        }
    }

    func stop() {
        guard !hasStopped else { return }
        hasStopped = true
        cancelScheduledActions()
        stopGeometryTracking()
        state = reducer.reduce(state, action: .stop)
        onHistoryAvailabilityChanged?(false)
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
            self.expireCurrent()
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

    private func scheduleHoverExitIfNeeded() {
        guard !openedFromKeyboard else { return }
        guard state.phase == .peek || state.phase == .expanded else { return }
        cancelHoverExitAction()
        scheduleHoverExitCheck(after: .milliseconds(180), from: state.phase)
    }

    /// Asks for the pointer position again before the island closes.
    ///
    /// The panel frame moves while the island opens, so SwiftUI can report one
    /// pointer exit while the pointer stays over the island. The island then
    /// waits and asks again.
    private func scheduleHoverExitCheck(
        after delay: Duration,
        from exitPhase: NotificationIslandPhase
    ) {
        hoverExitAction = scheduler.schedule(after: delay) { [weak self] in
            guard let self, !self.openedFromKeyboard, self.state.phase == exitPhase else {
                self?.hoverExitAction = nil
                return
            }
            guard !self.isPointerInsideIsland() else {
                self.scheduleHoverExitCheck(
                    after: .milliseconds(250),
                    from: exitPhase
                )
                return
            }
            self.hoverExitAction = nil
            self.completeHoverExit()
        }
    }

    /// Tells if the pointer is over the island.
    ///
    /// The area keeps a small margin at each side and below the panel. It goes
    /// to the top screen edge, because the pointer can reach that edge while it
    /// stays over the island.
    private func isPointerInsideIsland() -> Bool {
        if let pointerIsInsideIsland {
            return pointerIsInsideIsland()
        }
        guard let currentPlacement else { return false }
        return Self.pointerIsInside(
            NSEvent.mouseLocation,
            panelFrame: currentPlacement.frame.appKitRect,
            screenTopY: selectedScreen?.frame.maxY
        )
    }

    /// The margin that the pointer test adds beside and below the island.
    static let pointerTestMargin = 6.0

    /// Gives the pointer test frame in AppKit screen coordinates.
    ///
    /// The frame adds the margin at the two sides and at the bottom. It reaches
    /// the top screen edge, because the island hangs from that edge and the
    /// pointer stays over the island there.
    static func pointerTestFrame(
        panelFrame: CGRect,
        screenTopY: Double?
    ) -> CGRect {
        let margin = pointerTestMargin
        let bottom = panelFrame.minY - margin
        let top = max(panelFrame.maxY, screenTopY ?? panelFrame.maxY)
        return CGRect(
            x: panelFrame.minX - margin,
            y: bottom,
            width: panelFrame.width + (margin * 2),
            height: top - bottom
        )
    }

    /// Tells if a screen point counts as a point over the island.
    ///
    /// The test holds every edge of the frame, because the pointer reaches the
    /// exact top screen edge while it stays over the island.
    static func pointerIsInside(
        _ pointer: CGPoint,
        panelFrame: CGRect,
        screenTopY: Double?
    ) -> Bool {
        let frame = pointerTestFrame(
            panelFrame: panelFrame,
            screenTopY: screenTopY
        )
        return pointer.x >= frame.minX
            && pointer.x <= frame.maxX
            && pointer.y >= frame.minY
            && pointer.y <= frame.maxY
    }

    /// Closes the island after the pointer leaves it.
    ///
    /// The compact alert must not come back, so this rule expires the current
    /// event. The complete sequence changes the state one time, so the panel
    /// goes from the open size to the collapsed size in one movement. The
    /// unreviewed count and the recent list stay.
    private func completeHoverExit() {
        guard !hasStopped else { return }
        if state.phase == .peek {
            reduce(.endPeek)
        } else {
            reduce(.collapse)
        }
        if state.phase == .alert {
            reduce(.expireCurrent)
            reduce(.finishDismissal)
        }
        cancelAlertAction()
        cancelDismissalAction()
        render()
    }

    private func cancelScheduledActions() {
        cancelAlertAction()
        cancelDismissalAction()
        cancelHoverExitAction()
    }

    private func cancelAlertAction() {
        alertAction?.cancel()
        alertAction = nil
    }

    private func cancelDismissalAction() {
        dismissalAction?.cancel()
        dismissalAction = nil
    }

    private func cancelHoverExitAction() {
        hoverExitAction?.cancel()
        hoverExitAction = nil
    }

    private func apply(_ action: NotificationIslandAction) {
        reduce(action)
        render()
    }

    /// Changes the state without a new panel frame.
    ///
    /// A sequence of actions can then reach its last phase in one step. The
    /// panel frame therefore goes straight to the size of that phase.
    private func reduce(_ action: NotificationIslandAction) {
        guard !hasStopped else { return }
        let hadHistory = !state.recentEvents.isEmpty
        state = reducer.reduce(state, action: action)
        if state.phase != .expanded { openedFromKeyboard = false }
        if hadHistory != !state.recentEvents.isEmpty {
            onHistoryAvailabilityChanged?(!state.recentEvents.isEmpty)
        }
        removeUnusedContent()
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
        guard !isLocked, state.phase != .hidden else {
            renderer.hide()
            return
        }
        // No island window may exist while the application is still taking the
        // front for its main window. The settle hook renders this state again.
        guard hasLaunchActivationSettled else { return }
        guard let selectedScreen else { return }
        guard selectedScreen.hasCameraHousing else {
            renderer.hide()
            return
        }
        let size = desiredSize(for: state, on: selectedScreen)
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
        currentPlacement = placement
        renderer.show(
            state: state,
            content: content,
            recentContents: recentContents,
            appearance: appearance,
            cameraHousingSize: selectedScreen.cameraHousingFrame?.size,
            placement: placement,
            actions: panelActions
        )
    }

    private var panelActions: NotificationIslandPanelActions {
        switch state.phase {
        case .collapsed where state.recentEvents.isEmpty:
            return NotificationIslandPanelActions(
                primary: nil,
                pin: nil,
                collapse: nil,
                openEvent: nil,
                dismissEvent: nil,
                dismissAll: nil,
                hoverChanged: { [weak self] in self?.setHovering($0) }
            )
        case .collapsed:
            return NotificationIslandPanelActions(
                primary: { [weak self] in self?.expand() },
                pin: nil,
                collapse: nil,
                openEvent: nil,
                dismissEvent: nil,
                dismissAll: nil,
                hoverChanged: { [weak self] in self?.setHovering($0) }
            )
        case .peek:
            return NotificationIslandPanelActions(
                primary: nil,
                pin: { [weak self] in self?.expand() },
                collapse: { [weak self] in self?.collapse() },
                openEvent: { [weak self] eventID in
                    self?.openRecentEvent(eventID)
                },
                dismissEvent: { [weak self] eventID in
                    self?.dismissEvent(eventID)
                },
                dismissAll: { [weak self] in self?.dismissAll() },
                hoverChanged: { [weak self] in self?.setHovering($0) }
            )
        case .alert where state.currentEvent != nil:
            return NotificationIslandPanelActions(
                primary: nil,
                pin: nil,
                collapse: nil,
                openEvent: nil,
                dismissEvent: nil,
                dismissAll: nil,
                hoverChanged: { [weak self] in self?.setHovering($0) }
            )
        case .expanded:
            return NotificationIslandPanelActions(
                primary: nil,
                pin: nil,
                collapse: { [weak self] in self?.collapse() },
                openEvent: { [weak self] eventID in
                    self?.openRecentEvent(eventID)
                },
                dismissEvent: { [weak self] eventID in
                    self?.dismissEvent(eventID)
                },
                dismissAll: { [weak self] in self?.dismissAll() },
                hoverChanged: { [weak self] in self?.setHovering($0) }
            )
        case .hidden, .alert, .dismissed:
            return .none
        }
    }

    private func desiredSize(
        for state: NotificationIslandState,
        on screen: IslandScreenGeometry
    ) -> IslandScreenSize {
        switch state.phase {
        case .hidden:
            return IslandScreenSize(width: 0, height: 0)
        case .collapsed:
            if let housing = screen.cameraHousingFrame {
                // The collapsed island grows to the side of the housing only.
                // Its height stays the housing height, so the collapsed island
                // reads as the camera housing itself.
                //
                // With nothing unreviewed it takes no extra width at all. On
                // hardware any surplus reads as a wider notch rather than as
                // part of the island, because the collapsed surface is the same
                // black as the housing and the seam is invisible. The island is
                // still present at housing size, so it keeps its hover target.
                let counterWidth = state.unreviewedCount > 0 ? 76.0 : 0.0
                return IslandScreenSize(
                    width: panelWidth(
                        bodyWidth: housing.size.width + counterWidth
                    ),
                    height: housing.size.height
                )
            }
            return IslandScreenSize(
                width: panelWidth(bodyWidth: 220),
                height: 44
            )
        case .peek, .expanded:
            return expandedSize(for: state, on: screen)
        case .alert, .dismissed:
            return IslandScreenSize(
                width: panelWidth(bodyWidth: 360),
                height: 120
            )
        }
    }

    /// Adds the two notch ears to one island body width.
    ///
    /// The island shape merges into the top screen edge, so each side of the
    /// panel carries one ear that shows no island surface.
    private func panelWidth(bodyWidth: Double) -> Double {
        NotificationIslandLayout.panelWidth(bodyWidth: bodyWidth)
    }

    /// Gives the stack panel size for the number of session events.
    private func expandedSize(
        for state: NotificationIslandState,
        on screen: IslandScreenGeometry
    ) -> IslandScreenSize {
        let housingHeight = screen.cameraHousingFrame?.size.height
            ?? Self.fallbackCameraHousingHeight
        return IslandScreenSize(
            width: panelWidth(
                bodyWidth: NotificationIslandLayout.expandedWidth
            ),
            height: NotificationIslandLayout.expandedHeight(
                eventCount: state.recentEvents.count,
                cameraHousingHeight: housingHeight
            )
        )
    }

    private static let fallbackCameraHousingHeight = 38.0

    private func removeUnusedContent() {
        let eventIDs = [state.currentEvent]
            .compactMap { $0?.id }
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
    private let serviceIconURLProvider: @MainActor () -> URL?

    init(
        controller: IslandPanelController,
        serviceLabel: String,
        serviceIconURLProvider: @escaping @MainActor () -> URL?
    ) {
        self.controller = controller
        self.serviceLabel = serviceLabel
        self.serviceIconURLProvider = serviceIconURLProvider
    }

    func makeContent(event: NotificationEvent) -> NotificationIslandPanelContent {
        NotificationIslandPanelContent(
            event: event,
            serviceLabel: serviceLabel,
            serviceIconURL: serviceIconURLProvider()
        )
    }

    func present(
        event: NotificationEvent,
        requestID: String,
        traceID: String
    ) {
        controller.present(makeContent(event: event))
        AppLogger.notifications.info(
            "Notification trace \(traceID, privacy: .public): island accepted request \(requestID, privacy: .public)"
        )
    }
}

/// Keeps the presentation state for the persistent island view.
@MainActor
@Observable
private final class NotificationIslandPanelModel {
    var state = NotificationIslandState.hidden
    var content: NotificationIslandPanelContent?
    var recentContents: [NotificationIslandPanelContent] = []
    var appearance = NotificationIslandAppearance.defaultValue
    var cameraHousingSize: IslandScreenSize?
    var actions = NotificationIslandPanelActions.none

    func update(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        appearance: NotificationIslandAppearance,
        cameraHousingSize: IslandScreenSize?,
        actions: NotificationIslandPanelActions
    ) {
        self.state = state
        self.content = content
        self.recentContents = recentContents
        self.appearance = appearance
        self.cameraHousingSize = cameraHousingSize
        self.actions = actions
    }

    /// The last pointer state that the panel sent to the controller.
    @ObservationIgnored private var isPointerInside = false

    /// Number of cards that a person moves at this moment.
    @ObservationIgnored private var activeDragCount = 0

    /// Tells if the pointer left the island during a card movement.
    @ObservationIgnored private var hoverExitPending = false

    /// Sends one pointer change, and a real change only.
    ///
    /// The AppKit tracking area rebuilds itself while the panel frame animates,
    /// so it can report the same pointer state twice. The panel keeps the last
    /// state and forwards a change one time.
    ///
    /// A card movement can also take the pointer outside the island. The exit
    /// then waits for the end of that movement, because the island must not
    /// close under the pointer.
    func changeHover(_ isHovering: Bool) {
        guard isHovering != isPointerInside else { return }
        isPointerInside = isHovering
        guard !isHovering else {
            hoverExitPending = false
            actions.hoverChanged?(true)
            return
        }
        guard activeDragCount == 0 else {
            hoverExitPending = true
            return
        }
        actions.hoverChanged?(false)
    }

    /// Counts the card movements and completes one waiting pointer exit.
    func changeDragState(_ isDragging: Bool) {
        guard !isDragging else {
            activeDragCount += 1
            return
        }
        activeDragCount = max(0, activeDragCount - 1)
        guard activeDragCount == 0, hoverExitPending else { return }
        hoverExitPending = false
        actions.hoverChanged?(false)
    }
}

/// Owns the lazy, nonactivating AppKit panel.
@MainActor
private final class AppKitNotificationIslandPanelRenderer:
    NotificationIslandPanelRendering
{
    private var panel: NotificationIslandPanel?
    private var model: NotificationIslandPanelModel?
    private weak var previousKeyWindow: NSWindow?

    func show(
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        appearance: NotificationIslandAppearance,
        cameraHousingSize: IslandScreenSize?,
        placement: NotificationIslandPlacement,
        actions: NotificationIslandPanelActions
    ) {
        let (panel, model) = panelAndModel()
        if state.phase == .expanded, !panel.isKeyWindow {
            previousKeyWindow = NSApp.keyWindow
        }
        let frame = placement.frame.appKitRect
        let shouldAnimate = shouldAnimateFrameChange(
            panel: panel,
            to: frame
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        updateFrame(
            of: panel,
            to: frame,
            animated: shouldAnimate && !reduceMotion
        )
        update(
            model,
            state: state,
            content: content,
            recentContents: recentContents,
            appearance: appearance,
            cameraHousingSize: cameraHousingSize,
            actions: actions
        )
        panel.hasShadow = false
        panel.ignoresMouseEvents = !actions.acceptsPointerEvents
        if state.phase != .expanded, panel.isKeyWindow {
            panel.resignKey()
            restoreKeyboardFocus()
        }
        panel.acceptsKeyWindow = state.phase == .expanded
        panel.becomesKeyOnlyIfNeeded = state.phase != .expanded
        if state.phase == .expanded {
            panel.makeKeyAndOrderFront(nil)
        } else if state.phase == .collapsed {
            // Never `orderFrontRegardless` here. The collapsed island is
            // ambient, so it takes its place in the window order and leaves the
            // front to whichever application owns it. `IslandPanelController`
            // holds this call until the launch activation has settled, so the
            // request can no longer compete with the main window.
            panel.orderFront(nil)
        } else {
            // An alert must appear while another application is active.
            panel.orderFrontRegardless()
        }
    }

    func hide() {
        let wasKey = panel?.isKeyWindow == true
        panel?.orderOut(nil)
        if wasKey { restoreKeyboardFocus() }
    }

    private func restoreKeyboardFocus() {
        if NSApp.isActive, let window = previousKeyWindow, window.isVisible {
            window.makeKey()
        }
        previousKeyWindow = nil
    }

    func stop() {
        panel?.orderOut(nil)
        panel?.close()
        panel = nil
        model = nil
    }

    private func panelAndModel() -> (
        NotificationIslandPanel,
        NotificationIslandPanelModel
    ) {
        if let panel, let model {
            return (panel, model)
        }

        let model = NotificationIslandPanelModel()
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
        let contentView = NotificationIslandPanelContentView(
            rootView: NotificationIslandPanelView(model: model),
            hoverChanged: { [weak model] isHovering in
                model?.changeHover(isHovering)
            }
        )
        panel.contentView = contentView
        self.panel = panel
        self.model = model
        return (panel, model)
    }

    private func update(
        _ model: NotificationIslandPanelModel,
        state: NotificationIslandState,
        content: NotificationIslandPanelContent?,
        recentContents: [NotificationIslandPanelContent],
        appearance: NotificationIslandAppearance,
        cameraHousingSize: IslandScreenSize?,
        actions: NotificationIslandPanelActions
    ) {
        model.update(
            state: state,
            content: content,
            recentContents: recentContents,
            appearance: appearance,
            cameraHousingSize: cameraHousingSize,
            actions: actions
        )
    }

    private func shouldAnimateFrameChange(
        panel: NSPanel,
        to frame: CGRect
    ) -> Bool {
        guard panel.isVisible else { return false }
        return abs(panel.frame.midX - frame.midX) < 2
            && abs(panel.frame.maxY - frame.maxY) < 2
            && panel.frame != frame
    }

    private func updateFrame(
        of panel: NSPanel,
        to frame: CGRect,
        animated: Bool
    ) {
        guard animated else {
            panel.setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.allowsImplicitAnimation = true
            panel.animator().setFrame(frame, display: true)
        }
    }
}

/// Keeps SwiftUI inside a frame that AppKit controls.
///
/// This view also owns the island hover tracking. AppKit reports the pointer
/// against the real panel frame, so an animated size change does not create the
/// pointer exit that SwiftUI reports at the top screen edge.
@MainActor
private final class NotificationIslandPanelContentView<Content: View>: NSView {
    private let hostingView: NSHostingView<Content>
    private let hoverChanged: (@MainActor (Bool) -> Void)?
    private var hoverTrackingArea: NSTrackingArea?

    /// The last pointer state that this view sent.
    private var isPointerInside = false

    init(
        rootView: Content,
        hoverChanged: (@MainActor (Bool) -> Void)? = nil
    ) {
        hostingView = NSHostingView(rootView: rootView)
        self.hoverChanged = hoverChanged
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        guard hostingView.frame != bounds else { return }
        hostingView.frame = bounds
    }

    /// Rebuilds the hover area after each frame change.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTrackingArea {
            removeTrackingArea(hoverTrackingArea)
        }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        hoverTrackingArea = trackingArea
        reconcileHoverState()
    }

    /// Drops a pointer state that the panel keeps after it leaves the pointer.
    ///
    /// AppKit sends no pointer exit when the panel leaves the screen. A stored
    /// state of true would then reject the next real entry. This test therefore
    /// clears that state. It never creates an entry, because the tracking area
    /// reports each real entry itself.
    private func reconcileHoverState() {
        guard isPointerInside else { return }
        guard let window, window.isVisible, !window.ignoresMouseEvents else {
            changeHover(false)
            return
        }
        let pointer = convert(
            window.mouseLocationOutsideOfEventStream,
            from: nil
        )
        guard !bounds.contains(pointer) else { return }
        changeHover(false)
    }

    override func mouseEntered(with event: NSEvent) {
        changeHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        changeHover(false)
    }

    /// Sends a pointer change one time only.
    ///
    /// The rebuilt tracking area can repeat the current state while the panel
    /// frame animates. The last state stops that second report.
    private func changeHover(_ isHovering: Bool) {
        guard isHovering != isPointerInside else { return }
        isPointerInside = isHovering
        hoverChanged?(isHovering)
    }
}

/// Accepts keyboard focus only after the user opens the expanded island.
private final class NotificationIslandPanel: NSPanel {
    var acceptsKeyWindow = false

    override var canBecomeKey: Bool { acceptsKeyWindow }
    override var canBecomeMain: Bool { false }
}

/// Includes the dismiss target outside the padded card content.
private struct NotificationIslandCardInteractionShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addRect(CGRect(
            x: rect.maxX - 10,
            y: rect.minY - 15,
            width: 28,
            height: 28
        ))
        return path
    }
}

/// The silhouette of the MacBook camera housing.
///
/// The shape hangs from the top screen edge. Each top corner is a concave
/// fillet that merges the island into that edge, and each bottom corner is a
/// convex round. The visible body therefore starts one top radius inside each
/// side, while the top edge spans the complete rectangle.
///
/// Both radii animate, so the island keeps one silhouette while it changes
/// between the collapsed pill and the open panel.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    init(topCornerRadius: CGFloat = 6, bottomCornerRadius: CGFloat = 12) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
    }

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(max(0, topCornerRadius), rect.width / 2, rect.height)
        let bottom = min(
            max(0, bottomCornerRadius),
            max(0, (rect.width / 2) - top),
            max(0, rect.height - top)
        )

        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // The concave ear that joins the top screen edge.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

enum IslandKeyboardInput {
    // macOS backward Delete can arrive as DEL rather than SwiftUI's BS value.
    static let dismissalKeys: Set<KeyEquivalent> = [.delete, .deleteForward, KeyEquivalent("\u{7f}")]
}

private struct NotificationIslandPanelView: View {
    private enum FocusTarget: Hashable {
        case dismissAll
        case event(UUID)
        case dismiss(UUID)
    }

    let model: NotificationIslandPanelModel

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedControl: FocusTarget?
    @AccessibilityFocusState(for: .voiceOver) private var voiceOverControl: FocusTarget?
    @State private var scrollContainerHeight: CGFloat = 0
    @State private var hoveredEventID: UUID?

    /// The island silhouette. Each state uses the notch form.
    /// True when the island has nothing to show and must be invisible.
    ///
    /// The housing is already black, so anything drawn over it only adds the
    /// antialiased edge of a second curve on top of the real one, which reads
    /// as a border around the notch. Everything that paints checks this, and
    /// it is the same test `desiredSize` uses to give an idle island exactly
    /// the housing size: an island that takes no width must paint nothing.
    private var isIdle: Bool {
        isCollapsedShape && model.state.unreviewedCount == 0
    }

    private var shape: NotchShape {
        NotchShape(
            topCornerRadius: Self.notchEarWidth,
            bottomCornerRadius: bottomCornerRadius
        )
    }

    /// Width of one concave ear, and the top radius of each island shape.
    private static let notchEarWidth = CGFloat(
        NotificationIslandLayout.notchEarWidth
    )

    /// Bottom radius of the real camera housing.
    private static let housingBottomCornerRadius: CGFloat = 10

    var body: some View {
        styledContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .onTapGesture {
                model.actions.pin?()
            }
            .onExitCommand {
                model.actions.collapse?()
            }
    }

    @ViewBuilder
    private var styledContent: some View {
        if isIdle {
            islandContent
        } else if isCollapsedShape {
            // With a count to show the island is wider than the housing, so it
            // needs its own black surface for the part that extends past it.
            islandContent.background(shape.fill(Color.black))
        } else if reduceTransparency {
            islandContent.background {
                if colorScheme == .light {
                    shape.fill(Color(white: 0.86))
                } else {
                    ZStack {
                        shape.fill(Color(nsColor: .windowBackgroundColor))
                        materialTint
                    }
                }
            }
        } else if #available(macOS 26, *), model.appearance.glassStyle != .off {
            glassSurface
        } else {
            // Liquid Glass arrived in macOS 26. Earlier systems take the same
            // material surface the Off style draws.
            islandContent.background {
                ZStack {
                    shape.fill(.regularMaterial)
                    materialTint
                }
            }
        }
    }

    @available(macOS 26, *)
    @ViewBuilder
    private var glassSurface: some View {
        switch model.appearance.glassStyle {
        case .clear:
            islandContent.glassEffect(.clear.tint(glassTint), in: shape)
        case .off, .regular:
            islandContent.glassEffect(.regular.tint(glassTint), in: shape)
        }
    }

    /// Tells if the island is the black pill beside the camera housing.
    private var isCollapsedShape: Bool {
        model.state.phase == .collapsed || model.state.phase == .hidden
    }

    private var islandContent: some View {
        ZStack(alignment: .top) {
            // The bridge is one ear wider than the housing on each side, and
            // those ears are concave, so an idle island drew two small black
            // wedges either side of the notch. Nothing to show means nothing
            // to draw.
            if !isIdle {
                cameraBridge
            }

            Group {
                if model.state.phase == .peek
                    || model.state.phase == .expanded {
                    expandedContent
                } else {
                    compactContent
                }
            }
            .padding(.top, contentTopInset)
            // The two ears carry no island surface, so the content keeps its
            // distance from the visible body edge.
            .padding(.horizontal, Self.notchEarWidth)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var materialTint: some View {
        shape.fill(
            colorScheme == .light
                ? Color(white: 0.82).opacity(
                    GlassIntensityScale.materialTintOpacity(model.appearance.transparency)
                )
                : PaguroColor.Fill.shellMaterialTint(
                    intensity: model.appearance.transparency
                )
        )
    }

    private var glassTint: Color {
        colorScheme == .light
            ? Color(white: 0.82).opacity(
                GlassIntensityScale.controlTintAlpha(model.appearance.transparency)
            )
            : PaguroColor.Fill.glassTint(
                intensity: model.appearance.transparency
            )
    }

    /// The black surface that continues the physical camera housing.
    ///
    /// The bridge keeps the notch silhouette and adds one ear on each side,
    /// so its visible body has the housing width and its top edge merges into
    /// the island top edge.
    private var cameraBridge: some View {
        let size = model.cameraHousingSize
            ?? IslandScreenSize(width: 164, height: 38)
        return NotchShape(
            topCornerRadius: Self.notchEarWidth,
            bottomCornerRadius: Self.housingBottomCornerRadius
        )
        .fill(.black)
        .frame(
            width: CGFloat(
                NotificationIslandLayout.panelWidth(bodyWidth: size.width)
            ),
            height: CGFloat(size.height)
        )
    }

    /// The convex bottom radius of the island.
    ///
    /// The collapsed island keeps the housing radius, so it reads as the
    /// camera housing itself, only wider. The open states use a larger round.
    private var bottomCornerRadius: CGFloat {
        switch model.state.phase {
        case .hidden, .collapsed:
            Self.housingBottomCornerRadius
        case .peek, .alert, .expanded, .dismissed:
            22
        }
    }

    private var contentTopInset: CGFloat {
        switch model.state.phase {
        case .hidden, .collapsed, .peek, .expanded:
            0
        case .alert, .dismissed:
            cameraHousingHeight
        }
    }

    private var cameraHousingWidth: CGFloat {
        CGFloat(model.cameraHousingSize?.width ?? 164)
    }

    private var cameraHousingHeight: CGFloat {
        CGFloat(model.cameraHousingSize?.height ?? 38)
    }

    @ViewBuilder
    private var compactContent: some View {
        if let primaryAction = model.actions.primary {
            Button(action: primaryAction) {
                collapsedLabel
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .help(openHelp)
            .accessibilityLabel(compactAccessibilityLabel)
        } else if let content = model.content {
            compactEventLabel(content)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compactAccessibilityLabel)
        } else {
            collapsedLabel
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compactAccessibilityLabel)
        }
    }

    @ViewBuilder
    private var collapsedLabel: some View {
        HStack {
            if let countLabel = unreviewedCountLabel {
                Text(countLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(counterBadgeFill, in: .capsule)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 7)
    }

    private func compactEventLabel(
        _ content: NotificationIslandPanelContent
    ) -> some View {
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

            if let countLabel = unreviewedCountLabel {
                notificationCountBadge(countLabel)
            }
        }
    }

    private var expandedContent: some View {
        ZStack(alignment: .top) {
            // The list goes below the toolbar and stops at the island edge.
            notificationStack
                .padding(
                    .horizontal,
                    CGFloat(NotificationIslandLayout.cardHorizontalInset)
                )
                .padding(
                    .bottom,
                    CGFloat(NotificationIslandLayout.bottomInset)
                )

            expandedNotchToolbar
        }
        .onAppear {
            if model.state.phase == .expanded {
                focusFirstExpandedControl()
            }
        }
        .onChange(of: model.state.phase) { _, phase in
            if phase == .expanded {
                focusFirstExpandedControl()
            }
        }
        .onKeyPress(.return) {
            activateFocusedControl() ? .handled : .ignored
        }
        .onKeyPress(.upArrow) {
            moveFocusedEvent(by: -1) ? .handled : .ignored
        }
        .onKeyPress(.downArrow) {
            moveFocusedEvent(by: 1) ? .handled : .ignored
        }
        .onKeyPress(keys: IslandKeyboardInput.dismissalKeys, phases: .down) { _ in
            dismissFocusedEvent() ? .handled : .ignored
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Paguro recent notifications")
    }

    private var expandedNotchToolbar: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "bell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                if let countLabel = unreviewedCountLabel {
                    notificationCountBadge(countLabel)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(toolbarControlBackground, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The camera area stays black above the cards that pass below it.
            cameraBridge

            HStack(spacing: 6) {
                Button {
                    model.actions.dismissAll?()
                } label: {
                    Text("Clear All")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .focusable(model.state.phase == .expanded)
                .focusEffectDisabled()
                .focused($focusedControl, equals: .dismissAll)
                .accessibilityFocused($voiceOverControl, equals: .dismissAll)
                .background(
                    focusedControl == .dismissAll
                        ? controlAccent.opacity(0.22)
                        : Color.clear,
                    in: .capsule
                )
                .help("Clear all notifications")
                .accessibilityLabel("Clear all notifications")
            }
            // No inset here, so the last button right edge and the card
            // right edge share one position.
            .background(toolbarControlBackground, in: .capsule)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: cameraHousingHeight)
        .padding(
            .horizontal,
            CGFloat(NotificationIslandLayout.horizontalInset)
        )
    }

    /// Keeps the toolbar controls readable while a card passes below them.
    private var toolbarControlBackground: AnyShapeStyle {
        if reduceTransparency {
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
        return AnyShapeStyle(.regularMaterial)
    }

    private var notificationStack: some View {
        ScrollViewReader { proxy in
            notificationScrollView
                .onChange(of: focusedControl) { previous, control in
                    guard Self.eventID(of: previous) != Self.eventID(of: control) else { return }
                    scrollToFocusedEvent(control, using: proxy)
                }
                .onChange(of: voiceOverControl) { previous, control in
                    guard Self.eventID(of: previous) != Self.eventID(of: control) else { return }
                    scrollToFocusedEvent(control, using: proxy)
                }
        }
    }

    private var notificationScrollView: some View {
        ScrollView(.vertical) {
            // Each space is content. A content inset would change the scroll
            // view height that gives the fold line its position.
            VStack(spacing: 0) {
                Color.clear
                    .frame(height: topSpacerHeight)

                VStack(spacing: NotificationIslandLayout.rowSpacing) {
                    ForEach(
                        Array(model.recentContents.enumerated()),
                        id: \.element.event.id
                    ) { index, recentContent in
                        foldedEventCard(recentContent, at: index)
                    }
                }
                .animation(stackAnimation, value: recentEventIDs)
                // The cards cut each other inside one group.
                .compositingGroup()

                if foldsRows {
                    Color.clear
                        .frame(
                            height: NotificationIslandLayout
                                .bottomScrollClearance
                        )
                }
            }
        }
        // A card of the pile draws outside the scroll bounds. The island
        // shape stays the one clip of the panel.
        .scrollClipDisabled()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.height
        } action: { height in
            scrollContainerHeight = height
        }
        .scrollIndicators(.never)
    }

    /// Reveals the complete focused card, including cards hidden by the bottom fold.
    /// Focus changes include Tab traversal and VoiceOver, not only arrow keys.
    private func scrollToFocusedEvent(
        _ control: FocusTarget?,
        using proxy: ScrollViewProxy
    ) {
        guard let eventID = Self.eventID(of: control) else { return }
        if reduceMotion {
            proxy.scrollTo(eventID, anchor: .center)
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(eventID, anchor: .center)
            }
        }
    }

    /// Gives the visible scroll view height for the pile rule.
    ///
    /// A row below the visible area gets no scroll view bounds, so the view
    /// measures the scroll view itself. The pure rule supplies the height
    /// until the first measurement arrives.
    private var measuredScrollContainerHeight: Double {
        let ruleHeight = ruleScrollContainerHeight
        let measuredHeight = Double(scrollContainerHeight)
        guard measuredHeight > 0 else { return ruleHeight }
        // A later change of a view modifier can measure another height. The
        // panel frame follows the rule, so the rule stays the safe value.
        guard abs(measuredHeight - ruleHeight) <= 1 else { return ruleHeight }
        return measuredHeight
    }

    /// Gives the scroll view height that the panel height rule expects.
    private var ruleScrollContainerHeight: Double {
        NotificationIslandLayout.scrollContainerHeight(
            eventCount: model.recentContents.count,
            cameraHousingHeight: Double(cameraHousingHeight)
        )
    }

    /// Gives the empty height that keeps the first card below the toolbar.
    private var topSpacerHeight: CGFloat {
        CGFloat(
            NotificationIslandLayout.topSpacerHeight(
                cameraHousingHeight: Double(cameraHousingHeight)
            )
        )
    }

    /// Tells if the list is long enough to fold its last cards.
    private var foldsRows: Bool {
        NotificationIslandLayout.foldsRows(
            eventCount: model.recentContents.count
        )
    }

    /// Gives one row of the notification stack.
    ///
    /// The row keeps its own drawing rule, so a scroll movement does not draw
    /// the complete panel again.
    private func foldedEventCard(
        _ recentContent: NotificationIslandPanelContent,
        at index: Int
    ) -> some View {
        NotificationIslandStackRow(
            index: index,
            eventCount: model.recentContents.count,
            containerHeight: measuredScrollContainerHeight,
            cameraHousingHeight: Double(cameraHousingHeight),
            background: cardBackground(for: recentContent),
            content: cardContent(for: recentContent),
            dismiss: { [weak model = model] in
                model?.actions.dismissEvent?(recentContent.event.id)
            },
            dragStateChanged: { [weak model = model] isDragging in
                model?.changeDragState(isDragging)
            }
        )
        .id(recentContent.event.id)
        .transition(cardTransition)
    }

    private var cardTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .top).combined(with: .opacity),
            removal: .opacity
                .combined(with: .scale(scale: 0.9))
                .combined(with: .offset(x: 48))
        )
    }

    private var stackAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(duration: 0.4, bounce: 0.15)
    }

    /// Gives the controls of one recent event card.
    ///
    /// The row keeps this value, so a scroll movement composes the card again
    /// without a new build of these controls.
    private func cardContent(
        for recentContent: NotificationIslandPanelContent
    ) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                model.actions.openEvent?(recentContent.event.id)
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
                                .foregroundStyle(.secondary)
                        }
                        Text(recentContent.event.title)
                            .font(.body.weight(.medium))
                            .lineLimit(1)
                        if let body = recentContent.event.body {
                            Text(body)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 8)
                }
                .contentShape(.rect)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.trailing, 8)
            .buttonStyle(.plain)
            .focusable(model.state.phase == .expanded)
            .focusEffectDisabled()
            .focused(
                $focusedControl,
                equals: .event(recentContent.event.id)
            )
            .help("Open \(recentContent.serviceLabel)")
            .accessibilityLabel(recentAccessibilityLabel(for: recentContent))
            .accessibilityFocused($voiceOverControl, equals: .event(recentContent.event.id))

            Button {
                dismissCard(recentContent.event.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .focusable(model.state.phase == .expanded)
            .focusEffectDisabled()
            .focused(
                $focusedControl,
                equals: .dismiss(recentContent.event.id)
            )
            .foregroundStyle(
                focusedControl == .dismiss(recentContent.event.id)
                    ? (colorScheme == .dark ? Color.black : Color.white)
                    : Color.primary
            )
            .background(
                controlAccent.opacity(focusedControl == .dismiss(recentContent.event.id) ? 0.75 : 0.10),
                in: .circle
            )
            .background(Color(nsColor: .windowBackgroundColor), in: .circle)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .frame(width: 28, height: 28)
            .contentShape(.circle)
            // Keep the center six points inside the card corner.
            .offset(x: 18, y: -15)
            .help("Dismiss \(recentContent.serviceLabel) notification")
            .accessibilityLabel(
                "Dismiss \(recentContent.serviceLabel) notification"
            )
            .accessibilityFocused($voiceOverControl, equals: .dismiss(recentContent.event.id))
            // Keep the control in keyboard and VoiceOver navigation when quiet.
            .opacity(showsDismissButton(for: recentContent.event.id) ? 1 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // One continuous region covers the card and the protruding button.
        .contentShape(NotificationIslandCardInteractionShape())
        .onHover { isHovering in
            if isHovering {
                hoveredEventID = recentContent.event.id
            } else if hoveredEventID == recentContent.event.id {
                hoveredEventID = nil
            }
        }
    }

    private func showsDismissButton(for eventID: UUID) -> Bool {
        hoveredEventID == eventID
            || isFocused(eventID)
            || Self.eventID(of: voiceOverControl) == eventID
    }

    /// Gives the surface of one recent event card.
    private func cardBackground(
        for recentContent: NotificationIslandPanelContent
    ) -> some View {
        islandCardShape
            .fill(cardFill(isFocused: isFocused(recentContent.event.id)))
            .overlay {
                if focusedControl == .event(recentContent.event.id) {
                    islandCardShape.strokeBorder(controlAccent.opacity(0.35), lineWidth: 1)
                }
            }
    }

    private var controlAccent: Color {
        colorScheme == .dark ? .white : .black
    }

    private func cardFill(isFocused: Bool) -> Color {
        if reduceTransparency {
            // Keep cards brighter than the opaque surface behind them.
            let white = colorScheme == .dark
                ? (isFocused ? 0.34 : 0.24)
                : (isFocused ? 1.0 : 0.97)
            return Color(white: white)
        }
        return Color.white.opacity(
            colorScheme == .light
                ? (isFocused ? 0.85 : 0.55)
                : (isFocused ? 0.22 : 0.10)
        )
    }

    @ViewBuilder
    private func serviceIcon(
        for content: NotificationIslandPanelContent,
        size: CGFloat
    ) -> some View {
        if let image = content.serviceIcon {
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

    private func notificationCountBadge(_ label: String) -> some View {
        Text(label)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(isCollapsedShape ? Color.white : Color.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(counterBadgeFill, in: .capsule)
            .accessibilityLabel("\(label) unreviewed notifications")
    }

    /// Keeps the counter readable on the black collapsed island.
    private var counterBadgeFill: Color {
        (isCollapsedShape ? Color.white : controlAccent).opacity(0.18)
    }

    private var unreviewedCountLabel: String? {
        NotificationIslandCounterLabel.text(
            for: model.state.unreviewedCount
        )
    }

    private var recentEventIDs: [UUID] {
        model.recentContents.map(\.event.id)
    }

    private func isFocused(_ eventID: UUID) -> Bool {
        focusedControl == .event(eventID)
            || focusedControl == .dismiss(eventID)
    }

    private var compactAccessibilityLabel: String {
        guard let content = model.content else {
            return "Paguro notification island"
        }
        if let body = content.event.body {
            return "\(content.serviceLabel), \(content.event.title), \(body)"
        }
        return "\(content.serviceLabel), \(content.event.title)"
    }

    private var openHelp: String {
        guard let content = model.content else {
            return "Open recent notifications"
        }
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
        let target = model.recentContents.first.map {
            FocusTarget.event($0.event.id)
        } ?? .dismissAll
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            guard !Task.isCancelled, model.state.phase == .expanded else { return }
            focusedControl = target
            if NSWorkspace.shared.isVoiceOverEnabled {
                voiceOverControl = target
            }
        }
    }

    /// Moves the focus one card up or down and stops at each end.
    private func moveFocusedEvent(by offset: Int) -> Bool {
        let eventIDs = recentEventIDs
        guard !eventIDs.isEmpty else { return false }
        guard let currentIndex = focusedEventID
            .flatMap(eventIDs.firstIndex) else {
            focusedControl = .event(eventIDs[0])
            return true
        }
        let nextIndex = min(
            eventIDs.count - 1,
            max(0, currentIndex + offset)
        )
        guard nextIndex != currentIndex else { return false }
        focusedControl = .event(eventIDs[nextIndex])
        return true
    }

    private func dismissFocusedEvent() -> Bool {
        guard let eventID = focusedEventID else { return false }
        return dismissCard(eventID)
    }

    @discardableResult
    private func dismissCard(_ eventID: UUID) -> Bool {
        guard let dismissEvent = model.actions.dismissEvent else { return false }
        if model.state.phase == .expanded,
           Self.eventID(of: voiceOverControl) == eventID,
           let replacement = NotificationIslandFocusRule.replacement(
               for: eventID, in: recentEventIDs
           ) {
            // Move both cursors while the destination still exists in the tree.
            focusedControl = .event(replacement)
            voiceOverControl = .event(replacement)
        }
        dismissEvent(eventID)
        return true
    }

    private var focusedEventID: UUID? {
        Self.eventID(of: focusedControl)
    }

    private static func eventID(of control: FocusTarget?) -> UUID? {
        switch control {
        case let .event(eventID), let .dismiss(eventID):
            return eventID
        case .dismissAll, nil:
            return nil
        }
    }

    private func activateFocusedControl() -> Bool {
        switch focusedControl {
        case .dismissAll:
            guard let dismissAll = model.actions.dismissAll else { return false }
            dismissAll()
            return true
        case let .event(eventID):
            guard let openEvent = model.actions.openEvent else { return false }
            openEvent(eventID)
            return true
        case let .dismiss(eventID):
            return dismissCard(eventID)
        case nil:
            return false
        }
    }
}

/// The shape of one card of the notification stack.
private var islandCardShape: RoundedRectangle {
    RoundedRectangle(
        cornerRadius: CGFloat(NotificationIslandLayout.cardCornerRadius),
        style: .continuous
    )
}

/// One card of the notification stack.
///
/// The card keeps its own pile rule in local state. A scroll movement then
/// composes this row again and leaves the complete panel unchanged. The rule
/// comes from the layout report, because a visual effect inside another
/// visual effect sees the changed position of the effect above it.
///
/// The row holds the surface and the controls as two values. It therefore
/// composes the card again without a new build of the controls.
private struct NotificationIslandStackRow<
    Background: View,
    Content: View
>: View {
    let index: Int
    let eventCount: Int
    let containerHeight: Double
    let cameraHousingHeight: Double
    let background: Background
    let content: Content
    let dismiss: () -> Void
    let dragStateChanged: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    /// Horizontal movement of the current drag.
    @State private var dragX: CGFloat = 0

    /// Width of the card, for the drag rules.
    @State private var cardWidth: CGFloat = 0

    /// The direction of the current drag, or `nil` before it starts.
    @State private var isHorizontalDrag: Bool?

    /// Tells if the card is behind the complete pile.
    ///
    /// The rule of each drawn frame gives the card position. This value is
    /// the one state of the row, so a scroll movement writes no state while
    /// the card stays visible.
    @State private var isHidden: Bool

    init(
        index: Int,
        eventCount: Int,
        containerHeight: Double,
        cameraHousingHeight: Double,
        background: Background,
        content: Content,
        dismiss: @escaping () -> Void,
        dragStateChanged: @escaping (Bool) -> Void
    ) {
        self.index = index
        self.eventCount = eventCount
        self.containerHeight = containerHeight
        self.cameraHousingHeight = cameraHousingHeight
        self.background = background
        self.content = content
        self.dismiss = dismiss
        self.dragStateChanged = dragStateChanged
        // The first frame uses the position of an unscrolled list.
        _isHidden = State(
            initialValue: Self.isBehindThePile(
                rowMaxY: NotificationIslandLayout.rowMaxY(
                    index: index,
                    cameraHousingHeight: cameraHousingHeight
                ),
                containerHeight: Self.resolvedContainerHeight(
                    containerHeight,
                    eventCount: eventCount,
                    cameraHousingHeight: cameraHousingHeight
                ),
                eventCount: eventCount
            )
        )
    }

    var body: some View {
        let usedContainerHeight = Self.resolvedContainerHeight(
            containerHeight,
            eventCount: eventCount,
            cameraHousingHeight: cameraHousingHeight
        )
        let listLength = eventCount
        let reducesMotion = reduceMotion
        return rowContent
            .offset(x: dragOffset)
            .opacity(dragOpacity)
            .highPriorityGesture(cardDragGesture)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                guard cardWidth != width else { return }
                cardWidth = width
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .scrollView).maxY
            } action: { position in
                report(
                    rowMaxY: Double(position),
                    containerHeight: usedContainerHeight
                )
            }
            // The panel frame grows while the island opens. A card that waits
            // behind the pile must come back for the new height.
            .onChange(of: containerHeight) { _, _ in
                showCardAgain()
            }
            .onChange(of: eventCount) { _, _ in
                showCardAgain()
            }
            .onChange(of: cameraHousingHeight) { _, _ in
                showCardAgain()
            }
            // One visual effect for each drawn frame. The rule reads the
            // current position, so a card that waits at the stop line stays
            // still while the list moves.
            .visualEffect { card, proxy in
                let placement = NotificationIslandLayout.pilePlacement(
                    rowMaxY: Double(proxy.frame(in: .scrollView).maxY),
                    containerHeight: usedContainerHeight,
                    eventCount: listLength
                )
                return card
                    .scaleEffect(
                        reducesMotion ? 1 : CGFloat(placement.scale),
                        anchor: .bottom
                    )
                    .offset(y: CGFloat(placement.offset))
                    .opacity(placement.opacity)
            }
            .zIndex(Double(-index))
    }

    /// Gives the card, or an empty space of the same size.
    ///
    /// A card behind the complete pile is invisible. The row therefore keeps
    /// the space of that card and draws no control. The change happens at
    /// opacity 0, so a person sees no step.
    @ViewBuilder
    private var rowContent: some View {
        if isHidden {
            Color.clear
                .frame(height: CGFloat(NotificationIslandLayout.rowHeight))
        } else {
            ZStack {
                // The stack draws the deepest card first. This shape removes
                // each card part below this card, so one translucent card
                // covers the card behind it completely.
                islandCardShape
                    .fill(Color.black)
                    .blendMode(.destinationOut)

                background

                // The edge of the front card separates it from the card
                // behind it.
                islandCardShape
                    .strokeBorder(cardBorderColor, lineWidth: 1)

                content
                    .padding(.horizontal, 10)
                    .padding(
                        .vertical,
                        CGFloat(NotificationIslandLayout.cardVerticalPadding)
                    )
            }
            .frame(maxWidth: .infinity)
            .frame(height: CGFloat(NotificationIslandLayout.rowHeight))
        }
    }

    /// Moves one card to the side and dismisses it.
    ///
    /// The drag starts after a short movement, so a click keeps the open
    /// action of the card and the dismiss button keeps its own action.
    private var cardDragGesture: some Gesture {
        DragGesture(
            minimumDistance: CGFloat(
                NotificationIslandSwipeRule.minimumDistance
            )
        )
        .onChanged { value in
            changeDrag(translation: value.translation)
        }
        .onEnded { value in
            endDrag(translation: value.translation, velocity: value.velocity)
        }
    }

    private func changeDrag(translation: CGSize) {
        if isHorizontalDrag == nil {
            let isHorizontal = NotificationIslandSwipeRule.isHorizontal(
                translationX: Double(translation.width),
                translationY: Double(translation.height)
            )
            isHorizontalDrag = isHorizontal
            if isHorizontal {
                dragStateChanged(true)
            }
        }
        guard isHorizontalDrag == true else { return }
        dragX = translation.width
    }

    private func endDrag(translation: CGSize, velocity: CGSize) {
        let wasHorizontal = isHorizontalDrag == true
        isHorizontalDrag = nil
        guard wasHorizontal else {
            dragX = 0
            return
        }
        // Each end of a movement reaches the island, so a waiting pointer
        // exit can start from this moment.
        dragStateChanged(false)
        let width = Double(cardWidth)
        guard NotificationIslandSwipeRule.shouldDismiss(
            dragX: Double(translation.width),
            velocityX: Double(velocity.width),
            cardWidth: width
        ) else {
            withAnimation(returnAnimation) {
                dragX = 0
            }
            return
        }
        if !reduceMotion {
            withAnimation(.easeOut(duration: 0.18)) {
                dragX = CGFloat(
                    NotificationIslandSwipeRule.releaseOffset(cardWidth: width)
                )
            }
        }
        // The list removes the card, so its own transition ends the movement.
        dismiss()
    }

    private var returnAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.18)
            : .spring(duration: 0.35, bounce: 0.2)
    }

    /// Gives the horizontal card position during a drag.
    private var dragOffset: CGFloat {
        CGFloat(
            NotificationIslandSwipeRule.displayOffset(
                dragX: Double(dragX),
                cardWidth: Double(cardWidth),
                reduceMotion: reduceMotion
            )
        )
    }

    /// Gives the card opacity during a drag.
    private var dragOpacity: Double {
        NotificationIslandSwipeRule.displayOpacity(
            offset: Double(dragOffset),
            cardWidth: Double(cardWidth),
            reduceMotion: reduceMotion
        )
    }

    /// Gives the color of the card edge.
    private var cardBorderColor: Color {
        colorSchemeContrast == .increased
            ? (colorScheme == .dark ? Color.white.opacity(0.60) : Color.black.opacity(0.30))
            : (colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.10))
    }

    /// Keeps the card out of the drawing work while it stays behind the pile.
    private func report(rowMaxY: Double, containerHeight: Double) {
        let placement = NotificationIslandLayout.pilePlacement(
            rowMaxY: rowMaxY,
            containerHeight: containerHeight,
            eventCount: eventCount
        )
        let hidden = placement == .hidden
        guard hidden != isHidden else { return }
        withoutAnimation {
            isHidden = hidden
        }
    }

    /// Draws the card again after a change of the panel or of the list.
    private func showCardAgain() {
        guard isHidden else { return }
        withoutAnimation {
            isHidden = false
        }
    }

    /// Keeps one row change out of the list animation.
    private func withoutAnimation(_ change: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, change)
    }

    private static func isBehindThePile(
        rowMaxY: Double,
        containerHeight: Double,
        eventCount: Int
    ) -> Bool {
        NotificationIslandLayout.pilePlacement(
            rowMaxY: rowMaxY,
            containerHeight: containerHeight,
            eventCount: eventCount
        ) == .hidden
    }

    /// Gives the scroll view height, or the height rule when none arrived.
    private static func resolvedContainerHeight(
        _ containerHeight: Double,
        eventCount: Int,
        cameraHousingHeight: Double
    ) -> Double {
        guard containerHeight > 0 else {
            return NotificationIslandLayout.scrollContainerHeight(
                eventCount: eventCount,
                cameraHousingHeight: cameraHousingHeight
            )
        }
        return containerHeight
    }
}

private extension IslandScreenRect {
    var appKitRect: CGRect {
        CGRect(x: minX, y: minY, width: size.width, height: size.height)
    }
}
