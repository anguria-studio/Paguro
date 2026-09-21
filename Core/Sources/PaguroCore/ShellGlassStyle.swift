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

/// Resolves saved choices without changing them when platform support differs.
public enum ShellGlassSupport: Sendable {
    case unavailable
    case presets
    case systemAppearance

    public var availableStyles: [ShellGlassStyle] {
        switch self {
        case .unavailable: []
        case .presets: [.off, .clear, .regular]
        case .systemAppearance: ShellGlassStyle.allCases
        }
    }

    public func effectiveStyle(for preference: ShellGlassStyle) -> ShellGlassStyle {
        switch self {
        case .unavailable: .off
        case .presets: preference == .system ? .regular : preference
        case .systemAppearance: preference
        }
    }
}
