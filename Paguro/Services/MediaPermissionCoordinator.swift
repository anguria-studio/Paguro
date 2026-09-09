import Foundation
import SwiftData
import WebKit
import PaguroCore

/// Coordinates capture policy, native prompts, and related media feedback.
@MainActor
@Observable
final class MediaPermissionCoordinator {
    /// The UI-facing form of a queued camera or microphone request.
    struct Request: Identifiable, Equatable {
        let id: UUID
        let serviceLabel: String
        let originHost: String?
        let cameraAsked: Bool
        let microphoneAsked: Bool

        var kindLabel: String {
            switch (cameraAsked, microphoneAsked) {
            case (true, true): return "camera and microphone"
            case (false, true): return "microphone"
            case (true, false): return "camera"
            case (false, false): return "camera or microphone"
            }
        }

        var title: String {
            "Allow \(originHost ?? serviceLabel) to use your \(kindLabel)?"
        }

        var message: String {
            if let originHost {
                return "\(originHost), opened by \(serviceLabel), wants to use your \(kindLabel)."
            }
            return "\(serviceLabel) wants to use your \(kindLabel). Change this anytime in the service's settings."
        }

        static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    }

    /// A one-time offer for a presence-sensitive service.
    struct PresencePrompt: Identifiable, Equatable {
        let id: UUID
        let serviceLabel: String
    }

    private struct PendingEntry {
        let request: Request
        let serviceID: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let context: ModelContext
    private let preferencesStore: PreferencesStore
    private let webViewPool: WebViewPool
    @ObservationIgnored private var queue: [PendingEntry] = []
    @ObservationIgnored private var microphoneFeedbackTask: Task<Void, Never>?
    @ObservationIgnored private var isLocked: @MainActor () -> Bool = { true }
    @ObservationIgnored private var onWebViewRebuilt: @MainActor () -> Void = {}
    @ObservationIgnored private var isStarted = false

    private(set) var pendingRequest: Request?
    private(set) var presencePrompt: PresencePrompt?
    private(set) var microphoneActionFeedback: String?
    private(set) var defaultCameraPolicy: MediaPermissionPolicy
    private(set) var defaultMicrophonePolicy: MediaPermissionPolicy

    init(
        context: ModelContext,
        preferencesStore: PreferencesStore,
        webViewPool: WebViewPool
    ) {
        self.context = context
        self.preferencesStore = preferencesStore
        self.webViewPool = webViewPool
        defaultCameraPolicy = preferencesStore.defaultCameraPolicy
        defaultMicrophonePolicy = preferencesStore.defaultMicrophonePolicy
    }

    /// Connects the coordinator to the pool after application state is ready.
    func start(
        isLocked: @escaping @MainActor () -> Bool,
        onWebViewRebuilt: @escaping @MainActor () -> Void
    ) {
        guard !isStarted else { return }
        isStarted = true
        self.isLocked = isLocked
        self.onWebViewRebuilt = onWebViewRebuilt

        webViewPool.mediaCapturePolicyProvider = { [weak self] serviceID, type, frame in
            await self?.resolve(serviceID: serviceID, type: type, frame: frame) ?? .deny
        }
        webViewPool.onServiceTornDown = { [weak self] serviceID in
            self?.denyRequests(for: serviceID)
        }
    }

    /// Stops prompt-related work and denies every unresolved request.
    func shutdown() {
        microphoneFeedbackTask?.cancel()
        microphoneFeedbackTask = nil
        denyAllRequests()
        webViewPool.mediaCapturePolicyProvider = nil
        webViewPool.onServiceTornDown = nil
        isStarted = false
    }

