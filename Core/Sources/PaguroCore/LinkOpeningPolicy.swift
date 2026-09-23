/// Chooses the destination for web links that no configured service owns.
public enum LinkOpeningPolicy: String, CaseIterable, Sendable {
    case followGlobal
    case paguro
    case browser

    public init(override: Bool?) {
        switch override {
        case true: self = .paguro
        case false: self = .browser
        case nil: self = .followGlobal
        }
    }

    public var override: Bool? {
        switch self {
        case .followGlobal: nil
        case .paguro: true
        case .browser: false
        }
    }

    public func opensInPaguro(globalDefault: Bool) -> Bool {
        override ?? globalDefault
    }
}
