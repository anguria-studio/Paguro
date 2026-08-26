import XCTest
import Foundation
import SwiftData
import AtollCore
@testable import Atoll

@MainActor
final class StoreIntegrityTests: XCTestCase {
    // MARK: - Store integrity after deleting a space (repro: "delete second workspace and quit, won't start")

    /// Reproduces the reported sequence against a real on-disk store: seed two
    /// spaces with linked services, delete the second (reclaiming its orphaned
    /// services exactly as `AppState.deleteSpace` does at the SwiftData layer),
    /// close the container, then reopen it and run the launch-time queries.
    /// A dangling `SpaceServiceLink` or corrupt store would trap here.
    func testDeleteSecondSpaceThenReopenStoreIsClean() throws {
        let schema = Self.storeSchema
        let sandbox = try StoreSandbox(testCase: self, label: "delete-reopen")
        let storeURL = sandbox.storeURL

        // --- Session 1: seed two spaces, then delete the second ---
        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext

            let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
            let work = Space(name: "Work", emoji: "💼", sortOrder: 1)
            context.insert(personal)
            context.insert(work)

            func link(_ label: String, to space: Space, order: Int) {
                let svc = ServiceInstance(label: label, url: "https://\(label).example", catalogEntryID: label)
                context.insert(svc)
                context.insert(SpaceServiceLink(sortOrder: order, space: space, service: svc))
            }
            link("gmail-personal", to: personal, order: 0)
            link("claude", to: personal, order: 1)
            link("gmail-work", to: work, order: 0)
            link("slack", to: work, order: 1)
            try context.save()

            // Replicate AppState.deleteSpace's SwiftData operations for `work`.
            let workID = work.id
            let doomed = try context.fetch(
                FetchDescriptor<Space>(predicate: #Predicate { $0.id == workID })
            ).first!
            let linkedServices = doomed.serviceLinks.map(\.service)
            var memberships: [UUID: Set<UUID>] = [:]
            for service in linkedServices {
                memberships[service.id] = Set(service.spaceLinks.map { $0.space.id })
            }
            // The inverse must be wired for this to be non-empty — the bug was
            // that it read 0, so nothing was reclaimed and the space's links
            // were left dangling after the space was deleted.
            XCTAssertEqual(doomed.serviceLinks.count, 2, "Space.serviceLinks inverse must be populated")
            let orphaned = WorkspaceDeletionPolicy.servicesOrphaned(
                byDeletingSpace: workID,
                memberships: memberships
            )
            XCTAssertEqual(orphaned.count, 2, "Both of Work's services should be reclaimed")
            for service in linkedServices where orphaned.contains(service.id) {
                context.delete(service)
            }
            context.delete(doomed)
            try context.save()
        }

        // --- Session 2: reopen the SAME store and run launch-time queries ---
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        // WebsiteDataReclaimer must find no service without a live link.
        let services = try context.fetch(FetchDescriptor<ServiceInstance>())
        XCTAssertEqual(services.count, 2, "Only Personal's two services should remain")
        let orphans = services.filter { $0.spaceLinks.isEmpty }
        XCTAssertTrue(orphans.isEmpty, "No orphaned services should survive the delete")

        // servicesForSpace guard path: materialize each link's relationships.
        let links = try context.fetch(FetchDescriptor<SpaceServiceLink>())
        XCTAssertEqual(links.count, 2, "Only Personal's two links should remain")
        for l in links {
            XCTAssertNotNil(l.modelContext)
            XCTAssertNotNil(l.space.modelContext, "Link's space must not dangle")
            XCTAssertNotNil(l.service.modelContext, "Link's service must not dangle")
        }

        let spaces = try context.fetch(FetchDescriptor<Space>())
        XCTAssertEqual(spaces.count, 1)
        XCTAssertEqual(spaces.first?.name, "Personal")
    }

    // MARK: - Repair of a store ALREADY corrupted by a pre-1.5.1 build

