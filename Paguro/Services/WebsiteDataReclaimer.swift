import Foundation
import SwiftData
import WebKit
import PaguroCore

/// Reclaims persistent WebKit stores after their service rows are committed away.
@MainActor
final class WebsiteDataReclaimer {
    private let context: ModelContext
    private let dataStoreManager: DataStoreManager
    private let isSafeToReclaim: Bool
    private let bundleID: String?
    private let defaults: UserDefaults
    private let backoff: [Duration]
    private let removeDataStore: @MainActor (UUID) async throws -> Void
    private var removalTasks: [UUID: Task<Void, Never>] = [:]
    private var hasShutDown = false

    init(
        context: ModelContext,
        dataStoreManager: DataStoreManager,
        isSafeToReclaim: Bool,
        bundleID: String? = Bundle.main.bundleIdentifier,
        defaults: UserDefaults = .standard,
        backoff: [Duration] = [.seconds(2), .seconds(3), .seconds(5)],
        removeDataStore: @escaping @MainActor (UUID) async throws -> Void = {
            try await WKWebsiteDataStore.remove(forIdentifier: $0)
        }
    ) {
        self.context = context
        self.dataStoreManager = dataStoreManager
        self.isSafeToReclaim = isSafeToReclaim
        self.bundleID = bundleID
        self.defaults = defaults
        self.backoff = backoff
        self.removeDataStore = removeDataStore
    }

    /// Cancels delayed removal work. Durable tombstones remain for the next launch.
    func shutdown() {
        guard !hasShutDown else { return }
        hasShutDown = true
        for task in removalTasks.values { task.cancel() }
        removalTasks.removeAll()
    }

    /// Marks a data store for delayed removal.
    func markOrphaned(_ identifier: UUID) {
        guard !hasShutDown else { return }
        var identifiers = loadOrphanedIdentifiers()
        identifiers.insert(identifier)
        saveOrphanedIdentifiers(identifiers)
    }

    /// Reconciles durable tombstones and starts one removal task per store.
    func cleanUpOrphanedDataStores() {
        guard !hasShutDown else { return }
        let reconciled = WebsiteDataReclamationPolicy.reconcile(
            tombstoned: loadOrphanedIdentifiers(),
            claimed: liveDataStoreIdentifiers()
        )
        if !reconciled.dropped.isEmpty {
            AppLogger.dataStore.info(
                "Dropping \(reconciled.dropped.count) tombstone(s) for data store(s) a live service still claims"
            )
            saveOrphanedIdentifiers(reconciled.keep)
        }

        let pending = reconciled.keep.subtracting(removalTasks.keys)
        for identifier in pending {
            dataStoreManager.evict(identifier: identifier)
            removalTasks[identifier] = Task { @MainActor [weak self] in
                await self?.removeWithBackoff(identifier)
            }
        }
    }

    /// Deletes unlinked service rows only on a launch known to represent the
    /// user's healthy store. Data-store removal starts after the save succeeds.
    func reapOrphanedServices() {
        guard isSafeToReclaim else {
            AppLogger.dataStore.info(
                "Skipping the orphan reap: the store was damaged, restored, or is the in-memory fallback"
            )
            return
        }

        let services: [ServiceInstance]
        let links: [SpaceServiceLink]
        do {
            services = try context.fetch(FetchDescriptor<ServiceInstance>())
            links = try context.fetch(FetchDescriptor<SpaceServiceLink>())
        } catch {
            AppLogger.dataStore.error(
                "Failed to fetch services for orphan reaping: \(error.localizedDescription)"
            )
            return
        }

        // Both ends have to resolve before the service counts as linked: a
        // link that outlived either end still holds a freed model.
        let linkedServiceIDs = Set(links.compactMap { $0.liveEnds?.service.id })
        let orphans = services.filter { !linkedServiceIDs.contains($0.id) }
        guard !orphans.isEmpty else { return }

        let orphanedIDs = orphans.map(\.dataStoreIdentifier)
        for service in orphans { context.delete(service) }
        guard context.saveOrRollback(reason: "reap orphaned services") else { return }

        AppLogger.dataStore.info("Reaped \(orphans.count) orphaned service(s) at launch")
        for identifier in orphanedIDs { markOrphaned(identifier) }
        cleanUpOrphanedDataStores()
    }

    /// Tombstones identifier-scoped stores that no service row claims.
    func reclaimUnreferencedDataStores() {
        guard isSafeToReclaim else { return }
        guard let directory = Self.websiteDataStoreDirectory(bundleID: bundleID),
              let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else { return }

        let onDisk = Set(names.compactMap(UUID.init(uuidString:)))
        let unreferenced = WebsiteDataReclamationPolicy.unreferenced(
            onDisk: onDisk,
            claimed: liveDataStoreIdentifiers()
        )
        guard !unreferenced.isEmpty else { return }

        AppLogger.dataStore.info(
            "Reclaiming \(unreferenced.count) website data store(s) no service points at"
        )
        for identifier in unreferenced { markOrphaned(identifier) }
    }

    /// Allows application tests to wait for injected removal work.
    func waitForPendingRemovals() async {
        let tasks = Array(removalTasks.values)
        for task in tasks { await task.value }
    }

    /// Returns the identifier-scoped WebKit directory for one application.
    nonisolated static func websiteDataStoreDirectory(bundleID: String?) -> URL? {
        guard let bundleID, !bundleID.isEmpty else { return nil }
        return URL.libraryDirectory
            .appending(path: "WebKit")
            .appending(path: bundleID)
            .appending(path: "WebsiteDataStore")
    }

    private func removeWithBackoff(_ identifier: UUID) async {
        defer { removalTasks.removeValue(forKey: identifier) }

        for delay in backoff {
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard !Task.isCancelled, !hasShutDown else { return }

            do {
                try await removeDataStore(identifier)
                var current = loadOrphanedIdentifiers()
                current.remove(identifier)
                saveOrphanedIdentifiers(current)
                AppLogger.dataStore.info("Removed orphaned data store \(identifier)")
                return
            } catch {
                AppLogger.dataStore.warning(
                    "Data store \(identifier) not yet removable, will retry: \(error.localizedDescription)"
                )
            }
        }
    }

    /// Empty means either no services or a failed fetch. Both cases must block
    /// automatic filesystem enumeration from treating every store as garbage.
    private func liveDataStoreIdentifiers() -> Set<UUID> {
        let services = (try? context.fetch(FetchDescriptor<ServiceInstance>())) ?? []
        return Set(services.map(\.dataStoreIdentifier))
    }

    private func loadOrphanedIdentifiers() -> Set<UUID> {
        guard let raw = defaults.array(forKey: DefaultsKey.orphanedDataStoreIdentifiers) as? [String] else {
            return []
        }
        return Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func saveOrphanedIdentifiers(_ identifiers: Set<UUID>) {
        if identifiers.isEmpty {
            defaults.removeObject(forKey: DefaultsKey.orphanedDataStoreIdentifiers)
        } else {
            defaults.set(
                identifiers.map(\.uuidString).sorted(),
                forKey: DefaultsKey.orphanedDataStoreIdentifiers
            )
        }
    }
}
