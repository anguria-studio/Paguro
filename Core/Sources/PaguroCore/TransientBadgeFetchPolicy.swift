/// Pure rule that decides which services the transient badge fetch may load.
///
/// The transient fetch loads a full copy of a service page in a hidden web
/// view on the service's own data store, then tears it down after a short
/// window. For most services this is harmless. A chat service is different:
/// WhatsApp Web allows one live client for each session and keeps its
/// multi-device keys in IndexedDB. A hidden copy that boots next to the real
/// view, or that is torn down during a write, can log the session out.
///
/// Chat services (notification-critical) do not need this fetch. Launch
/// preload keeps them live and both hibernation sweeps exempt them, so their
/// live view supplies the badge.
public enum TransientBadgeFetchPolicy {
    public static func shouldFetch(
        hasLiveWebView: Bool,
        isMuted: Bool,
        showsBadge: Bool,
        isNotificationCritical: Bool
    ) -> Bool {
        !hasLiveWebView && !isMuted && showsBadge && !isNotificationCritical
    }
}
