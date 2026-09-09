/// A stored camera or microphone permission for one service.
public enum MediaPermissionPolicy: String, CaseIterable, Sendable {
    case ask, allow, deny
}

/// The devices included in a media-capture request.
///
/// This type mirrors the relevant WebKit cases without making Core depend on
/// WebKit.
public enum MediaCaptureKind: Sendable {
    case camera, microphone, cameraAndMicrophone
}

/// The permission fields that a prompt must decide.
public struct MediaPermissionFields: Equatable, Sendable {
    public let camera: Bool
    public let microphone: Bool

    public init(camera: Bool, microphone: Bool) {
        self.camera = camera
        self.microphone = microphone
    }
}

/// Pure rules for resolving media-capture permissions.
public enum MediaPermissionResolver {
    /// The result of applying the stored permission policy.
    public enum Resolution: Equatable, Sendable {
        case grant, deny, ask
    }

    /// The result for a request from an origin outside the service's own site.
    public enum ForeignCaptureOutcome: Equatable, Sendable {
        case grantSilently, promptNamingOrigin, deny
    }

    /// Returns the service policy, then the global policy, then `.ask`.
    public static func effectivePolicy(
        serviceRaw: String?,
        globalRaw: String?
    ) -> MediaPermissionPolicy {
        if let serviceRaw, let policy = MediaPermissionPolicy(rawValue: serviceRaw) {
            return policy
        }
        if let globalRaw, let policy = MediaPermissionPolicy(rawValue: globalRaw) {
            return policy
        }
        return .ask
    }

    /// Resolves a request with deny taking priority over ask and allow.
    public static func resolve(
        _ kind: MediaCaptureKind,
        camera: MediaPermissionPolicy,
        microphone: MediaPermissionPolicy
    ) -> Resolution {
        switch kind {
        case .camera:
            return resolution(for: camera)
        case .microphone:
            return resolution(for: microphone)
        case .cameraAndMicrophone:
            if camera == .deny || microphone == .deny { return .deny }
            if camera == .ask || microphone == .ask { return .ask }
            return .grant
        }
    }

    /// Returns the requested devices whose policy is `.ask`.
    public static func askedFields(
        _ kind: MediaCaptureKind,
        camera: MediaPermissionPolicy,
        microphone: MediaPermissionPolicy
    ) -> MediaPermissionFields {
        let cameraInvolved: Bool
        let microphoneInvolved: Bool

        switch kind {
        case .camera:
            (cameraInvolved, microphoneInvolved) = (true, false)
        case .microphone:
            (cameraInvolved, microphoneInvolved) = (false, true)
        case .cameraAndMicrophone:
            (cameraInvolved, microphoneInvolved) = (true, true)
        }

        return MediaPermissionFields(
            camera: cameraInvolved && camera == .ask,
            microphone: microphoneInvolved && microphone == .ask
        )
    }

    /// Resolves a request from an origin outside the service's own site.
    ///
    /// A denied policy, subframe, or empty origin fails closed. A curated
    /// first-party service with an existing grant may grant its foreign main
    /// frame silently. Every other valid main-frame request prompts and names
    /// its real origin.
    public static func foreignCaptureOutcome(
        isMainFrame: Bool,
        originHost: String,
        isFirstParty: Bool,
        resolution: Resolution
    ) -> ForeignCaptureOutcome {
        guard resolution != .deny, isMainFrame, !originHost.isEmpty else { return .deny }
        if isFirstParty, resolution == .grant { return .grantSilently }
        return .promptNamingOrigin
    }

    private static func resolution(for policy: MediaPermissionPolicy) -> Resolution {
        switch policy {
        case .allow: return .grant
        case .deny: return .deny
        case .ask: return .ask
        }
    }
}
