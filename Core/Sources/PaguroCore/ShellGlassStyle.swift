/// The window material preference, separate from light or dark appearance.
public enum ShellGlassStyle: String, CaseIterable, Sendable {
    case system
    case off
    case clear
    case regular

    /// Fixed app tint strength. Native glass still responds to accessibility
    /// preferences; system mode adds no tint of its own.
    public var transparency: Double {
        switch self {
        case .system, .clear: 1
        case .off: 0
        case .regular: 0.85
        }
    }

    /// Extra backdrop frost, separate from the native glass material.
    public var backdropFrostOpacity: Double {
        switch self {
        case .system, .off: 0
        case .clear: 0.45
        case .regular: 1
        }
    }
}
