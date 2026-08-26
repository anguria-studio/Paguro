import Foundation
import SwiftData
import AtollCore

/// How the application obtained its model container at launch.
/// `AppState` uses this value to select the recovery banner.
enum StoreLoadOutcome: Equatable {
    /// The on-disk store opened normally. No banner is required.
    case openedClean
    /// The store was unusable, so Atoll restored a pre-migration snapshot.
    case restoredFromSnapshot(version: String?, takenAt: Date?)
    /// The store was unusable, so Atoll is using temporary storage.
    case inMemoryFallback(reason: String)
}

/// Opens the SwiftData store and applies the launch recovery policy.
@MainActor
enum StoreLoader {
    /// Records whether this installation has held user data. This lets the loader
    /// distinguish a fresh installation from a store that migrated to empty.
    static let hasEverHadDataKey = "atoll.hasEverHadData"

    /// Result of one open attempt. An unusable container does not escape this
    /// scope, so SwiftData releases its SQLite connection before a restore.
    private enum TryOpenResult {
        case usable(ModelContainer)
        case emptiedWithHistory
        case failed
    }

    /// Opens the persistent store. If it is unusable, the loader restores the
    /// newest usable snapshot and retries once. It preserves every store and
    /// snapshot when recovery fails, then uses an in-memory container.
    static func load(
        schema: Schema,
        config: ModelConfiguration,
        defaults: UserDefaults = .standard
    ) -> (ModelContainer, StoreLoadOutcome) {
        // File existence and record count describe different cases. A missing
        // file can be a fresh installation. An existing empty file can be loss.
        let fileExisted = FileManager.default.fileExists(atPath: config.url.path)
        let before = StoreRepair.spaceCount(at: config.url)
        let hadHistory = (before ?? 0) > 0 || defaults.bool(forKey: hasEverHadDataKey)
        if (before ?? 0) > 0 { recordHasData(defaults) }

        let kind: StoreUnusableKind
        switch tryOpen(schema: schema, config: config, hadHistory: hadHistory) {
        case .usable(let opened):
            if ((try? opened.mainContext.fetchCount(FetchDescriptor<Space>())) ?? 0) > 0 {
                recordHasData(defaults)
            }
            return (opened, .openedClean)
        case .emptiedWithHistory:
            kind = .emptiedWithHistory
        case .failed:
            kind = .openFailed
        }

        let plan = StoreRecoveryPolicy.recoveryPlan(
            kind: kind,
            before: before,
            fileExisted: fileExisted
        )
        // A usable backup must remain protected even when its restore fails.
        // Check for it before the restore and branch on its existence.
        let candidate = plan.attemptRestore ? StoreRepair.newestRestorableSnapshot(for: config.url) : nil
        AppLogger.dataStore.error("Store unusable on open (kind=\(String(describing: kind)), before=\(before.map(String.init) ?? "nil"), fileExisted=\(fileExisted)); attemptRestore=\(plan.attemptRestore), haveBackup=\(candidate != nil)")

        if let candidate {
            if StoreRepair.restoreFromSnapshot(candidate, to: config.url),
               case .usable(let reopened) = tryOpen(schema: schema, config: config, hadHistory: true) {
                recordHasData(defaults)
                AppLogger.dataStore.info("Automatic restore succeeded from backup \(candidate.version ?? "?")")
                return (reopened, .restoredFromSnapshot(version: candidate.version, takenAt: candidate.takenAt))
            }
            AppLogger.dataStore.error("Restore did not take though a usable backup exists; preserving it and running in-memory")
            return (inMemoryContainer(schema: schema), .inMemoryFallback(reason: "restore failed; usable backup preserved"))
        }

        switch plan.ifNoRestore {
        case .freshStart:
            // It is safe to clear a stale history flag only when no store file or
            // usable backup exists.
            defaults.set(false, forKey: hasEverHadDataKey)
            if case .usable(let fresh) = tryOpen(schema: schema, config: config, hadHistory: false) {
                AppLogger.dataStore.info("No file and nothing to restore; starting fresh")
                return (fresh, .openedClean)
            }
            AppLogger.dataStore.error("Fresh open failed; falling back to in-memory storage")
            return (inMemoryContainer(schema: schema), .inMemoryFallback(reason: "fresh open failed"))
        case .preserveInMemory:
            AppLogger.dataStore.error("No restore performed; running in-memory. On-disk store and snapshots preserved for manual recovery")
            return (inMemoryContainer(schema: schema), .inMemoryFallback(reason: "store unusable; on-disk data and snapshots preserved"))
        }
    }