    /// The 1.5.1 fix has two halves: the inverse declaration (prevents NEW
    /// corruption — covered by the test above) and `reapDanglingLinks` (repairs
    /// a store a pre-fix build already corrupted). The reporter is in the second
    /// case: they deleted a space on 1.4.0/1.5.0, so their store holds a
    /// `SpaceServiceLink` whose `space` points at a deleted row. This test
    /// reproduces exactly that on-disk state — by deleting the space's row
    /// directly, the way the pre-fix build effectively did when its cascade
    /// never fired — then runs the shipped repair sequence and the launch badge
    /// read that used to trap. If deleting a dangling link faults its dead space,
    /// or the read still traps, this test crashes (SIGTRAP), matching the report.
    func testReapRepairsPreFixDanglingLinkWithoutCrashing() throws {
        let schema = Self.storeSchema
        let sandbox = try StoreSandbox(testCase: self, label: "dangling-repair")
        let dir = sandbox.directoryURL
        let storeURL = sandbox.storeURL

        // --- Session 1: seed two spaces with linked services, clean ---
        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 0)
            let work = Space(name: "Work", emoji: "💼", sortOrder: 1)
            context.insert(personal)
            context.insert(work)
            func link(_ label: String, to space: Space, order: Int) {
                let svc = ServiceInstance(label: label, url: "https://\(label).example", catalogEntryID: label)
                context.insert(svc)
                context.insert(SpaceServiceLink(sortOrder: order, space: space, service: svc))
            }
            link("gmail-personal", to: personal, order: 0)
            link("claude", to: personal, order: 1)
            link("gmail-work", to: work, order: 0)
            link("slack", to: work, order: 1)
            try context.save()
        }

        // --- Corrupt like a pre-fix build: delete the Work space ROW,
        //     leaving its two links with a dangling ZSPACE foreign key. ---
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE WHERE ZNAME='Work';")
        func danglingRows() throws -> Int {
            Int(try SQLiteHelpers.run(
                storeURL,
                "SELECT count(*) FROM ZSPACESERVICELINK WHERE ZSPACE NOT IN (SELECT Z_PK FROM ZSPACE);"
            ).trimmingCharacters(in: .whitespacesAndNewlines)) ?? -1
        }
        XCTAssertEqual(try danglingRows(), 2, "repro must leave two dangling links")

        // --- Run the SHIPPED pre-open repair against the raw file. ---
        StoreRepair.repairDanglingLinks(at: storeURL)
        XCTAssertEqual(try danglingRows(), 0, "repair must remove the dangling links")

        // Idempotency: a second pass is a no-op.
        StoreRepair.repairDanglingLinks(at: storeURL)
        XCTAssertEqual(try danglingRows(), 0, "second repair pass must stay clean")

        // A backup of the corrupted store must have been written.
        let backups = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.contains(".corrupt-") }
        XCTAssertFalse(backups.isEmpty, "repair must back up the store before mutating")

        // --- Session 2: open the repaired store and run the launch queries
        //     that used to trap, then confirm good data survived. ---
        let config = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext

        let links = try context.fetch(FetchDescriptor<SpaceServiceLink>())
        XCTAssertEqual(links.count, 2, "only Personal's two links should survive")
        for l in links {
            _ = l.space.id     // the badge-sweep read that crashed pre-fix
            _ = l.service.id
        }
        let spaces = try context.fetch(FetchDescriptor<Space>())
        XCTAssertEqual(spaces.map(\.name), ["Personal"], "the live space must be intact")
        let services = try context.fetch(FetchDescriptor<ServiceInstance>())
        XCTAssertEqual(services.count, 4, "no service rows should be lost by the repair")

        // The store must remain writable (bookkeeping/history survived): create
        // and remove a link, then save with no error.
        let probeSpace = spaces[0]
        let probeSvc = ServiceInstance(label: "probe", url: "https://probe.example", catalogEntryID: "probe")
        context.insert(probeSvc)
        let probeLink = SpaceServiceLink(sortOrder: 9, space: probeSpace, service: probeSvc)
        context.insert(probeLink)
        try context.save()
        context.delete(probeLink)
        context.delete(probeSvc)
        try context.save()
    }

    /// The launch gate's detector must flag a store that still holds a dangling
    /// link (true) and clear a repaired one (false). This is what makes `init`
    /// fall back to in-memory instead of running on a store that would trap on a
    /// later `.space`/`.service` read.
    func testStoreHasDanglingLinksDetectsAndClears() throws {
        let schema = Self.storeSchema
        let sandbox = try StoreSandbox(testCase: self, label: "dangling-gate")
        let storeURL = sandbox.storeURL

        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            let work = Space(name: "Work", emoji: "💼", sortOrder: 0)
            let personal = Space(name: "Personal", emoji: "🏠", sortOrder: 1)
            context.insert(work)
            context.insert(personal)
            let svc = ServiceInstance(label: "slack", url: "https://slack.example", catalogEntryID: "slack")
            context.insert(svc)
            context.insert(SpaceServiceLink(sortOrder: 0, space: work, service: svc))
            let keep = ServiceInstance(label: "gmail", url: "https://gmail.example", catalogEntryID: "gmail")
            context.insert(keep)
            context.insert(SpaceServiceLink(sortOrder: 0, space: personal, service: keep))
            try context.save()
        }

        // Corrupt: delete Work's row, leaving its link dangling.
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE WHERE ZNAME='Work';")

        // Detector must flag the corrupted store.
        let corruptConfig = ModelConfiguration(schema: schema, url: storeURL)
        let corrupt = try ModelContainer(for: schema, configurations: [corruptConfig])
        XCTAssertTrue(StoreLoader.storeHasDanglingLinks(corrupt), "must detect the dangling link")

        // After repair, the same detector must pass the store.
        StoreRepair.repairDanglingLinks(at: storeURL)
        let repairedConfig = ModelConfiguration(schema: schema, url: storeURL)
        let repaired = try ModelContainer(for: schema, configurations: [repairedConfig])
        XCTAssertFalse(StoreLoader.storeHasDanglingLinks(repaired), "repaired store must be clean")
    }

    /// `StoreRepair.spaceCount` is what lets `init` tell a fresh install from a
    /// store that had spaces but came up empty (a silent migration failure).
    /// It must return nil when there's no file, nil when the schema has no
    /// ZSPACE table, and the exact row count otherwise — so a genuine empty
    /// store reads as 0, never nil, and a populated one reads as its count.
    func testSpaceCountDistinguishesMissingUnknownAndPopulated() throws {
        let schema = Self.storeSchema
        let sandbox = try StoreSandbox(testCase: self, label: "space-count")
        let dir = sandbox.directoryURL
        let storeURL = sandbox.storeURL

        // No file yet → unknown, not zero.
        XCTAssertNil(StoreRepair.spaceCount(at: storeURL), "missing store must read as nil (unknown)")

        // A store with two spaces → exact count.
        do {
            let config = ModelConfiguration(schema: schema, url: storeURL)
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext
            context.insert(Space(name: "Personal", emoji: "🏠", sortOrder: 0))
            context.insert(Space(name: "Work", emoji: "💼", sortOrder: 1))
            try context.save()
        }
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 2, "populated store must read its space count")

        // Emptied on disk → 0, NOT nil: the table still exists, so the count is
        // known to be zero. This is the case that must NOT look like a fresh
        // install to init (nil), or the seed would overwrite the store.
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 0, "emptied store must read as 0, not nil")

        // A file with no ZSPACE table → unknown (nil), never guessed as zero.
        let alienURL = dir.appendingPathComponent("alien.sqlite")
        try SQLiteHelpers.run(alienURL, "CREATE TABLE ZOTHER (x INTEGER);")
        XCTAssertNil(StoreRepair.spaceCount(at: alienURL), "unrecognized schema must read as nil")
    }

    // MARK: - Auto-restore of an emptied store

    /// The store schema, shared by the restore tests. Uses the versioned current
    /// schema so it matches `AtollMigrationPlan`'s latest, the same shape
    /// `StoreLoader` opens in production.
    static var storeSchema: Schema {
        ModelFixtures.storeSchema
    }

    /// `newestRestorableSnapshot` must skip empty and corrupt snapshots and
    /// return the newest one that actually holds data.
    func testNewestRestorableSnapshotSkipsEmptyAndCorruptPicksNewestGood() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-newest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Good store → snapshot it as the OLDEST.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")

        // Empty the store → snapshot it as a NEWER but empty snapshot.
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        StoreRepair.snapshot(at: storeURL, stamp: "1700000500-1.1.0")

        // A NEWEST but corrupt snapshot file (not a database).
        let corrupt = dir.appendingPathComponent("store.sqlite.snapshot-1700000999-1.2.0.bak")
        try "not a database".write(to: corrupt, atomically: true, encoding: .utf8)

        let candidate = StoreRepair.newestRestorableSnapshot(for: storeURL)
        XCTAssertEqual(candidate?.version, "1.0.0", "must skip the newer empty and corrupt snapshots for the good one")
        XCTAssertEqual(candidate?.takenAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    /// End-to-end proof that the shipped recovery path sees a snapshot whose
    /// `-wal` sibling is gone — exactly what `StoreRepair.snapshot` produces
    /// after a clean checkpoint, since it only copies the suffixes that exist
    /// at backup time. Before the WAL-header/no-`-wal` fallback in
    /// `StoreInventory.openReadOnly`, this snapshot would have been
    /// misjudged unusable (via either `spaceCount`'s gate or
    /// `snapshotHasUsableData`'s own integrity-check open) and skipped.
    /// Regression guard for the production bug behind this task: it fails if
    /// any of the three readers that share the opener loses the fallback.
    func testNewestRestorableSnapshotFindsAMainFileOnlySnapshot() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-newest-walonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")

        // Strip the snapshot's own `-wal`/`-shm` siblings, regardless of
        // whether `StoreRepair.snapshot` copied them, so the fixture is
        // exactly the main-file-only WAL-mode shape this bug needs.
        let snapshotURL = dir.appendingPathComponent("store.sqlite.snapshot-1700000000-1.0.0.bak")
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: snapshotURL.path + suffix))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: snapshotURL.path + "-wal"),
            "precondition: the snapshot has no -wal sibling"
        )

        let candidate = StoreRepair.newestRestorableSnapshot(for: storeURL)
        XCTAssertEqual(
            candidate?.version, "1.0.0",
            "a main-file-only WAL-mode snapshot must be found, not skipped as unusable"
        )
    }

    /// `restoreFromSnapshot` must copy the snapshot's data back and keep exactly
    /// one prerestore backup of the bad store across repeated calls.
    func testRestoreFromSnapshotBacksUpOnceAndCopiesData() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 0, "precondition: store emptied")

        let candidate = try XCTUnwrap(StoreRepair.newestRestorableSnapshot(for: storeURL))
        XCTAssertTrue(StoreRepair.restoreFromSnapshot(candidate, to: storeURL))
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 3, "restore must bring the data back")

        func prerestoreStamps() throws -> Set<String> {
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.contains(".prerestore-") }
            // Collapse the triple (…, -wal, -shm) to distinct stamps.
            return Set(names.map { $0.replacingOccurrences(of: "-wal", with: "").replacingOccurrences(of: "-shm", with: "") })
        }
        let after1 = try prerestoreStamps()
        XCTAssertEqual(after1.count, 1, "exactly one prerestore backup after first restore")

        // Second restore must NOT stack another backup.
        _ = StoreRepair.restoreFromSnapshot(candidate, to: storeURL)
        XCTAssertEqual(try prerestoreStamps(), after1, "second restore must not add another prerestore backup")
    }

    /// End-to-end: a store that had data but comes up empty, with a good snapshot
    /// present, must auto-restore — the exact recovery the field bug needed.
    func testLoadContainerRestoresEmptiedStoreWithHistory() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-load-restore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 4)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        defaults.set(true, forKey: StoreLoader.hasEverHadDataKey)   // user has had data

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        guard case .restoredFromSnapshot = outcome else {
            return XCTFail("expected .restoredFromSnapshot, got \(outcome)")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Space>()), 4, "restored store must hold the snapshot's spaces")
    }

    /// A genuine fresh install (no file, no history) opens clean and does NOT
    /// restore or record data yet.
    func testLoadContainerFreshInstallOpensCleanWithoutRestore() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-load-fresh-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        XCTAssertEqual(outcome, .openedClean)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Space>()), 0)
        XCTAssertFalse(defaults.bool(forKey: StoreLoader.hasEverHadDataKey), "an empty fresh install hasn't recorded data yet")
    }

    /// Emptied store + history but NO usable snapshot → in-memory fallback, and
    /// the on-disk store is left untouched (not seeded, not deleted).
    func testLoadContainerFallsBackToInMemoryWhenNoSnapshot() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-load-fallback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")   // emptied, but no snapshot taken
        defaults.set(true, forKey: StoreLoader.hasEverHadDataKey)

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (_, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        guard case .inMemoryFallback = outcome else {
            return XCTFail("expected .inMemoryFallback, got \(outcome)")
        }
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 0, "on-disk store must be left untouched (not seeded)")
    }

    /// Opening a store that already holds data must record `hasEverHadData`, so
    /// an existing user is protected from a future empty-store reseed.
    func testLoadContainerWithExistingDataRecordsHasEverHadData() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-existing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        XCTAssertFalse(defaults.bool(forKey: StoreLoader.hasEverHadDataKey), "precondition: flag not yet set")

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        XCTAssertEqual(outcome, .openedClean)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Space>()), 2)
        XCTAssertTrue(defaults.bool(forKey: StoreLoader.hasEverHadDataKey), "opening a populated store must record that data exists")
    }

    /// When no store file exists but a usable backup does, Atoll must RESTORE
    /// the backup — never clear the durable flag and reseed over it. Guards the
    /// regression where `freshStart` could abandon a recoverable snapshot.
    func testLoadContainerNoFileButUsableSnapshotRestoresNotReseeds() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-nofile-snap-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // Build a usable snapshot, then remove the store file entirely so only the
        // backup remains (a store-deleted-but-snapshots-kept situation).
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        defaults.set(true, forKey: StoreLoader.hasEverHadDataKey)   // stale flag, no file

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        guard case .restoredFromSnapshot = outcome else {
            return XCTFail("a usable backup must be restored, not reseeded; got \(outcome)")
        }
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Space>()), 3)
        XCTAssertTrue(defaults.bool(forKey: StoreLoader.hasEverHadDataKey), "the flag must NOT be cleared when a backup was restored")
    }

    /// Prune must never delete the newest USABLE snapshot, even when a run of
    /// newer empty snapshots pushes it past the keep window — otherwise the only
    /// copy of real data is destroyed after a few post-loss version bumps.
    func testPruneRetainsNewestUsableSnapshotBeyondKeepWindow() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-prune-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // One good snapshot (oldest), then several newer EMPTY snapshots.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        for stamp in ["1700000100-1.1.0", "1700000200-1.2.0", "1700000300-1.3.0", "1700000400-1.4.0"] {
            StoreRepair.snapshot(at: storeURL, stamp: stamp)
        }

        StoreRepair.pruneSnapshots(at: storeURL, keeping: 3)

        let good = dir.appendingPathComponent("store.sqlite.snapshot-1700000000-1.0.0.bak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: good.path), "the newest usable snapshot must survive prune")
        XCTAssertEqual(StoreRepair.newestRestorableSnapshot(for: storeURL)?.version, "1.0.0")
    }

    /// Unreadable content must not be treated as evidence of a seed. A snapshot
    /// that opens, holds real `ZSPACE` rows, and passes an integrity check —
    /// exactly what `snapshotHasUsableData` (the automatic-restore rule) already
    /// protects — must still be protected by pruning even when `readContent`
    /// itself fails, because its schema is missing a table `readContent`
    /// requires but `snapshotHasUsableData` does not. Without a fallback to the
    /// shipped rule, pruning would delete the very file the automatic-restore
    /// path would otherwise pick.
    func testPruneFallsBackToShippedRuleWhenContentIsUnreadable() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-prune-unknown-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Oldest snapshot: genuine data. Its own ZSPACESERVICELINK table is then
        // dropped, so `readContent` (which requires all three tables) reads it
        // as UNKNOWN — not empty, not seed-shaped, just unreadable — while
        // `snapshotHasUsableData` (ZSPACE + integrity check only) still passes it.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        let genuineSnapshot = dir.appendingPathComponent("store.sqlite.snapshot-1700000000-1.0.0.bak")
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: genuineSnapshot.path + suffix))
        }
        _ = try SQLiteHelpers.run(genuineSnapshot, "DROP TABLE ZSPACESERVICELINK;")

        // Then several newer, genuinely EMPTY snapshots — no data at all, so
        // they must never be mistaken for something worth protecting.
        try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        for stamp in ["1700000100-1.1.0", "1700000200-1.2.0", "1700000300-1.3.0", "1700000400-1.4.0"] {
            StoreRepair.snapshot(at: storeURL, stamp: stamp)
        }

        StoreRepair.pruneSnapshots(at: storeURL, keeping: 3)

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: genuineSnapshot.path),
            "a snapshot whose content merely failed to read must not be pruned as if it were a seed"
        )
    }

    /// Pruning must protect the newest snapshot holding the user's own data, not
    /// the newest one that merely has rows. A snapshot taken after the loss holds
    /// the default seed, and treating that as worth keeping let the real backup
    /// age out of the keep-3 window and be deleted.
    func testPruneProtectsTheUsersDataNotASeededSnapshot() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-prune-seed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Oldest snapshot: the user's own 5 spaces.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 5)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.5.11+20")

        // Then four newer snapshots of a seed-shaped store, as four updates
        // after the loss would produce.
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSeedShape(storeURL)
        for (i, version) in ["1.5.12+21", "1.5.13+22", "1.5.14+23", "1.5.15+24"].enumerated() {
            StoreRepair.snapshot(at: storeURL, stamp: "17000005\(i)0-\(version)")
        }

        StoreRepair.pruneSnapshots(at: storeURL, keeping: 3)

        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.sqlite.snapshot-") && $0.hasSuffix(".bak") }
        XCTAssertTrue(
            remaining.contains { $0.contains("1.5.11+20") },
            "the only snapshot holding the user's data must survive pruning, got \(remaining)"
        )
    }

    /// Each user-chosen restore writes a full store triple aside under
    /// `.prepick-`, and no existing reaper matches that family, so without this
    /// the directory grows by one copy of the whole store per restore, forever.
    /// Recency alone is not enough here, unlike `pruneSnapshots`: the OLDEST
    /// aside is the store as it stood before the user began trying candidates at
    /// all, so it must survive alongside the newest few, not be pruned away by
    /// a purely newest-first rule the way a run of several restores would.
    func testPrunePickAsidesKeepsNewestPlusOldest() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-prune-pick-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)

        // Five asides, oldest first. Pruning is filename bookkeeping — it never
        // reads a candidate's contents — so stand-in bytes are the honest
        // fixture here, and they keep the test fast.
        let stamps = ["1700000010", "1700000020", "1700000030", "1700000040", "1700000050"]
        for stamp in stamps {
            for suffix in ["", "-wal", "-shm"] {
                let path = storeURL.path + ".prepick-\(stamp).bak" + suffix
                try Data("aside \(stamp)\(suffix)".utf8).write(to: URL(fileURLWithPath: path))
            }
        }

        StoreRepair.prunePickAsides(at: storeURL, keeping: 3)

        let left = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let primaries = left.filter { $0.hasPrefix("store.sqlite.prepick-") && $0.hasSuffix(".bak") }.sorted()
        XCTAssertEqual(
            primaries,
            ["store.sqlite.prepick-1700000010.bak",
             "store.sqlite.prepick-1700000030.bak",
             "store.sqlite.prepick-1700000040.bak",
             "store.sqlite.prepick-1700000050.bak"],
            "the newest three plus the oldest must survive, got \(primaries)"
        )
        for suffix in ["", "-wal", "-shm"] {
            XCTAssertFalse(
                left.contains("store.sqlite.prepick-1700000020.bak" + suffix),
                "the second-oldest aside must be pruned along with its whole triple, \(suffix) survived"
            )
        }
        XCTAssertTrue(left.contains("store.sqlite"), "pruning must never touch the live store")
    }

    /// A stale `hasEverHadData` flag with NO store file and no snapshot (e.g. a
    /// support step deleted the store but not the preferences) must start fresh
    /// and clear the flag — not brick the app into a permanent empty state.
    func testLoadContainerStaleFlagWithNoFileStartsFresh() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("atoll-stale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")   // deliberately not created
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "atoll-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: StoreLoader.hasEverHadDataKey)   // stale

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        XCTAssertEqual(outcome, .openedClean, "no file + nothing to restore must start fresh, not fall to a permanent empty state")
        XCTAssertFalse(defaults.bool(forKey: StoreLoader.hasEverHadDataKey), "the stale flag must be cleared so the seed can run")
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<Space>()), 0)
    }

}
