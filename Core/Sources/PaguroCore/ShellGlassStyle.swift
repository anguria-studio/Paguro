/// The window material preference, separate from light or dark appearance.
public enum ShellGlassStyle: String, CaseIterable, Sendable {
    case system
    case off
    case clear
    case regular

    /// System mode leaves tint strength to the native material. Keep the saved
    /// manual value separate so selecting an override restores it.
    public func effectiveTransparency(manualValue: Double) -> Double {
        self == .system ? 1 : min(1, max(0, manualValue))
    }
}
