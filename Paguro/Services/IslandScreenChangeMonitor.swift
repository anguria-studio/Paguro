import AppKit

/// Reports public system changes that can move the notification island.
@MainActor
protocol IslandScreenChangeMonitoring: AnyObject {
    func start(onChange: @escaping @MainActor () -> Void)
    func stop()
}

/// Observes screen, main-window, Space, and wake changes while the island is visible.
@MainActor
final class IslandScreenChangeMonitor: NSObject, IslandScreenChangeMonitoring {
    typealias WindowFilter = @MainActor (NSWindow) -> Bool

    private let notificationCenter: NotificationCenter
    private let workspaceNotificationCenter: NotificationCenter
    private let windowFilter: WindowFilter
    private var onChange: (@MainActor () -> Void)?
    private var isObserving = false

    init(
        notificationCenter: NotificationCenter = .default,
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        windowFilter: @escaping WindowFilter = IslandScreenChangeMonitor.isMainPaguroWindow
    ) {
        self.notificationCenter = notificationCenter
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.windowFilter = windowFilter
    }

    func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        guard !isObserving else { return }
        isObserving = true

        observeSystemChanges()
        observeWindowChanges()
        observeWorkspaceChanges()
    }

    func stop() {
        guard isObserving else {
            onChange = nil
            return
        }
        isObserving = false
        onChange = nil
        notificationCenter.removeObserver(self)
        workspaceNotificationCenter.removeObserver(self)
    }

    @objc private func systemGeometryDidChange(_ notification: Notification) {
        onChange?()
    }

    @objc private func trackedWindowDidChange(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              windowFilter(window) else {
            return
        }
        onChange?()
    }

    @objc private func workspaceGeometryDidChange(_ notification: Notification) {
        onChange?()
    }

    private func observeSystemChanges() {
        notificationCenter.addObserver(
            self,
            selector: #selector(systemGeometryDidChange(_:)),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func observeWindowChanges() {
        let names: [Notification.Name] = [
            NSWindow.didMoveNotification,
            NSWindow.didChangeScreenNotification,
            NSWindow.didChangeBackingPropertiesNotification,
            NSWindow.didEndLiveResizeNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.willCloseNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification
        ]
        for name in names {
            notificationCenter.addObserver(
                self,
                selector: #selector(trackedWindowDidChange(_:)),
                name: name,
                object: nil
            )
        }
    }

    private func observeWorkspaceChanges() {
        let names: [Notification.Name] = [
            NSWorkspace.activeSpaceDidChangeNotification,
            NSWorkspace.didWakeNotification
        ]
        for name in names {
            workspaceNotificationCenter.addObserver(
                self,
                selector: #selector(workspaceGeometryDidChange(_:)),
                name: name,
                object: nil
            )
        }
    }

    private static func isMainPaguroWindow(_ window: NSWindow) -> Bool {
        window.identifier?.rawValue == "main"
            || (window.canBecomeMain
                && window.styleMask.contains(.titled)
                && window.title == "Paguro")
    }
}
