import Foundation
import SwiftData
import BlattaCore

/// Schedules full hibernation for inactive service web views.
@MainActor
final class HibernationScheduler {
    typealias IdleCandidate = (id: UUID, idle: TimeInterval)

    private let context: ModelContext
    private let webViewPool: WebViewPool
    private let sweepInterval: Duration
    private let immediateDelay: Duration
    private let now: @MainActor () -> Date
    private let idleCandidates: @MainActor (Date) -> [IdleCandidate]
    private let hibernate: @MainActor (UUID) async -> Bool

    private var globalEnabled = false
    private var globalIdleMinutes = 10
    private var isLocked: @MainActor () -> Bool = { true }
    private var idleSweepTask: Task<Void, Never>?
    private var pendingImmediateTasks: [UUID: Task<Void, Never>] = [:]
    private var hasStarted = false
    private var hasShutDown = false

    init(
        context: ModelContext,
        webViewPool: WebViewPool,
        sweepInterval: Duration = .seconds(60),
        immediateDelay: Duration = .seconds(HibernationResolver.immediateBackstopSeconds),
        now: @escaping @MainActor () -> Date = Date.init,
        idleCandidates: (@MainActor (Date) -> [IdleCandidate])? = nil,
        hibernate: (@MainActor (UUID) async -> Bool)? = nil
    ) {
        self.context = context
        self.webViewPool = webViewPool
        self.sweepInterval = sweepInterval
        self.immediateDelay = immediateDelay
        self.now = now
        self.idleCandidates = idleCandidates ?? { webViewPool.idleCandidates(now: $0) }
        self.hibernate = hibernate ?? { await webViewPool.hibernateIfStillIdle($0) }
    }

    /// Installs pool lifecycle callbacks and starts the idle sweep when needed.
    func start(
        globalEnabled: Bool,
        globalIdleMinutes: Int,
        isLocked: @escaping @MainActor () -> Bool,
        onServiceHibernated: @escaping @MainActor (UUID) -> Void = { _ in },
        onServiceSoftHibernated: @escaping @MainActor (UUID) -> Void = { _ in },
        onServiceRemoved: @escaping @MainActor (UUID) -> Void = { _ in }
    ) {
        guard !hasStarted, !hasShutDown else { return }
        hasStarted = true
        self.globalEnabled = globalEnabled
        self.globalIdleMinutes = globalIdleMinutes
        self.isLocked = isLocked

        webViewPool.isNotificationCritical = { [weak self] serviceID in
            self?.service(serviceID)?.isNotificationCritical ?? false
        }
        webViewPool.onServiceHibernated = { [weak self] serviceID in
            self?.cancelImmediateHibernation(serviceID)
            onServiceHibernated(serviceID)
        }
        webViewPool.onServiceWoke = { [weak self] serviceID in
            self?.cancelImmediateHibernation(serviceID)
        }
        webViewPool.onServiceSoftHibernated = { [weak self] serviceID in
            self?.scheduleImmediateHibernationIfNeeded(serviceID)
            onServiceSoftHibernated(serviceID)
        }
        webViewPool.onServiceSoftWoke = { [weak self] serviceID in
            self?.cancelImmediateHibernation(serviceID)
        }
        webViewPool.onServiceRemoved = { [weak self] serviceID in
            guard let self else { return }
            self.cancelImmediateHibernation(serviceID)
            self.refreshIdleSweepTask()
            onServiceRemoved(serviceID)
        }

        refreshIdleSweepTask()
    }

    /// Cancels every scheduler task and removes its pool callbacks.
    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        idleSweepTask?.cancel()
        idleSweepTask = nil
        for task in pendingImmediateTasks.values { task.cancel() }
        pendingImmediateTasks.removeAll()

