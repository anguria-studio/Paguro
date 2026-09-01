import AppKit
import BlattaCore

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

    /// Starts runtime work once AppKit is ready for platform side effects.
    var startAfterLaunch: (@MainActor () -> Void)? {
        didSet {
            guard hasFinishedLaunching else { return }
            startAfterLaunch?()
        }
    }

    /// Runs once the launch activation has settled: the application has become
    /// active and AppKit has brought the initial main window forward.
    ///
    /// A window that never takes the front — the island's non-activating panel
    /// — must wait for this hook. Ordering such a window while the launch
    /// activation is still in flight leaves the main window behind the
    /// application that started Blatta.
    var launchActivationDidSettle: (@MainActor () -> Void)? {
        didSet {
            guard hasSettledLaunchActivation else { return }
            launchActivationDidSettle?()
        }
    }

    /// Runs each time Blatta becomes the active application. The island uses this
    /// hook, because the user then reads the active service account again.
    var didBecomeActive: (@MainActor () -> Void)?

    /// Asks SwiftUI to open the main window scene.
    ///
    /// Only SwiftUI can create the window of the `Window(id: "main")` scene, so
    /// the view layer fills this hook and AppKit calls it when no such window
    /// exists any more.
    var openMainWindow: (@MainActor () -> Void)?

    private var isSettlingLoginLaunch = false
    private var isTerminating = false
    private var hasFinishedLaunching = false
    private var hasActivatedSinceLaunch = false
    private var hasSettledLaunchActivation = false
    private var launchState = ApplicationActivationState.regular
    /// A regular activation policy only makes Blatta eligible for Command-Tab.
    /// It does not make the initial SwiftUI window key. Keep this request until
    /// the scene has produced a visible main-capable window.
    private var isAwaitingInitialWindowActivation = false

    /// The moment until which an activation belongs to Blatta's own request.
    ///
    /// `takeFrontForUserAction` is static, because a view can start that route
    /// without the delegate instance, so this marker is static too.
    private static var selfActivationRequestDeadline: ContinuousClock.Instant?

    /// A request that Blatta made for itself expires after this time.
    ///
    /// The system answers an activation request through the window server, so
    /// the answer arrives several event-loop passes later. The value covers
    /// that delay and stays far below the time a person needs to reach
    /// Command-Tab.
    private static let selfActivationRequestLifetime = Duration.seconds(2)

    /// Tells whether the current activation follows a request of Blatta itself.
    private var isSelfInitiatedActivation: Bool {
        guard let deadline = Self.selfActivationRequestDeadline else {
            return false
        }
        return ContinuousClock.now < deadline
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        hasFinishedLaunching = true
        startAfterLaunch?()
        observeWindows()

        let launchState = ApplicationLifecyclePolicy.activationAtLaunch(
            launchedAsLoginItem: Self.launchedAsLoginItem,
            keepsDockIconVisible: alwaysShowDockIcon
        )
        self.launchState = launchState
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

    /// Command-Tab activates the process but does not issue a reopen request,
    /// so this hook must give every activation a visible result.
    ///
    /// A visible main window comes forward. A window that AppKit already made
    /// key is that result already, and the launch activation arrives here too,
    /// so the redundant order request is skipped.
    ///
    /// With no visible main-capable window, the window comes back. A Dock click
    /// runs the reopen handler and this restore, and both are safe to repeat:
    /// `Window(id: "main")` is a unique scene, and a second order request for
    /// the same window changes nothing.
    func applicationDidBecomeActive(_ notification: Notification) {
        hasActivatedSinceLaunch = true
        didBecomeActive?()

        // Read the marker before any branch returns, and drop it at once. The
        // request that set it describes this activation only.
        let isSelfInitiated = isSelfInitiatedActivation
        Self.selfActivationRequestDeadline = nil

        let state = Self.activationState
        guard hasFinishedLaunching,
              !isSettlingLoginLaunch,
              !isTerminating,
              state == .regular
        else { return }

        if let window = mainWindow, window.isVisible {
            guard !window.isKeyWindow else { return }
            window.makeKeyAndOrderFront(nil)
            return
        }

        let visibleMainWindowCount = NSApp.windows.filter {
            Self.carriesMainWindowLifecycle($0) && $0.isVisible
        }.count
        guard ApplicationLifecyclePolicy.restoresMainWindowOnActivation(
            state: state,
            isSelfInitiated: isSelfInitiated,
            visibleMainWindowCount: visibleMainWindowCount
        ) else { return }

        bringMainWindowForward()
    }

    /// SwiftUI can create its Window scene after the launch callback. AppKit's
    /// update hook provides a public, bounded retry point; the pending flag is
    /// cleared as soon as the main window is available.
    func applicationDidUpdate(_ notification: Notification) {
        activateInitialWindowIfAvailable()
        settleLaunchActivationIfReady()
    }

    /// Releases the work that waits for the end of the launch activation.
    ///
    /// AppKit calls the update hook after every event-loop pass, so this runs
    /// after the delegate's own activation and window callbacks rather than
    /// racing them.
    private func settleLaunchActivationIfReady() {
        guard !hasSettledLaunchActivation, hasFinishedLaunching else { return }
        guard ApplicationLifecyclePolicy.hasLaunchActivationSettled(
            launchState: launchState,
            hasActivatedSinceLaunch: hasActivatedSinceLaunch,
            isAwaitingInitialWindowActivation: isAwaitingInitialWindowActivation,
            isSettlingLoginLaunch: isSettlingLoginLaunch,
            hasMainWindow: NSApp.mainWindow != nil
        ) else { return }

        hasSettledLaunchActivation = true
        launchActivationDidSettle?()
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
    ///
    /// This is the explicit request that follows a person's action, never the
    /// launch request: at launch the system is already activating Blatta and a
    /// second request costs it the front.
    static func prepareToShowWindow() {
        apply(ApplicationLifecyclePolicy.activationBeforeShowingMainWindow())
        takeFrontForUserAction()
    }

    /// Takes the front for an action that a person performed.
    ///
    /// macOS 14 replaced `activate(ignoringOtherApps:)` with a cooperative
    /// exchange, in which the application that holds the front hands it over.
    /// Naming that application makes the request succeed without the
    /// deprecated call.
    private static func takeFrontForUserAction() {
        let frontApplication = NSWorkspace.shared.frontmostApplication
        let request = ApplicationLifecyclePolicy.activationRequestForUserAction(
            isApplicationActive: NSApp.isActive,
            hasOtherFrontApplication: frontApplication != nil
                && frontApplication != .current
        )
        switch request {
        case .none:
            return
        case .cooperative:
            markSelfInitiatedActivation()
            NSApp.activate()
        case .takeFront:
            guard let frontApplication else { return }
            markSelfInitiatedActivation()
            NSRunningApplication.current.activate(from: frontApplication)
        }
    }

    /// Marks the activation that Blatta requests for one of its own windows.
    ///
    /// `applicationDidBecomeActive` must not restore the main window for such a
    /// request: the caller shows a window of its own directly after it, and a
    /// restored main window would cover that window. The menu-bar Settings
    /// button takes this route.
    ///
    /// The marker expires by time and never latches. A request can produce no
    /// activation callback, and a marker that waited for one would then swallow
    /// the next real Command-Tab.
    private static func markSelfInitiatedActivation() {
        selfActivationRequestDeadline = ContinuousClock.now
            .advanced(by: selfActivationRequestLifetime)
    }

    /// The activation state that AppKit currently applies.
    private static var activationState: ApplicationActivationState {
        NSApp.activationPolicy() == .regular ? .regular : .accessory
    }

    /// Activates Blatta and shows its main window after an external action.
    ///
    /// A closed main window leaves AppKit with no window to order forward, so
    /// the request goes to SwiftUI, which builds the window scene again.
    func bringMainWindowForward() {
        Self.prepareToShowWindow()
        guard let window = mainWindow else {
            openMainWindow?()
            return
        }
        window.makeKeyAndOrderFront(nil)
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
        guard let window = notification.object as? NSWindow,
              Self.carriesMainWindowLifecycle(window) else { return }
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
              Self.carriesMainWindowLifecycle(closingWindow) else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let visibleMainWindowCount = NSApp.windows.filter {
                $0 !== closingWindow
                    && Self.carriesMainWindowLifecycle($0)
                    && $0.isVisible
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

    /// Tells whether a window drives Blatta's main-window lifecycle.
    ///
    /// The window-style menu bar extra owns a borderless status window, and
    /// AppKit and the text input system add further borderless windows while
    /// Blatta starts. None of them is a window a person opened, so none of them
    /// may promote the activation policy, hide the application, or count as the
    /// last window on screen.
    private static func carriesMainWindowLifecycle(_ window: NSWindow) -> Bool {
        window.canBecomeMain && window.styleMask.contains(.titled)
    }

    private func reconcileActivationPolicy() {
        let visibleMainWindowCount = NSApp.windows.filter {
            Self.carriesMainWindowLifecycle($0) && $0.isVisible
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
        Self.apply(ApplicationLifecyclePolicy.activationBeforeShowingMainWindow())

        // `LSUIElement` is NO, so the system already brought Blatta to the front
        // and AppKit already made this window key. Repeating either request
        // hands the front back to the application that launched Blatta: an
        // activation request from an application that is already active enters
        // the macOS 14 cooperative exchange, and the launching application wins
        // it. Ask only for the part that is still missing.
        let activation = ApplicationLifecyclePolicy.initialWindowActivation(
            isApplicationActive: NSApp.isActive,
            isMainWindowKey: window.isKeyWindow
        )
        if activation.activatesApplication {
            NSApp.activate()
        }
        if activation.ordersWindowForward {
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// SwiftUI uses the scene ID as the AppKit identifier. The title fallback
    /// covers an initial scene window before SwiftUI assigns that identifier.
    /// It requires a titled window: the window-style menu bar extra also has
    /// the title "Blatta" but is borderless, and activating it at launch left
    /// the real window behind.
    private var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue == "main" }
            ?? NSApp.windows.first {
                Self.carriesMainWindowLifecycle($0) && $0.title == "Blatta"
            }
    }

    private func closeMainWindows() {
        for window in NSApp.windows
        where Self.carriesMainWindowLifecycle(window) && window.isVisible {
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
