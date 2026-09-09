import Testing
@testable import PaguroCore

struct MediaPermissionResolverTests {
    @Test
    func effectivePolicyPrefersServiceThenGlobalThenAsk() {
        #expect(MediaPermissionResolver.effectivePolicy(
            serviceRaw: "allow", globalRaw: "deny") == .allow)
        #expect(MediaPermissionResolver.effectivePolicy(
            serviceRaw: nil, globalRaw: "deny") == .deny)
        #expect(MediaPermissionResolver.effectivePolicy(
            serviceRaw: nil, globalRaw: nil) == .ask)
        #expect(MediaPermissionResolver.effectivePolicy(
            serviceRaw: "garbage", globalRaw: nil) == .ask)
    }

    @Test
    func singleDeviceRequestReadsOnlyItsMatchingField() {
        #expect(MediaPermissionResolver.resolve(
            .camera, camera: .allow, microphone: .deny) == .grant)
        #expect(MediaPermissionResolver.resolve(
            .camera, camera: .deny, microphone: .allow) == .deny)
        #expect(MediaPermissionResolver.resolve(
            .camera, camera: .ask, microphone: .allow) == .ask)

        #expect(MediaPermissionResolver.resolve(
            .microphone, camera: .allow, microphone: .deny) == .deny)
        #expect(MediaPermissionResolver.resolve(
            .microphone, camera: .deny, microphone: .allow) == .grant)
        #expect(MediaPermissionResolver.resolve(
            .microphone, camera: .allow, microphone: .ask) == .ask)
    }

    @Test
    func combinedRequestUsesTheMostRestrictivePolicy() {
        #expect(MediaPermissionResolver.resolve(
            .cameraAndMicrophone, camera: .allow, microphone: .allow) == .grant)
        #expect(MediaPermissionResolver.resolve(
            .cameraAndMicrophone, camera: .deny, microphone: .allow) == .deny)
        #expect(MediaPermissionResolver.resolve(
            .cameraAndMicrophone, camera: .ask, microphone: .deny) == .deny)
        #expect(MediaPermissionResolver.resolve(
            .cameraAndMicrophone, camera: .ask, microphone: .allow) == .ask)
        #expect(MediaPermissionResolver.resolve(
            .cameraAndMicrophone, camera: .allow, microphone: .ask) == .ask)
    }

    @Test
    func askedFieldsAreGatedByRequestKindAndPolicy() {
        #expect(MediaPermissionResolver.askedFields(
            .microphone, camera: .ask, microphone: .ask
        ) == MediaPermissionFields(camera: false, microphone: true))
        #expect(MediaPermissionResolver.askedFields(
            .camera, camera: .ask, microphone: .ask
        ) == MediaPermissionFields(camera: true, microphone: false))
        #expect(MediaPermissionResolver.askedFields(
            .cameraAndMicrophone, camera: .ask, microphone: .allow
        ) == MediaPermissionFields(camera: true, microphone: false))
        #expect(MediaPermissionResolver.askedFields(
            .cameraAndMicrophone, camera: .ask, microphone: .ask
        ) == MediaPermissionFields(camera: true, microphone: true))
    }

    @Test
    func foreignCaptureGrantsSilentlyOnlyForFirstPartyAllow() {
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: true,
            originHost: "messenger.com",
            isFirstParty: true,
            resolution: .grant
        ) == .grantSilently)
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: true,
            originHost: "messenger.com",
            isFirstParty: true,
            resolution: .ask
        ) == .promptNamingOrigin)
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: true,
            originHost: "evil.example.com",
            isFirstParty: false,
            resolution: .grant
        ) == .promptNamingOrigin)
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: false,
            originHost: "messenger.com",
            isFirstParty: true,
            resolution: .grant
        ) == .deny)
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: true,
            originHost: "",
            isFirstParty: true,
            resolution: .grant
        ) == .deny)
        #expect(MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: true,
            originHost: "messenger.com",
            isFirstParty: true,
            resolution: .deny
        ) == .deny)
    }
}