        guard hasStarted else { return }
        webViewPool.isNotificationCritical = nil
        webViewPool.onServiceHibernated = nil
        webViewPool.onServiceWoke = nil
        webViewPool.onServiceSoftHibernated = nil
        webViewPool.onServiceSoftWoke = nil
        webViewPool.onServiceRemoved = nil
    }

    /// Applies the saved global policy and starts or stops the sweep.
    func configure(globalEnabled: Bool, globalIdleMinutes: Int) {
        guard !hasShutDown else { return }
        self.globalEnabled = globalEnabled
        self.globalIdleMinutes = globalIdleMinutes
        refreshIdleSweepTask()
    }

    /// Synchronizes pool exemptions and timers after a service policy edit.
    func servicePolicyDidChange(_ serviceID: UUID) {
        guard !hasShutDown else { return }
        let policy = service(serviceID)?.hibernationPolicyEffective
        webViewPool.setNeverHibernate(policy == .never, for: serviceID)
        cancelImmediateHibernation(serviceID)
        refreshIdleSweepTask()
    }

    /// Runs one pass. Tests call this directly; production calls it on a timer.
    func runIdleSweep() async {
        guard hasStarted, !hasShutDown, !isLocked() else { return }
        guard shouldRunIdleSweep else {
            idleSweepTask?.cancel()
            idleSweepTask = nil
            return
        }

        for candidate in idleCandidates(now()) {
            guard !isLocked() else { return }
            guard let service = service(candidate.id),
                  !service.isNotificationCritical,
                  let threshold = idleThreshold(for: service),
                  candidate.idle >= threshold
            else { continue }
            _ = await hibernate(candidate.id)
        }
    }

    /// Lets application tests await an injected immediate hibernation.
    func waitForImmediateHibernation(_ serviceID: UUID) async {
        await pendingImmediateTasks[serviceID]?.value
    }

    /// Whether a periodic sweep is currently scheduled.
    var isIdleSweepScheduled: Bool { idleSweepTask != nil }

    /// Whether a service has a pending immediate-hibernation grace task.
    func hasPendingImmediateHibernation(_ serviceID: UUID) -> Bool {
        pendingImmediateTasks[serviceID] != nil
    }

    private var shouldRunIdleSweep: Bool {
        globalEnabled || hasExplicitHibernationPolicy()
    }

    private func refreshIdleSweepTask() {
        idleSweepTask?.cancel()
        idleSweepTask = nil
        guard hasStarted, !hasShutDown, shouldRunIdleSweep else { return }

        idleSweepTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    try await Task.sleep(for: self.sweepInterval)
                } catch {
                    return
                }
                await self.runIdleSweep()
            }
        }
    }

    private func scheduleImmediateHibernationIfNeeded(_ serviceID: UUID) {
        guard let service = service(serviceID),
              service.hibernationPolicyEffective == .immediate,
              !service.isNotificationCritical else { return }

        cancelImmediateHibernation(serviceID)
        pendingImmediateTasks[serviceID] = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: self.immediateDelay)
            } catch {
                return
            }
            guard !Task.isCancelled, !self.hasShutDown else { return }
            if !self.isLocked() {
                _ = await self.hibernate(serviceID)
            }
            guard !Task.isCancelled else { return }
            self.pendingImmediateTasks[serviceID] = nil
        }
    }

    private func cancelImmediateHibernation(_ serviceID: UUID) {
        pendingImmediateTasks[serviceID]?.cancel()
        pendingImmediateTasks[serviceID] = nil
    }

    private func hasExplicitHibernationPolicy() -> Bool {
        let services = (try? context.fetch(FetchDescriptor<ServiceInstance>())) ?? []
        return services.contains {
            switch $0.hibernationPolicyEffective {
            case .after, .immediate: true
            case .followGlobal, .never: false
            }
        }
    }

    private func idleThreshold(for service: ServiceInstance) -> TimeInterval? {
        HibernationResolver.idleThreshold(
            policy: service.hibernationPolicyEffective,
            globalEnabled: globalEnabled,
            globalIdleMinutes: globalIdleMinutes,
            afterMinutes: service.hibernateAfterMinutesEffective
        )
    }

    private func service(_ serviceID: UUID) -> ServiceInstance? {
        var descriptor = FetchDescriptor<ServiceInstance>(
            predicate: #Predicate { $0.id == serviceID }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