    /// Applies stored service and global policy to one WebKit request.
    func resolve(
        serviceID: UUID,
        type: WKMediaCaptureType,
        frame: WKFrameInfo
    ) async -> WKPermissionDecision {
        guard let service = fetchService(id: serviceID) else { return .deny }
        let camera = MediaPermissionResolver.effectivePolicy(
            serviceRaw: service.cameraPolicyRaw,
            globalRaw: defaultCameraPolicy.rawValue
        )
        let microphone = MediaPermissionResolver.effectivePolicy(
            serviceRaw: service.microphonePolicyRaw,
            globalRaw: defaultMicrophonePolicy.rawValue
        )
        let kind = Self.captureKind(from: type)
        let resolution = MediaPermissionResolver.resolve(
            kind,
            camera: camera,
            microphone: microphone
        )
        if resolution == .deny { return .deny }

        guard !isLocked() else {
            AppLogger.webView.info("Media capture denied: app is locked")
            return .deny
        }
        guard webViewPool.activeServiceID == serviceID else {
            AppLogger.webView.info("Media capture denied: \(service.label) isn't the active service")
            return .deny
        }

        if isCaptureFrameTrusted(frame, service: service) {
            if resolution == .grant { return .grant }
            let fields = MediaPermissionResolver.askedFields(
                kind,
                camera: camera,
                microphone: microphone
            )
            let allowed = await requestDecision(
                serviceID: serviceID,
                serviceLabel: service.label,
                originHost: nil,
                fields: fields
            )
            persistAnswer(serviceID: serviceID, allow: allowed, fields: fields)
            return allowed ? .grant : .deny
        }

        let originHost = frame.securityOrigin.host
        switch MediaPermissionResolver.foreignCaptureOutcome(
            isMainFrame: frame.isMainFrame,
            originHost: originHost,
            isFirstParty: isFirstPartyService(service),
            resolution: resolution
        ) {
        case .deny:
            logUntrustedDenial(frame, service: service)
            return .deny
        case .grantSilently:
            return .grant
        case .promptNamingOrigin:
            let fields = MediaPermissionResolver.askedFields(
                kind,
                camera: .ask,
                microphone: .ask
            )
            let allowed = await requestDecision(
                serviceID: serviceID,
                serviceLabel: service.label,
                originHost: originHost,
                fields: fields
            )
            return allowed ? .grant : .deny
        }
    }

    /// Queues a native decision and resumes when the user answers or the request
    /// becomes invalid. This is internal so queue behavior can be tested without
    /// constructing a `WKFrameInfo`.
    func requestDecision(
        serviceID: UUID,
        serviceLabel: String,
        originHost: String?,
        fields: MediaPermissionFields
    ) async -> Bool {
        guard fields.camera || fields.microphone else { return false }
        return await withCheckedContinuation { continuation in
            let request = Request(
                id: UUID(),
                serviceLabel: serviceLabel,
                originHost: originHost,
                cameraAsked: fields.camera,
                microphoneAsked: fields.microphone
            )
            queue.append(PendingEntry(
                request: request,
                serviceID: serviceID,
                continuation: continuation
            ))
            if pendingRequest == nil {
                pendingRequest = queue.first?.request
            }
        }
    }

    /// Answers only the request that is currently visible.
    func answerRequest(_ id: UUID, allow: Bool) {
        guard queue.first?.request.id == id else { return }
        let entry = queue.removeFirst()
        entry.continuation.resume(returning: allow)
        presentNextRequest()
    }

    /// Denies prompts for a web view that no longer exists.
    func denyRequests(for serviceID: UUID) {
        guard queue.contains(where: { $0.serviceID == serviceID }) else { return }
        let removedVisibleRequest = queue.first?.serviceID == serviceID
        let denied = queue.filter { $0.serviceID == serviceID }
        queue.removeAll { $0.serviceID == serviceID }
        for entry in denied { entry.continuation.resume(returning: false) }
        if removedVisibleRequest { presentNextRequest() }
    }

    /// Denies and removes all prompts before lock or shutdown.
    func denyAllRequests() {
        guard !queue.isEmpty else { return }
        let denied = queue
        queue.removeAll()
        for entry in denied { entry.continuation.resume(returning: false) }
        pendingRequest = nil
    }

    func reloadConfigurationPreferences() {
        defaultCameraPolicy = preferencesStore.defaultCameraPolicy
        defaultMicrophonePolicy = preferencesStore.defaultMicrophonePolicy
    }

    func setDefaultCameraPolicy(_ policy: MediaPermissionPolicy) {
        guard preferencesStore.setDefaultMediaPolicies(
            camera: policy,
            microphone: defaultMicrophonePolicy
        ) else { return }
        defaultCameraPolicy = policy
    }

