import AppKit
import AtollCore

/// Applies the macOS lifecycle contract while SwiftUI owns the scenes.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// A user preference can keep the Dock icon present without a window.
    var alwaysShowDockIcon = false {
        didSet {
            guard hasFinishedLaunching, alwaysShowDockIcon != oldValue else { return }
            reconcileActivationPolicy()
        }
    }

    /// AppKit waits for this hook before it completes a requested quit.
    var flushBeforeTerminate: (@MainActor () async -> Void)?

    private var isSettlingLoginLaunch = false
    private var isTerminating = false
    private var hasFinishedLaunching = false
    /// A regular activation policy only makes Atoll eligible for Command-Tab.
    /// It does not make the initial SwiftUI window key. Keep this request until
    /// the scene has produced a visible main-capable window.
    private var isAwaitingInitialWindowActivation = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        observeWindows()

        let launchState = ApplicationLifecyclePolicy.activationAtLaunch(
            launchedAsLoginItem: Self.launchedAsLoginItem,
            keepsDockIconVisible: alwaysShowDockIcon
        )
        Self.apply(launchState)

        guard launchState == .accessory else {
            isAwaitingInitialWindowActivation = true
            activateInitialWindowIfAvailable()
            DispatchQueue.main.async { [weak self] in
                self?.activateInitialWindowIfAvailable()
            }
            return
        }
        isSettlingLoginLaunch = true
        closeMainWindows()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closeMainWindows()
            self.isSettlingLoginLaunch = false
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// A Dock click asks AppKit to reopen the application. Promote first so an
    /// accessory launch cannot create its window behind the current app.
    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        Self.prepareToShowWindow()
        guard let window = mainWindow else {
            // Let SwiftUI create the Window scene when AppKit no longer owns an
            // existing instance that can be ordered forward.
            return true
        }
        window.makeKeyAndOrderFront(nil)
        return false
    }

    /// Command-Tab activates the process but does not issue a reopen request.
    /// Re-order an existing visible main window so activation always has a
    /// visible result.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard hasFinishedLaunching,
              !isSettlingLoginLaunch,
              !isTerminating,
              NSApp.activationPolicy() == .regular,
              let window = mainWindow,
              window.isVisible
        else { return }

        window.makeKeyAndOrderFront(nil)
    }

    /// SwiftUI can create its Window scene after the launch callback. AppKit's
    /// update hook provides a public, bounded retry point; the pending flag is
    /// cleared as soon as the main window is available.
    func applicationDidUpdate(_ notification: Notification) {
        activateInitialWindowIfAvailable()
    }

    /// AppKit must delay termination because `applicationWillTerminate` cannot
    /// wait for asynchronous cleanup.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        guard let flushBeforeTerminate else { return .terminateNow }

        isTerminating = true
        Task { @MainActor in
            await flushBeforeTerminate()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Promote before opening a window. Opening first can place the window
    /// behind the currently active application.
    static func prepareToShowWindow() {
        apply(ApplicationLifecyclePolicy.activationBeforeShowingMainWindow())
        NSApp.activate(ignoringOtherApps: true)
    }

    private func observeWindows() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(windowDidBecomeMain(_:)),
            name: NSWindow.didBecomeMainNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeMain(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.canBecomeMain else { return }
        if isSettlingLoginLaunch {
            window.close()
            return
        }
        guard NSApp.activationPolicy() != .regular else { return }

        Self.prepareToShowWindow()
        DispatchQueue.main.async {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
              closingWindow.canBecomeMain else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visibleMainWindowCount = NSApp.windows.filter {
                $0 !== closingWindow && $0.canBecomeMain && $0.isVisible
            }.count
            let state = ApplicationLifecyclePolicy.activationAfterClosingMainWindow(
                visibleMainWindowCount: visibleMainWindowCount,
                keepsDockIconVisible: self.alwaysShowDockIcon
            )
            guard state == .accessory, NSApp.activationPolicy() != .accessory else { return }
            Self.apply(state)
            NSApp.hide(nil)
        }
    }

    private func reconcileActivationPolicy() {
        let visibleMainWindowCount = NSApp.windows.filter {
            $0.canBecomeMain && $0.isVisible
        }.count
        let state = ApplicationLifecyclePolicy.activationAfterClosingMainWindow(
            visibleMainWindowCount: visibleMainWindowCount,
            keepsDockIconVisible: alwaysShowDockIcon
        )
        Self.apply(state)
    }

    private func activateInitialWindowIfAvailable() {
        guard isAwaitingInitialWindowActivation else { return }
        guard let window = mainWindow else { return }

        isAwaitingInitialWindowActivation = false
        Self.prepareToShowWindow()
        window.makeKeyAndOrderFront(nil)
    }

    /// SwiftUI uses the scene ID as the AppKit identifier. The title fallback
    /// covers an initial scene window before SwiftUI assigns that identifier.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first { $0.canBecomeMain && $0.title == "Atoll" }
    }

    private func closeMainWindows() {
        for window in NSApp.windows where window.canBecomeMain && window.isVisible {
            window.close()
        }
    }

    private static func apply(_ state: ApplicationActivationState) {
        switch state {
        case .regular:
            NSApp.setActivationPolicy(.regular)
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent else {
            return false
        }
        return event.eventID == kAEOpenApplication
            && event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
                == keyAELaunchedAsLogInItem
    }
}
