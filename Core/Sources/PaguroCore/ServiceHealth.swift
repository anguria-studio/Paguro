/// The current loading state of a service page.
public enum ServiceHealth: Equatable, CaseIterable, Sendable {
    case live
    case loading
    case failed
    case signedOut

    /// A navigation event that can change service health.
    public enum Event: CaseIterable, Sendable {
        case startedLoading
        case finishedLoading
        case failed
    }

    /// Returns the health state after a navigation event.
    public func next(_ event: Event) -> ServiceHealth {
        switch event {
        case .startedLoading: return .loading
        case .finishedLoading: return .live
        case .failed: return .failed
        }
    }

    /// Whether the service needs a visible health mark.
    public var drawsDot: Bool { self != .live }

    /// The shape that distinguishes each visible health state without color.
    public enum DotShape: Hashable, Sendable {
        case ring
        case disc
        case square
    }

    /// The shape of the service's health mark.
    public var dotShape: DotShape {
        switch self {
        case .loading: return .ring
        case .failed: return .disc
        case .signedOut: return .square
        case .live: return .disc
        }
    }

    /// The health description used in an accessibility label.
    public var spokenDescription: String {
        switch self {
        case .live: return ""
        case .loading: return "loading"
        case .failed: return "failed to load"
        case .signedOut: return "signed out"
        }
    }
}
