/// One explanation of the app's passkey limitation, independent of services.
public struct PasskeyNoticeState: Equatable, Sendable {
    public private(set) var hasBeenSeen: Bool
    public private(set) var isVisible = false

    public init(hasBeenSeen: Bool) {
        self.hasBeenSeen = hasBeenSeen
    }

    /// A locked window cannot present or consume the explanation.
    public mutating func present(isLocked: Bool, passkeysSupported: Bool) {
        guard !isLocked, !passkeysSupported, !hasBeenSeen else { return }
        hasBeenSeen = true
        isVisible = true
    }

    public mutating func dismiss() {
        isVisible = false
    }
}
