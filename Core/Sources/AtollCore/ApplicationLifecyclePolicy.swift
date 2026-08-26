/// Activation states that the macOS adapter can apply to the application.
///
/// This value stays free of AppKit so lifecycle decisions can be tested in
/// AtollCore. The app delegate maps the result to an AppKit activation policy.
public enum ApplicationActivationState: Equatable, Sendable {
    case regular
    case accessory
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