    func setDefaultMicrophonePolicy(_ policy: MediaPermissionPolicy) {
        guard preferencesStore.setDefaultMediaPolicies(
            camera: defaultCameraPolicy,
            microphone: policy
        ) else { return }
        defaultMicrophonePolicy = policy
    }

    /// Offers the presence override only for a matching curated service.
    func offerPresenceActivationIfNeeded(serviceID: UUID, catalogEntryID: String?) {
        guard let catalogEntryID,
              ServiceCatalog.shared.entry(for: catalogEntryID)?.presenceSensitive == true,
              let service = fetchService(id: serviceID) else { return }
        presencePrompt = PresencePrompt(id: serviceID, serviceLabel: service.label)
    }

    /// Applies the accepted presence override and rebuilds its live web view.
    func answerPresencePrompt(_ id: UUID, enable: Bool) {
        defer { presencePrompt = nil }
        guard enable, let service = fetchService(id: id) else { return }
        service.stayActiveInBackground = true
        guard context.saveOrRollback(reason: "enable background presence") else { return }
        webViewPool.recreateWebView(for: id)
        onWebViewRebuilt()
    }

    /// Mutes every currently capturing microphone and briefly reports the count.
    func muteActiveMicrophones() {
        let count = webViewPool.muteActiveMicrophones()
        AppLogger.general.info("Muted \(count) live microphone(s)")
        guard let feedback = MicrophoneMutePresentation.confirmation(mutedCount: count) else {
            return
        }
        microphoneActionFeedback = feedback
        microphoneFeedbackTask?.cancel()
        microphoneFeedbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(2))
            } catch {
                return
            }
            guard self?.microphoneActionFeedback == feedback else { return }
            self?.microphoneActionFeedback = nil
        }
    }

    private func presentNextRequest() {
        pendingRequest = nil
        guard let next = queue.first?.request else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  self.pendingRequest == nil,
                  self.queue.first?.request.id == next.id else { return }
            self.pendingRequest = next
        }
    }

    private func persistAnswer(
        serviceID: UUID,
        allow: Bool,
        fields: MediaPermissionFields
    ) {
        guard let service = fetchService(id: serviceID) else { return }
        let policy: MediaPermissionPolicy = allow ? .allow : .deny
        if fields.camera { service.cameraPolicy = policy }
        if fields.microphone { service.microphonePolicy = policy }
        context.saveOrRollback(reason: "persist media permission")
    }

    private func fetchService(id: UUID) -> ServiceInstance? {
        var descriptor = FetchDescriptor<ServiceInstance>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func isCaptureFrameTrusted(_ frame: WKFrameInfo, service: ServiceInstance) -> Bool {
        guard let serviceHost = URL(string: service.url)?.host else { return false }
        let frameHost = frame.securityOrigin.host
        guard !frameHost.isEmpty else { return false }
        return WebRoutingPolicy.belongsToService(frameHost, serviceHost: serviceHost)
    }

    private func isFirstPartyService(_ service: ServiceInstance) -> Bool {
        guard let id = service.catalogEntryID,
              let entry = ServiceCatalog.shared.entry(for: id),
              entry.firstParty == true,
              let serviceHost = URL(string: service.url)?.host,
              let entryHost = URL(string: entry.url)?.host else { return false }
        return WebRoutingPolicy.belongsToService(serviceHost, serviceHost: entryHost)
    }

    private func logUntrustedDenial(_ frame: WKFrameInfo, service: ServiceInstance) {
        let frameHost = frame.securityOrigin.host
        let serviceHost = URL(string: service.url)?.host ?? service.url
        AppLogger.webView.info(
            "Media capture denied: request origin \(frameHost, privacy: .public) doesn't belong to \(service.label, privacy: .public) (\(serviceHost, privacy: .public))"
        )
    }

    private static func captureKind(from type: WKMediaCaptureType) -> MediaCaptureKind {
        switch type {
        case .camera: return .camera
        case .microphone: return .microphone
        case .cameraAndMicrophone: return .cameraAndMicrophone
        @unknown default: return .cameraAndMicrophone
        }
    }
}
