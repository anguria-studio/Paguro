/// Features available in each build, independent of a user's preferences.
public enum AppDistribution: Sendable {
    case development
    case directDownload
    case appStore

    public var supportsSelfUpdates: Bool { self == .directDownload }
    public var supportsGoogleIconFallback: Bool { self != .appStore }
}
