/// What happened when Blatta asked macOS for the notification permission.
///
/// The two cases carry the whole distinction between a refusal by the user and
/// a failure of the platform. macOS answers a permission request that it can
/// run, even when its answer is "no": it returns, and the reported permission
/// holds the decision. macOS throws only when it cannot run the request at
/// all, which means it never asked the user.
public enum NotificationAuthorizationRequestOutcome: String, Equatable, Sendable {
    /// macOS ran the request. The reported permission holds the answer.
    case completed
    /// macOS refused the request and asked nobody.
    case failed
}

/// The state machine for the macOS notification permission.
///
/// Blatta must separate two states that look the same from the outside. In
/// both, no banner appears and `notificationSettings()` reports `denied`:
///
/// - the user refused the permission, which Blatta must remember and respect;
/// - macOS never registered Blatta, which Blatta must retry at each start.
///
/// The permission alone cannot separate them, so the state machine uses the
/// request outcome instead.
public enum NotificationAuthorizationPolicy {
    /// Tells whether Blatta asks macOS for the permission at this start.
    ///
    /// Blatta asks once for each start unless macOS already permits the
    /// notification. A request under a stored refusal shows no prompt and
    /// disturbs nobody: macOS answers it from that stored decision. That
    /// harmless request is the only way to separate a stored refusal from an
    /// app that macOS never registered, so Blatta always makes it.
    public static func shouldRequest(
        for state: NotificationAuthorizationState
    ) -> Bool {
        switch state {
        case .authorized, .provisional:
            return false
        case .unknown, .notDetermined, .denied, .unavailable:
            return true
        }
    }

    /// Returns the state that follows one permission request.
    ///
    /// A request that macOS ran gives an authoritative answer, so the reported
    /// permission wins. A request that macOS refused gives no answer about the
    /// user at all, so the state becomes `unavailable` whatever macOS reports.
    public static func state(
        after outcome: NotificationAuthorizationRequestOutcome,
        reportedState: NotificationAuthorizationState
    ) -> NotificationAuthorizationState {
        switch outcome {
        case .completed:
            return reportedState
        case .failed:
            return .unavailable
        }
    }

    /// Merges a fresh permission read into the state that Blatta holds.
    ///
    /// Blatta reads the permission again at each activation, because the user
    /// changes it in System Settings. After a refused request macOS keeps
    /// reporting `denied`, so a plain overwrite would turn `unavailable` into
    /// a refusal that the user never made. This rule therefore keeps
    /// `unavailable` until macOS reports a permission that actually delivers.
    public static func merge(
        current: NotificationAuthorizationState,
        reported: NotificationAuthorizationState
    ) -> NotificationAuthorizationState {
        guard current == .unavailable else { return reported }
        switch reported {
        case .authorized, .provisional:
            return reported
        case .unknown, .notDetermined, .denied, .unavailable:
            return .unavailable
        }
    }

    /// Tells whether Blatta keeps this state across a restart.
    ///
    /// Blatta stores no permission of its own. This rule describes the macOS
    /// behaviour that the retry rule depends on: macOS remembers a refusal,
    /// and it remembers no failure. A test holds the rule to that contract.
    public static func survivesRestart(
        _ state: NotificationAuthorizationState
    ) -> Bool {
        switch state {
        case .authorized, .denied, .provisional, .notDetermined:
            return true
        case .unavailable, .unknown:
            return false
        }
    }
}
