/// Activation states that the macOS adapter can apply to the application.
///
/// This value stays free of AppKit so lifecycle decisions can be tested in
/// AtollCore. The app delegate maps the result to an AppKit activation policy.
public enum ApplicationActivationState: Equatable, Sendable {
    case regular
    case accessory
}

/// The two launch requests that the adapter can still owe after the system
/// has started a regular application.
///
/// A regular application is already the front application by the time its
/// scene produces the first window, and that window is already key. Repeating
/// either request is not free: an activation request enters the macOS 14
/// cooperative activation exchange, where the application that launched Atoll
/// can win the front back, and an order request competes with the ordering
/// AppKit performs for the same window.
public struct InitialWindowActivation: Equatable, Sendable {
    public let activatesApplication: Bool
    public let ordersWindowForward: Bool

    public init(activatesApplication: Bool, ordersWindowForward: Bool) {
        self.activatesApplication = activatesApplication
        self.ordersWindowForward = ordersWindowForward
    }
}

/// How Atoll asks for the front when a person acts on it from elsewhere.
public enum ApplicationActivationRequest: Equatable, Sendable {
    /// Atoll already owns the front. Only its window needs to come forward.
    case none
    /// Atoll asks the system for the front.
    case cooperative
    /// Atoll takes the front from the application that owns it.
    case takeFront
}

/// Pure rules for application activation and shutdown.
public enum ApplicationLifecyclePolicy {
    /// A login-item launch stays out of the Dock until a window is requested.
    public static func activationAtLaunch(
        launchedAsLoginItem: Bool,
        keepsDockIconVisible: Bool
    ) -> ApplicationActivationState {
        if launchedAsLoginItem && !keepsDockIconVisible {
            return .accessory
        }
        return .regular
    }

    /// A visible main window always requires regular activation.
    public static func activationBeforeShowingMainWindow() -> ApplicationActivationState {
        .regular
    }

    /// Asks only for what the launch state still lacks.
    ///
    /// The system activates a regular application at launch and AppKit makes
    /// its first window key. Asking again for either one competes with the work
    /// the system already did, so each request survives only while its result
    /// is missing.
    public static func initialWindowActivation(
        isApplicationActive: Bool,
        isMainWindowKey: Bool
    ) -> InitialWindowActivation {
        InitialWindowActivation(
            activatesApplication: !isApplicationActive,
            ordersWindowForward: !isMainWindowKey
        )
    }

    /// Tells whether the launch activation has finished.
    ///
    /// A window that never takes the front — the island's non-activating panel
    /// — must wait for this point. An order request that arrives earlier joins
    /// the ordering AppKit performs for the launch activation, and the main
    /// window can stay behind the application that started Atoll.
    ///
    /// A regular launch finishes once the application has become active and
    /// AppKit has made the initial main window main. A login launch shows no
    /// window at all, so it finishes as soon as its settling pass is over.
    public static func hasLaunchActivationSettled(
        launchState: ApplicationActivationState,
        hasActivatedSinceLaunch: Bool,
        isAwaitingInitialWindowActivation: Bool,
        isSettlingLoginLaunch: Bool,
        hasMainWindow: Bool
    ) -> Bool {
        switch launchState {
        case .regular:
            return hasActivatedSinceLaunch
                && !isAwaitingInitialWindowActivation
                && hasMainWindow
        case .accessory:
            return !isSettlingLoginLaunch
        }
    }

    /// A person acting on Atoll from elsewhere must reach a front window.
    ///
    /// This request is not the launch request: no system activation is under
    /// way, so Atoll must name the application that holds the front and take
    /// it. With no other front application, the plain request is enough.
    public static func activationRequestForUserAction(
        isApplicationActive: Bool,
        hasOtherFrontApplication: Bool
    ) -> ApplicationActivationRequest {
        if isApplicationActive {
            return .none
        }
        return hasOtherFrontApplication ? .takeFront : .cooperative
    }

    /// After the final main window closes, keep a requested Dock icon or return
    /// to menu-bar-only operation.
    public static func activationAfterClosingMainWindow(
        visibleMainWindowCount: Int,
        keepsDockIconVisible: Bool
    ) -> ApplicationActivationState {
        if visibleMainWindowCount > 0 || keepsDockIconVisible {
            return .regular
        }
        return .accessory
    }
}

/// Makes repeated termination requests share one shutdown operation.
public struct ApplicationShutdownState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case running
        case stopping
        case stopped
    }

    public private(set) var phase: Phase = .running

    public init() {}

    /// Returns true only for the caller that must start shutdown work.
    public mutating func begin() -> Bool {
        guard phase == .running else { return false }
        phase = .stopping
        return true
    }

    public mutating func finish() {
        guard phase == .stopping else { return }
        phase = .stopped
    }
}
