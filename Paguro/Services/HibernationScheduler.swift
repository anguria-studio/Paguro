import Foundation
import SwiftData
import PaguroCore

/// Schedules full hibernation for inactive service web views.
///
/// It also owns the capacity notice. The scheduler already installs the pool
/// lifecycle callbacks and already reads a service record, so it can name the
/// released service without a new dependency. A view reads the notice through
/// `AppState`, which keeps the direction view -> application state ->
/// controller -> pool.
@MainActor
@Observable
final class HibernationScheduler {
    typealias IdleCandidate = (id: UUID, idle: TimeInterval)

    /// How long the capacity notice stays on screen. It matches the other
    /// timed notices in the window.
    private static let capacityNoticeSeconds = 12

    private let context: ModelContext
    private let webViewPool: WebViewPool
    private let sweepInterval: Duration
    private let immediateDelay: Duration
    private let now: @MainActor () -> Date
    private let idleCandidates: @MainActor (Date) -> [IdleCandidate]
    private let hibernate: @MainActor (UUID) async -> Bool

    @ObservationIgnored private var globalEnabled = false
    @ObservationIgnored private var globalIdleMinutes = 10
    @ObservationIgnored private var isLocked: @MainActor () -> Bool = { true }
    @ObservationIgnored private var idleSweepTask: Task<Void, Never>?
    @ObservationIgnored private var pendingImmediateTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var hasShutDown = false
    @ObservationIgnored private var hasAnnouncedCapacityEviction = false
    @ObservationIgnored private var capacityNoticeTask: Task<Void, Never>?

    /// The current capacity-eviction explanation, or nil when there is none.
    private(set) var capacityEvictionNotice: String?

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
        webViewPool.onServiceEvictedForCapacity = { [weak self] serviceID in
            self?.announceCapacityEviction(serviceID)
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
        capacityNoticeTask?.cancel()
        capacityNoticeTask = nil
        capacityEvictionNotice = nil

        guard hasStarted else { return }
        webViewPool.isNotificationCritical = nil
        webViewPool.onServiceHibernated = nil
        webViewPool.onServiceEvictedForCapacity = nil
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
        let edited = service(serviceID)
        webViewPool.setNeverHibernate(edited?.hibernationPolicyEffective == .never, for: serviceID)
        webViewPool.setNotificationCritical(edited?.isNotificationCritical ?? false, for: serviceID)
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

    /// Removes the capacity notice after the user reads it.
    func dismissCapacityEvictionNotice() {
        capacityNoticeTask?.cancel()
        capacityNoticeTask = nil
        capacityEvictionNotice = nil
    }

    /// Explains the first capacity eviction of this app run.
    ///
    /// The pool releases the service because of its size limit, not because the
    /// user turned idle hibernation on. Without this notice the service looks
    /// broken. Later evictions repeat the same rule, so they stay silent.
    private func announceCapacityEviction(_ serviceID: UUID) {
        guard !hasShutDown,
              CapacityEvictionNotice.shouldAnnounce(
                  hasAnnouncedThisRun: hasAnnouncedCapacityEviction
              )
        else { return }
        hasAnnouncedCapacityEviction = true

        let message = CapacityEvictionNotice.message(
            serviceName: service(serviceID)?.label ?? ""
        )
        capacityEvictionNotice = message
        capacityNoticeTask?.cancel()
        capacityNoticeTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(Self.capacityNoticeSeconds))
            } catch {
                return
            }
            guard self?.capacityEvictionNotice == message else { return }
            self?.capacityEvictionNotice = nil
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