    /// Opens the store once and classifies the result. Raw-file repair runs
    /// before SwiftData opens the store. An unusable container stays in the
    /// autorelease pool so its SQLite connection closes before file restoration.
    private static func tryOpen(
        schema: Schema,
        config: ModelConfiguration,
        hadHistory: Bool
    ) -> TryOpenResult {
        StoreRepair.repairDanglingLinks(at: config.url)
        return autoreleasepool {
            let opened: ModelContainer
            do {
                opened = try ModelContainer(
                    for: schema,
                    migrationPlan: AtollMigrationPlan.self,
                    configurations: [config]
                )
            } catch {
                // Inferred migration is the compatibility fallback for stores
                // that the explicit versioned plan cannot open.
                AppLogger.dataStore.error("Versioned-plan open failed (\(error.localizedDescription)); retrying with inferred migration")
                do {
                    opened = try ModelContainer(for: schema, configurations: [config])
                } catch {
                    AppLogger.dataStore.error("Inferred-migration open also failed: \(error.localizedDescription)")
                    return .failed
                }
            }
            if storeHasDanglingLinks(opened) { return .failed }
            let spaces = (try? opened.mainContext.fetchCount(FetchDescriptor<Space>())) ?? 0
            if spaces == 0 && hadHistory { return .emptiedWithHistory }
            return .usable(opened)
        }
    }

    /// Returns an in-memory container when the persistent store is unsafe.
    /// A failure here means that the schema itself cannot open.
    private static func inMemoryContainer(schema: Schema) -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            AppLogger.dataStore.fault("In-memory model container failed: \(error.localizedDescription)")
            fatalError("Failed to initialize any model container: \(error.localizedDescription)")
        }
    }

    /// Returns true when a link is not reachable from both of its owners.
    /// The check reads relationship arrays only from live spaces and services.
    static func storeHasDanglingLinks(_ container: ModelContainer) -> Bool {
        let context = container.mainContext
        let links: [SpaceServiceLink]
        let spaces: [Space]
        let services: [ServiceInstance]
        do {
            links = try context.fetch(FetchDescriptor<SpaceServiceLink>())
            guard !links.isEmpty else { return false }
            spaces = try context.fetch(FetchDescriptor<Space>())
            services = try context.fetch(FetchDescriptor<ServiceInstance>())
        } catch {
            // An unverifiable store is unsafe. Fail closed so the caller uses the
            // in-memory fallback instead of faulting a deleted model later.
            AppLogger.dataStore.error("Dangling-link check failed; treating store as unsafe: \(error.localizedDescription)")
            return true
        }

        var reachableFromSpace: Set<UUID> = []
        for space in spaces {
            for link in space.serviceLinks { reachableFromSpace.insert(link.id) }
        }
        var reachableFromService: Set<UUID> = []
        for service in services {
            for link in service.spaceLinks { reachableFromService.insert(link.id) }
        }
        return links.contains {
            !reachableFromSpace.contains($0.id) || !reachableFromService.contains($0.id)
        }
    }

    /// Records that the current installation holds user data.
    static func recordHasData(_ defaults: UserDefaults = .standard) {
        if !defaults.bool(forKey: hasEverHadDataKey) {
            defaults.set(true, forKey: hasEverHadDataKey)
        }
    }
}
