import XCTest
import Foundation
import SwiftData
import SQLite3
import BlattaCore
@testable import Blatta

final class StoreRecoveryTests: XCTestCase {
    static var storeSchema: Schema {
        ModelFixtures.storeSchema
    }

    // MARK: - Store pre-migration snapshots

    /// Makes a throwaway directory holding a fake `default.store` triple and
    /// returns the store URL. The caller removes the directory when done.
    func makeFakeStore() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-snapshot-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let store = dir.appending(path: "default.store")
        for suffix in ["", "-wal", "-shm"] {
            try Data("db\(suffix)".utf8).write(to: URL(fileURLWithPath: store.path + suffix))
        }
        return store
    }

    func snapshotFiles(besides store: URL) -> [String] {
        let dir = store.deletingLastPathComponent()
        let prefix = store.lastPathComponent + StoreRepair.snapshotInfix
        let all = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return all.filter { $0.hasPrefix(prefix) }.sorted()
    }

    func testSnapshotCopiesTheWholeStoreTriple() throws {
        let store = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        StoreRepair.snapshot(at: store, stamp: "1000000000")

        let made = snapshotFiles(besides: store)
        XCTAssertEqual(made, [
            "default.store.snapshot-1000000000.bak",
            "default.store.snapshot-1000000000.bak-shm",
            "default.store.snapshot-1000000000.bak-wal",
        ])
    }

    func testPruneKeepsOnlyTheMostRecentSnapshots() throws {
        let store = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }

        // Five snapshots, oldest to newest by their fixed-width stamp.
        for stamp in ["1000000001", "1000000002", "1000000003", "1000000004", "1000000005"] {
            StoreRepair.snapshot(at: store, stamp: stamp)
        }
        StoreRepair.pruneSnapshots(at: store, keeping: 2)

        // Only the two newest triples survive (3 files each).
        let survivors = snapshotFiles(besides: store)
        XCTAssertEqual(survivors.count, 6)
        XCTAssertTrue(survivors.allSatisfy { $0.contains("1000000004") || $0.contains("1000000005") })
    }

    func testBackupOnlyRunsWhenTheVersionChanges() throws {
        let store = try makeFakeStore()
        defer { try? FileManager.default.removeItem(at: store.deletingLastPathComponent()) }
        let suite = "blatta-snapshot-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        // First launch on 1.5.7 — snapshot taken.
        StoreRepair.backupBeforeMigrationIfNeeded(at: store, version: "1.5.7", defaults: defaults, keeping: 3)
        XCTAssertEqual(snapshotFiles(besides: store).count, 3)

        // Relaunch, same version — no new snapshot.
        StoreRepair.backupBeforeMigrationIfNeeded(at: store, version: "1.5.7", defaults: defaults, keeping: 3)
        XCTAssertEqual(snapshotFiles(besides: store).count, 3)

        // New version installed — snapshot the pre-migration state again.
        StoreRepair.backupBeforeMigrationIfNeeded(at: store, version: "1.5.8", defaults: defaults, keeping: 3)
        XCTAssertEqual(snapshotFiles(besides: store).count, 6)
    }

    func testBackupIsANoOpWhenNoStoreExistsYet() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-snapshot-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = dir.appending(path: "default.store")  // never created
        let suite = "blatta-snapshot-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        StoreRepair.backupBeforeMigrationIfNeeded(at: store, version: "1.5.7", defaults: defaults, keeping: 3)
        XCTAssertEqual(snapshotFiles(besides: store).count, 0)
    }

    // MARK: - VersionedSchema migration

    /// Go/no-go for the enum-nested layout: SwiftData must resolve each nested
    /// `@Model` to its bare class name, else a real store won't match the
    /// declared version. (Verified here on this machine's macOS; the 14.0 target
    /// still needs a real-device pass per the plan — entity naming is a
    /// compile-time behavior so this is a fair proxy, the migration race is not.)
    func testVersionedSchemaEntityNamesAreBare() {
        let schemas: [(String, Schema)] = [
            ("V1_5_11", Schema(versionedSchema: BlattaSchemaV1_5_11.self)),
            ("V1_5_12", Schema(versionedSchema: BlattaSchemaV1_5_12.self)),
            ("VCurrent", Schema(versionedSchema: BlattaSchemaVCurrent.self)),
        ]
        for (label, schema) in schemas {
            let names = Set(schema.entities.map(\.name))
            for expected in ["ServiceInstance", "Space", "SpaceServiceLink", "AppPreferences"] {
                XCTAssertTrue(names.contains(expected), "\(label) entity names not bare: \(names)")
            }
        }
    }

    /// The plan's versions strictly increase and its stages connect every
    /// consecutive pair with no gap.
    func testMigrationPlanShapeIsContiguousAndIncreasing() {
        let versions = BlattaMigrationPlan.schemas.map { $0.versionIdentifier }
        XCTAssertEqual(versions, versions.sorted(), "versionIdentifiers must be in increasing order")
        XCTAssertEqual(Set(versions).count, versions.count, "versionIdentifiers must be unique")
        XCTAssertEqual(
            BlattaMigrationPlan.stages.count,
            BlattaMigrationPlan.schemas.count - 1,
            "need exactly one stage between each consecutive version"
        )
    }

    /// Drift guard: the current stored shape is pinned here. If this fails, a
    /// stored property changed on a model — freeze the prior shape as a new
    /// `BlattaSchemaV…`, bump `BlattaSchemaVCurrent`, add a stage + fixture, then
    /// update these sets. Turns "forgot to version a schema change" into a red
    /// test. `AppPreferences` is covered because the historical versioned schemas
    /// share a FROZEN copy of it — this catches drift between that frozen copy and
    /// the live model.
    func testCurrentStoredShapeIsPinned() throws {
        let schema = Schema(versionedSchema: BlattaSchemaVCurrent.self)
        func entity(_ name: String) throws -> Schema.Entity {
            try XCTUnwrap(schema.entities.first { $0.name == name }, "no entity \(name)")
        }

        let service = try entity("ServiceInstance")
        XCTAssertEqual(
            Set(service.attributes.map(\.name)),
            [
                "id", "label", "url", "customIconData", "fetchedIconData", "faviconFetchedAt",
                "catalogEntryID", "isMuted", "showBadge", "neverHibernate", "userAgent",
                "dataStoreIdentifier", "pageZoom", "osNotificationsEnabled", "customCSS",
                "forceDarkMode", "darkModeRaw", "cameraPolicyRaw", "microphonePolicyRaw",
                "openExternalLinksInApp", "stayActiveInBackground", "hasSeenPasskeyNotice",
                "hibernationPolicyRaw", "hibernateAfterMinutes", "createdAt", "lastAccessedAt",
            ],
            "ServiceInstance stored attributes changed without a new schema version"
        )
        XCTAssertEqual(
            Set(service.relationships.map(\.name)), ["spaceLinks"],
            "ServiceInstance relationships changed without a new schema version"
        )

        XCTAssertEqual(
            Set(try entity("Space").attributes.map(\.name)),
            ["id", "name", "emoji", "sortOrder", "isMuted", "createdAt"],
            "Space stored attributes changed without a new schema version"
        )
        XCTAssertEqual(
            Set(try entity("SpaceServiceLink").attributes.map(\.name)),
            ["id", "sortOrder"],
            "SpaceServiceLink stored attributes changed without a new schema version"
        )

        // Both ends must stay optional. Non-optional is what made a cascade
        // delete trap on macOS 15 and kill the app on deleting a space, and the
        // attribute set above cannot see it because a relationship is not an
        // attribute — so assert it directly.
        let link = try entity("SpaceServiceLink")
        for name in ["space", "service"] {
            let relationship = try XCTUnwrap(
                link.relationships.first { $0.name == name },
                "SpaceServiceLink lost its \(name) relationship"
            )
            XCTAssertTrue(
                relationship.isOptional,
                "SpaceServiceLink.\(name) must stay optional: a .cascade delete has to clear it, and SwiftData traps on macOS 15 when it cannot"
            )
        }

        // Control, so the check above cannot pass vacuously: the frozen 1.5.13
        // shape is the same relationships NOT optional, and `isOptional` has to
        // tell them apart or it is measuring nothing.
        let frozenLink = try XCTUnwrap(
            Schema(versionedSchema: BlattaSchemaV1_5_13.self)
                .entities.first { $0.name == "SpaceServiceLink" }
        )
        for name in ["space", "service"] {
            let relationship = try XCTUnwrap(frozenLink.relationships.first { $0.name == name })
            XCTAssertFalse(
                relationship.isOptional,
                "the frozen 1.5.13 shape is meant to be the non-optional one"
            )
        }
        XCTAssertEqual(
            Set(try entity("AppPreferences").attributes.map(\.name)),
            [
                "id", "appPresenceMode", "launchAtLogin", "globalKeyboardShortcutsEnabled",
                "showBadgeCountInDock", "autoDismissCookieBanners", "selectedSpaceID",
                "selectedServiceID", "defaultZoom", "scheduledDNDEnabled", "dndStartMinutes",
                "dndEndMinutes", "appLockEnabled", "lockOnLaunch", "lockOnSleep", "railLayoutRaw",
                "appearanceModeRaw", "contentBlockingEnabled", "annoyanceBlockingEnabled",
                "defaultCameraPolicyRaw", "defaultMicrophonePolicyRaw", "googleFaviconFallbackEnabled",
                "autoHibernateIdleEnabled", "autoHibernateIdleMinutes",
            ],
            "AppPreferences stored attributes changed — freeze its historical shape before editing (see BlattaSchema.swift)"
        )
    }

    /// Guards that the shared frozen `AppPreferences` still matches the live model,
    /// the specific drift the review flagged: the historical versioned schemas
    /// reference the frozen copy, so if the live `AppPreferences` gains a field
    /// and the frozen copy isn't updated with a new version, a real old store
    /// stops matching its declared version. Compare their attribute sets directly.
    func testFrozenAppPreferencesMatchesLiveModel() {
        let frozen = Schema([BlattaSchemaV1_5_11.AppPreferences.self])
        let live = Schema([AppPreferences.self])
        let frozenAttrs = Set((frozen.entities.first?.attributes ?? []).map(\.name))
        let liveAttrs = Set((live.entities.first?.attributes ?? []).map(\.name))
        XCTAssertEqual(
            frozenAttrs, liveAttrs,
            "frozen AppPreferences drifted from live — if you added a settings field, freeze the prior shape and add a new schema version"
        )
    }

    /// The incident path. Write a store at the 1.5.11 shape, reopen it at the
    /// current shape through the migration plan, and assert every row and field survives —
    /// with the fields added after 1.5.11 defaulting correctly. Proves the stage
    /// mapping is lossless. It does not test concurrent store access.
    @MainActor
    func testMigratesFrom1_5_11PreservingAllData() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-migr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "default.store")

        let serviceID = UUID(), spaceID = UUID(), linkID = UUID()

        // 1) Seed a store at the 1.5.11 shape (no migration plan).
        try autoreleasepool {
            let schema = Schema(versionedSchema: BlattaSchemaV1_5_11.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = container.mainContext
            let space = BlattaSchemaV1_5_11.Space(id: spaceID, name: "Work", emoji: "🏢", sortOrder: 3)
            space.isMuted = true
            let service = BlattaSchemaV1_5_11.ServiceInstance(id: serviceID, label: "Gmail", url: "https://mail.google.com")
            // Set EVERY 1.5.11 stored field to a distinct non-default value, so a
            // stage that silently dropped a pre-existing column would fail below.
            service.customIconData = Data([1, 2, 3])
            service.fetchedIconData = Data([4, 5, 6])
            service.faviconFetchedAt = Date(timeIntervalSince1970: 1_000_000)
            service.catalogEntryID = "gmail"
            service.isMuted = true
            service.showBadge = false
            service.neverHibernate = true
            service.userAgent = "CustomUA/1.0"
            service.pageZoom = 1.25
            service.osNotificationsEnabled = false
            service.customCSS = "body { color: red; }"
            service.forceDarkMode = true
            service.darkModeRaw = "on"
            service.cameraPolicyRaw = "deny"
            service.microphonePolicyRaw = "allow"
            service.openExternalLinksInApp = true
            service.hasSeenPasskeyNotice = true
            let link = BlattaSchemaV1_5_11.SpaceServiceLink(id: linkID, sortOrder: 5, space: space, service: service)
            ctx.insert(space); ctx.insert(service); ctx.insert(link)
            try ctx.save()
        }

        // 2) Reopen at the current shape through the plan.
        let schema = Schema(versionedSchema: BlattaSchemaVCurrent.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: BlattaMigrationPlan.self, configurations: [config])
        let ctx = container.mainContext

        let services = try ctx.fetch(FetchDescriptor<ServiceInstance>())
        XCTAssertEqual(services.count, 1)
        let s = try XCTUnwrap(services.first)
        XCTAssertEqual(s.id, serviceID)
        XCTAssertEqual(s.label, "Gmail")
        XCTAssertEqual(s.url, "https://mail.google.com")
        XCTAssertEqual(s.customIconData, Data([1, 2, 3]))
        XCTAssertEqual(s.fetchedIconData, Data([4, 5, 6]))
        XCTAssertEqual(s.faviconFetchedAt, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(s.catalogEntryID, "gmail")
        XCTAssertTrue(s.isMuted)
        XCTAssertFalse(s.showBadge)
        XCTAssertTrue(s.neverHibernate)
        XCTAssertEqual(s.userAgent, "CustomUA/1.0")
        XCTAssertEqual(s.pageZoom, 1.25)
        XCTAssertEqual(s.osNotificationsEnabled, false)
        XCTAssertEqual(s.customCSS, "body { color: red; }")
        XCTAssertEqual(s.forceDarkMode, true)
        XCTAssertEqual(s.darkModeRaw, "on")
        XCTAssertEqual(s.cameraPolicyRaw, "deny")
        XCTAssertEqual(s.microphonePolicyRaw, "allow")
        XCTAssertEqual(s.openExternalLinksInApp, true)
        XCTAssertEqual(s.hasSeenPasskeyNotice, true)
        // Added after 1.5.11 → nil on disk, resolving to their documented defaults.
        XCTAssertNil(s.stayActiveInBackground)
        XCTAssertNil(s.hibernationPolicyRaw)
        XCTAssertNil(s.hibernateAfterMinutes)
        XCTAssertFalse(s.staysActiveInBackgroundEffective)
        XCTAssertEqual(s.hibernationPolicyEffective, .never)  // legacy neverHibernate == true

        let spaces = try ctx.fetch(FetchDescriptor<Space>())
        XCTAssertEqual(spaces.count, 1)
        let sp = try XCTUnwrap(spaces.first)
        XCTAssertEqual(sp.id, spaceID)
        XCTAssertEqual(sp.name, "Work")
        XCTAssertEqual(sp.sortOrder, 3)
        XCTAssertTrue(sp.isMutedEffective)

        let links = try ctx.fetch(FetchDescriptor<SpaceServiceLink>())
        XCTAssertEqual(links.count, 1)
        let l = try XCTUnwrap(links.first)
        XCTAssertEqual(l.sortOrder, 5)
        XCTAssertEqual(l.liveSpace?.id, spaceID)
        XCTAssertEqual(l.liveService?.id, serviceID)
    }

    /// The second stage (1.5.12 → current). A 1.5.12 store already has
    /// `stayActiveInBackground`; it must survive, and only the hibernation fields
    /// should arrive as nil.
    @MainActor
    func testMigratesFrom1_5_12PreservingAllData() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-migr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "default.store")

        let serviceID = UUID()

        try autoreleasepool {
            let schema = Schema(versionedSchema: BlattaSchemaV1_5_12.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = container.mainContext
            let service = BlattaSchemaV1_5_12.ServiceInstance(id: serviceID, label: "Teams", url: "https://teams.microsoft.com")
            service.stayActiveInBackground = true
            ctx.insert(service)
            try ctx.save()
        }

        let schema = Schema(versionedSchema: BlattaSchemaVCurrent.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: BlattaMigrationPlan.self, configurations: [config])
        let ctx = container.mainContext

        let s = try XCTUnwrap(try ctx.fetch(FetchDescriptor<ServiceInstance>()).first)
        XCTAssertEqual(s.id, serviceID)
        XCTAssertEqual(s.label, "Teams")
        XCTAssertEqual(s.stayActiveInBackground, true)
        XCTAssertTrue(s.staysActiveInBackgroundEffective)
        XCTAssertNil(s.hibernationPolicyRaw)
        XCTAssertNil(s.hibernateAfterMinutes)
    }

    /// The REAL production provenance. Every field store today was written by the
    /// old `AppState.init`, which used a PLAIN `Schema([...])` (no version), not a
    /// `VersionedSchema`. This seeds a store exactly that way — a plain `Schema`
    /// over the 1.5.11-shaped types — then opens it through the versioned plan,
    /// the way the upgraded app will. It must open with data intact, NOT throw
    /// (which would strand every existing user in the in-memory fallback). Locks
    /// in CI what the local real-snapshot check proved by hand. (macOS 14.0 still
    /// needs its own device pass — the migration race is OS-specific.)
    @MainActor
    func testMigratesFromPlainSchemaProductionStore() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-migr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "default.store")

        let serviceID = UUID(), spaceID = UUID()

        // Seed with a PLAIN Schema of the 1.5.11-shaped types — production's exact
        // write path (plain Schema, older shape), not Schema(versionedSchema:).
        try autoreleasepool {
            let schema = Schema([
                BlattaSchemaV1_5_11.ServiceInstance.self,
                BlattaSchemaV1_5_11.Space.self,
                BlattaSchemaV1_5_11.SpaceServiceLink.self,
                BlattaSchemaV1_5_11.AppPreferences.self,
            ])
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = container.mainContext
            let space = BlattaSchemaV1_5_11.Space(id: spaceID, name: "Work", emoji: "🏢", sortOrder: 1)
            let service = BlattaSchemaV1_5_11.ServiceInstance(id: serviceID, label: "Gmail", url: "https://mail.google.com")
            let link = BlattaSchemaV1_5_11.SpaceServiceLink(id: UUID(), sortOrder: 0, space: space, service: service)
            let prefs = BlattaSchemaV1_5_11.AppPreferences(id: UUID())
            ctx.insert(space); ctx.insert(service); ctx.insert(link); ctx.insert(prefs)
            try ctx.save()
        }

        // Open through the plan, as the upgraded production app does.
        let schema = Schema(versionedSchema: BlattaSchemaVCurrent.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, migrationPlan: BlattaMigrationPlan.self, configurations: [config])
        let ctx = container.mainContext

        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<Space>()), 1, "plain-Schema store must not migrate to empty")
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<ServiceInstance>()), 1)
        XCTAssertEqual(try ctx.fetchCount(FetchDescriptor<SpaceServiceLink>()), 1)
        let s = try XCTUnwrap(try ctx.fetch(FetchDescriptor<ServiceInstance>()).first)
        XCTAssertEqual(s.id, serviceID)
        XCTAssertEqual(s.label, "Gmail")
    }

    // MARK: - Store content and the default-seed fingerprint

    /// The fingerprint must match the seed exactly and nothing else.
    func testUntouchedSeedFingerprint() {
        let seed = StoreContent(
            spaces: 2,
            services: 7,
            links: 7,
            spaceNames: DefaultSeed.spaces.map(\.name),
            serviceLabels: DefaultSeed.allServiceLabels
        )
        XCTAssertTrue(seed.looksLikeUntouchedSeed, "the exact seed shape must match")

        var labels = DefaultSeed.allServiceLabels
        labels.append("Notion")
        let plusOne = StoreContent(spaces: 2, services: 8, links: 8, spaceNames: DefaultSeed.spaces.map(\.name), serviceLabels: labels)
        XCTAssertFalse(plusOne.looksLikeUntouchedSeed, "one added service means the user has touched it")

        let renamed = StoreContent(spaces: 2, services: 7, links: 7, spaceNames: ["Personal", "Clients"], serviceLabels: DefaultSeed.allServiceLabels)
        XCTAssertFalse(renamed.looksLikeUntouchedSeed, "a renamed space means the user has touched it")

        let empty = StoreContent(spaces: 0, services: 0, links: 0, spaceNames: [], serviceLabels: [])
        XCTAssertFalse(empty.looksLikeUntouchedSeed, "an empty store is empty, not seeded")
        XCTAssertTrue(empty.isEmpty)
    }

    /// The fingerprint must recognize a store built from the seed lists the
    /// seeder uses. If someone edits one seed list and not the fingerprint, this
    /// goes red.
    @MainActor
    func testSeededStoreIsFingerprintedAsSeed() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-seedprint-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        let config = ModelConfiguration(schema: Self.storeSchema, url: storeURL)
        let container = try ModelContainer(for: Self.storeSchema, configurations: [config])
        let ctx = container.mainContext
        let spaces = DefaultSeed.spaces.enumerated().map { index, entry in
            Space(name: entry.name, emoji: entry.emoji, sortOrder: index)
        }
        for space in spaces { ctx.insert(space) }
        for (index, entry) in DefaultSeed.personalServices.enumerated() {
            let service = ServiceInstance(label: entry.label, url: entry.url, catalogEntryID: entry.catalogID)
            ctx.insert(service)
            ctx.insert(SpaceServiceLink(sortOrder: index, space: spaces[0], service: service))
        }
        for (index, entry) in DefaultSeed.workServices.enumerated() {
            let service = ServiceInstance(label: entry.label, url: entry.url, catalogEntryID: entry.catalogID)
            ctx.insert(service)
            ctx.insert(SpaceServiceLink(sortOrder: index, space: spaces[1], service: service))
        }
        try ctx.save()

        let content = StoreContent(
            spaces: try ctx.fetchCount(FetchDescriptor<Space>()),
            services: try ctx.fetchCount(FetchDescriptor<ServiceInstance>()),
            links: try ctx.fetchCount(FetchDescriptor<SpaceServiceLink>()),
            spaceNames: try ctx.fetch(FetchDescriptor<Space>()).map(\.name),
            serviceLabels: try ctx.fetch(FetchDescriptor<ServiceInstance>()).map(\.label)
        )
        XCTAssertTrue(content.looksLikeUntouchedSeed, "a store built from DefaultSeed must fingerprint as the seed")
    }

    /// Reading a store file must report its real counts and return nil
    /// (unknown) rather than zero for anything it cannot read. WAL visibility
    /// is covered separately, by `testReadContentSeesCommittedRowsStillInTheWAL`.
    @MainActor
    func testReadContentCountsRowsAndDistinguishesUnknown() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-readcontent-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        let content = try XCTUnwrap(StoreInventory.readContent(at: storeURL))
        XCTAssertEqual(content.spaces, 3)
        XCTAssertEqual(content.services, 0, "makePopulatedStore inserts spaces only")
        XCTAssertEqual(Set(content.spaceNames), ["S0", "S1", "S2"], "names come back for the fingerprint")

        // A missing file is unknown, not empty.
        XCTAssertNil(StoreInventory.readContent(at: dir.appendingPathComponent("nope.sqlite")))

        // A file that is not a database is unknown.
        let garbage = dir.appendingPathComponent("garbage.sqlite")
        try "not a database".write(to: garbage, atomically: true, encoding: .utf8)
        XCTAssertNil(StoreInventory.readContent(at: garbage))

        // A database with an unrecognized schema is unknown, never zero.
        let alien = dir.appendingPathComponent("alien.sqlite")
        _ = try SQLiteHelpers.run(alien, "CREATE TABLE ZOTHER (x INTEGER);")
        XCTAssertNil(StoreInventory.readContent(at: alien))
    }

    /// Guards the exact regression this reader exists to avoid. See
    /// `StoreInventory.openReadOnly`'s doc for the full rule: a plain open
    /// never uses `immutable=1` when a `-wal` sibling exists, because a `.bak`
    /// can sit beside a `-wal` holding committed-but-uncheckpointed rows, and
    /// an immutable open would silently under-count it. `makePopulatedStore`
    /// alone can't prove that: its container deallocates at the end of the
    /// call, and SQLite auto-checkpoints (folds the WAL into the main file) on
    /// the last close, so by the time `readContent` runs the row is very likely
    /// already in the main file either way. This test holds a second, writable
    /// connection open for the duration — so nothing checkpoints — commits a
    /// row through it, and shows `readContent` counts that row while a control
    /// connection opened with `immutable=1` does not. This test's store keeps a
    /// real `-wal` file the whole time, so `openReadOnly`'s narrow immutable
    /// fallback (which only applies when no `-wal` sibling exists) must not
    /// engage here; if `readContent` ever used `immutable=1` while a `-wal`
    /// with real rows is present, this goes red.
    @MainActor
    func testReadContentSeesCommittedRowsStillInTheWAL() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-wal-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)

        // A second, writable connection, held open for the rest of the test.
        // The last connection to close is what triggers SQLite's
        // checkpoint-on-close, so keeping this one open is what keeps the row
        // below in the -wal file rather than folded into the main store.
        var writer: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &writer, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
              let writer else {
            XCTFail("could not open a writable connection to the test store")
            return
        }
        defer { sqlite3_close(writer) }

        XCTAssertEqual(Self.execSQL(writer, "PRAGMA journal_mode=WAL;"), SQLITE_OK)
        XCTAssertEqual(Self.execSQL(writer, """
            INSERT INTO ZSPACE (Z_ENT, Z_OPT, ZSORTORDER, ZEMOJI, ZNAME)
            SELECT Z_ENT, 1, 99, '🌊', 'WAL-only' FROM ZSPACE LIMIT 1;
            """), SQLITE_OK, "the insert this test depends on must commit")

        // The row above is committed but, with `writer` still open, sitting in
        // the -wal file rather than the main one.
        let content = try XCTUnwrap(StoreInventory.readContent(at: storeURL))
        XCTAssertEqual(content.spaces, 3, "readContent must see the row committed to the WAL")
        XCTAssertTrue(content.spaceNames.contains("WAL-only"))

        // Control: an immutable=1 open of the same file ignores the WAL, so it
        // must see fewer spaces than readContent did. Without this contrast, a
        // regression that added immutable=1 to readContent could pass the
        // assertion above for the wrong reason (an early, coincidental
        // checkpoint) and this test would not catch it.
        var immutableDB: OpaquePointer?
        let uri = "file:\(storeURL.path)?immutable=1"
        guard sqlite3_open_v2(uri, &immutableDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil) == SQLITE_OK,
              let immutableDB else {
            XCTFail("could not open an immutable connection to the test store")
            return
        }
        defer { sqlite3_close(immutableDB) }

        var stmt: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(immutableDB, "SELECT COUNT(*) FROM ZSPACE;", -1, &stmt, nil), SQLITE_OK)
        defer { sqlite3_finalize(stmt) }
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        let immutableCount = Int(sqlite3_column_int64(stmt, 0))
        XCTAssertLessThan(immutableCount, content.spaces, "an immutable=1 open must not see the WAL-only row")
    }

    /// Runs one SQL statement to completion via `sqlite3_exec`, for test setup
    /// that needs a live, writable connection rather than the one-shot CLI
    /// `runSQLite` uses. Returns the SQLite result code.
    @discardableResult
    static func execSQL(_ db: OpaquePointer, _ sql: String) -> Int32 {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    // MARK: - Candidate enumeration

    /// Enumeration must find all four backup families plus the live store,
    /// parse stamps, and mark an unreadable file as unknown rather than empty.
    @MainActor
    func testCandidateEnumerationCoversAllBackupFamilies() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-inventory-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Live store with 1 space; a 4-space snapshot; a 2-space prerestore; a
        // 3-space corrupt-family backup; a 5-space prepick-family backup (the
        // aside `applyPendingRestore` writes); and one unreadable snapshot.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 4)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.5.11+20")
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 2)
        try ModelFixtures.copyStoreTriple(from: storeURL, to: dir.appendingPathComponent("store.sqlite.prerestore-1700000500.bak"))
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 3)
        try ModelFixtures.copyStoreTriple(from: storeURL, to: dir.appendingPathComponent("store.sqlite.corrupt-1700000600.bak"))
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 5)
        try ModelFixtures.copyStoreTriple(from: storeURL, to: dir.appendingPathComponent("store.sqlite.prepick-1700000700.bak"))
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 1)
        try "not a database".write(
            to: dir.appendingPathComponent("store.sqlite.snapshot-1700000900-1.5.12+21.bak"),
            atomically: true,
            encoding: .utf8
        )

        let live = try XCTUnwrap(StoreInventory.readContent(at: storeURL))
        let found = StoreInventory.candidates(for: storeURL, liveContent: live)

        XCTAssertEqual(found.count, 6, "live + snapshot + prerestore + corrupt + prepick + unreadable snapshot")
        XCTAssertEqual(found.filter { $0.kind == .live }.count, 1)
        XCTAssertEqual(found.first { $0.kind == .live }?.content?.spaces, 1)

        let snapshot = try XCTUnwrap(found.first { $0.kind == .snapshot(version: "1.5.11+20") })
        XCTAssertEqual(snapshot.content?.spaces, 4)
        XCTAssertEqual(snapshot.takenAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertTrue(snapshot.isRestorable)

        XCTAssertEqual(found.first { $0.kind == .prerestore }?.content?.spaces, 2)
        XCTAssertEqual(found.first { $0.kind == .corrupt }?.content?.spaces, 3)
        XCTAssertEqual(found.first { $0.kind == .prepick }?.content?.spaces, 5, "the .prepick- family must be recognized as its own kind, not folded into .corrupt")
        XCTAssertTrue(try XCTUnwrap(found.first { $0.kind == .prepick }).isRestorable)

        let unreadable = try XCTUnwrap(found.first { $0.kind == .snapshot(version: "1.5.12+21") })
        XCTAssertNil(unreadable.content, "an unreadable candidate is unknown, not empty")
        XCTAssertFalse(unreadable.isRestorable, "unknown content is never restorable")
    }

    /// The displayed list must rank backups by completeness
    /// (the same rule `best(among:)` uses), not by filename. A `.corrupt-`
    /// backup — damaged by definition, so it can never be preselected — must
    /// never sort above a `.snapshot-` holding more content just because
    /// ".corrupt-" sorts before ".snapshot-" lexically.
    @MainActor
    func testCandidatesOrdersBackupsByCompletenessNotFilename() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-order-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        // A fuller snapshot (5 spaces) and a thinner corrupt-family backup (1
        // space). Alphabetically ".corrupt-" < ".snapshot-", so a filename sort
        // would put the corrupt one first; completeness must not.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 5)
        try ModelFixtures.copyStoreTriple(from: storeURL, to: dir.appendingPathComponent("store.sqlite.snapshot-1700000000-1.5.11+20.bak"))
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 1)
        try ModelFixtures.copyStoreTriple(from: storeURL, to: dir.appendingPathComponent("store.sqlite.corrupt-1700000600.bak"))

        let live = try XCTUnwrap(StoreInventory.readContent(at: storeURL))
        let found = StoreInventory.candidates(for: storeURL, liveContent: live)

        XCTAssertEqual(found.first?.kind, .live, "the live row must always lead regardless of ranking")

        let snapshotIndex = try XCTUnwrap(found.firstIndex { $0.kind == .snapshot(version: "1.5.11+20") })
        let corruptIndex = try XCTUnwrap(found.firstIndex { $0.kind == .corrupt })
        XCTAssertLessThan(
            snapshotIndex, corruptIndex,
            "a fuller snapshot must sort above a corrupt-family backup, not below it by filename"
        )
    }

    /// A backup whose file header still says WAL-mode but whose `-wal` sibling
    /// is gone (exactly what `StoreRepair.snapshot` produces when it copies a
    /// store after a clean checkpoint, since it only copies suffixes that
    /// exist) must still be readable. A bare `SQLITE_OPEN_READONLY` open of
    /// such a file fails with SQLITE_CANTOPEN on this SQLite build, because a
    /// read-only connection can't create the `-shm` it needs — the exact bug
    /// this task found, reachable in production through both readers that
    /// share `StoreInventory.openReadOnly`. Regression guard: this must fail
    /// if the fallback is removed.
    @MainActor
    func testMainFileOnlyWALBackupIsReadableThroughBothReaders() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-walonly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        // Strip any `-wal`/`-shm` siblings explicitly, so the fixture is a
        // WAL-mode-headed main file with no siblings regardless of exactly
        // when SQLite's own checkpoint-on-close removed them.
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path + "-wal"),
            "precondition: no -wal sibling present"
        )

        let content = try XCTUnwrap(
            StoreInventory.readContent(at: storeURL),
            "a main-file-only WAL-mode backup must still be readable"
        )
        XCTAssertEqual(content.spaces, 3)

        XCTAssertEqual(
            StoreRepair.spaceCount(at: storeURL), 3,
            "spaceCount must share the same fallback as StoreInventory.readContent"
        )
    }

    /// Applying a pending restore must copy the chosen backup into place, always
    /// set the current store aside first, and clear the key so a crash cannot
    /// leave it looping.
    @MainActor
    func testApplyPendingRestoreCopiesAndAlwaysBacksUp() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-pending-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 4)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0.0")
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 1)
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 1, "precondition: live store thinned out")

        defaults.set("store.sqlite.snapshot-1700000000-1.0.0.bak", forKey: DefaultsKey.pendingRestore)
        XCTAssertTrue(StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults))

        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 4, "the chosen backup must be in place")
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must be cleared")

        let asideCount = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.sqlite.prepick-") && $0.hasSuffix(".bak") }
            .count
        XCTAssertEqual(asideCount, 1, "the thinned store must have been set aside, in its own .prepick- family (not .prerestore-, which restoreFromSnapshot's sentinel checks)")

        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix("store.sqlite.prerestore-") }
                .isEmpty,
            "a deliberate restore must never write into the .prerestore- family that restoreFromSnapshot's sentinel watches"
        )

        // A second apply with no key set is a no-op.
        XCTAssertFalse(StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults))

        // A rejected filename must clear the key and change nothing.
        defaults.set("../escape.bak", forKey: DefaultsKey.pendingRestore)
        XCTAssertFalse(StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults))
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore))
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 4, "a rejected name must not touch the store")
    }

    /// The revert branch (the chosen backup turns out unreadable) must put the
    /// previous store back exactly, and must not leave the CHOSEN BACKUP's
    /// `-wal` sitting beside the reverted main file. `copyTriple` used to skip
    /// removing a destination suffix whenever the source lacked it, which is
    /// harmless for the aside copy (a fresh path) but not for the revert: if
    /// the aside has no `-wal` (the normal post-clean-shutdown state) and the
    /// chosen backup's replace step left one behind, the revert would restore
    /// the old main file while leaving that foreign `-wal` in place — and
    /// SQLite does not bind a WAL to a specific database, so the next open
    /// would replay those frames onto the wrong store.
    @MainActor
    func testApplyPendingRestoreRevertsWithoutLeavingAForeignWAL() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-revert-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // The live store, in the normal post-clean-shutdown shape: real data,
        // no `-wal`/`-shm` siblings. This is what the aside copy will capture.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: storeURL.path + "-wal"), "precondition: no -wal sibling")
        let before = try XCTUnwrap(StoreRepair.spaceCount(at: storeURL), "precondition: live store is readable")
        XCTAssertEqual(before, 3)

        // A validly-named, but garbage, chosen backup — readContent will fail
        // on it — WITH a `-wal` sibling of its own. This is the "foreign WAL"
        // that must not survive the revert.
        let backupName = "store.sqlite.corrupt-1700001000.bak"
        let backupURL = dir.appendingPathComponent(backupName)
        try "not a database".write(to: backupURL, atomically: true, encoding: .utf8)
        try "someone else's WAL frames".write(
            to: URL(fileURLWithPath: backupURL.path + "-wal"),
            atomically: true,
            encoding: .utf8
        )

        defaults.set(backupName, forKey: DefaultsKey.pendingRestore)
        XCTAssertFalse(
            StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults),
            "an unreadable chosen backup must report failure"
        )

        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must still be cleared even on revert")
        XCTAssertEqual(
            StoreRepair.spaceCount(at: storeURL), before,
            "the revert must restore exactly what was live before the attempt"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path + "-wal"),
            "no foreign -wal from the rejected backup may remain beside the reverted store"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path + "-shm"),
            "no foreign -shm from the rejected backup may remain beside the reverted store"
        )
    }

    /// The missing-source branch: a filename that passes validation (it names
    /// one of the backup families and belongs to this store) but whose file is
    /// no longer on disk. This must return false, clear the key so it can't
    /// loop, and leave the live store completely untouched — no aside copy, no
    /// partial write.
    @MainActor
    func testApplyPendingRestoreMissingSourceLeavesStoreUntouched() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-missing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        let before = try XCTUnwrap(StoreRepair.spaceCount(at: storeURL))

        // Validly named for this store, but never written to disk.
        let missingName = "store.sqlite.snapshot-1700009999-1.9.9.bak"
        XCTAssertNotNil(
            StoreRecoveryPolicy.validatedRestoreName(
                missingName,
                storeName: storeURL.lastPathComponent
            ),
            "precondition: the name itself must pass validation"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(missingName).path))

        defaults.set(missingName, forKey: DefaultsKey.pendingRestore)
        XCTAssertFalse(StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults))

        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must be cleared")
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), before, "a missing source must not touch the store")

        let anyAsideFiles = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.sqlite.prepick-") }
        XCTAssertTrue(anyAsideFiles.isEmpty, "a missing source must return before any aside copy is made")
    }

    /// `copyTriple` reports whether the restore copy succeeded, so it is tested
    /// directly rather than only indirectly through
    /// `applyPendingRestore`. A real copy into an existing directory succeeds;
    /// a destination inside a directory that does not exist cannot be written
    /// to, so `copyItem` throws and this must report failure, not silently
    /// swallow it the way the old `Void`-returning version did.
    func testCopyTripleReportsSuccessAndFailure() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-copytriple-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceURL = dir.appendingPathComponent("source.sqlite")
        try "some store bytes".write(to: sourceURL, atomically: true, encoding: .utf8)

        let goodDestination = dir.appendingPathComponent("dest.sqlite")
        XCTAssertTrue(
            StoreRepair.copyTriple(from: sourceURL.path, to: goodDestination.path, label: "test-good"),
            "a real copy into an existing directory must report success"
        )
        XCTAssertEqual(try String(contentsOf: goodDestination, encoding: .utf8), "some store bytes")

        let badDestination = dir.appendingPathComponent("does-not-exist").appendingPathComponent("dest.sqlite")
        XCTAssertFalse(
            StoreRepair.copyTriple(from: sourceURL.path, to: badDestination.path, label: "test-bad"),
            "a destination inside a directory that doesn't exist must report failure, not silently succeed"
        )
    }

    /// A failed removal must not produce a false success. The apply step's `removeItem`
    /// on the live store's own main file is made to fail here by setting the
    /// `uchg` (immutable) flag, which blocks deletion even for the file's
    /// owner (verified empirically on this filesystem: `FileManager
    /// .removeItem` fails with "Operation not permitted" under it, the same
    /// failure shape a real permissions or flag problem would produce).
    /// `copyItem` then throws "file already exists" because the (still
    /// present) destination was never actually removed. Before the fix,
    /// `applyPendingRestore` only checked whether `storeURL` still read
    /// afterward — and it did, because it was untouched — so this reported
    /// success having changed nothing. `copyTriple`'s return value now catches
    /// this directly.
    @MainActor
    func testApplyPendingRestoreReportsFailureWhenTheLiveFileResistsRemoval() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-uchg-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        // `copyItem` carries BSD flags across, so the aside copy of the live file
        // can arrive holding `UF_IMMUTABLE` too — and a directory holding an
        // immutable file cannot be removed. Clear the flag on every entry, not
        // just the live file, or this fixture survives the run in the temp
        // directory and `try?` hides that it did.
        defer {
            let fm = FileManager.default
            for name in (try? fm.contentsOfDirectory(atPath: dir.path)) ?? [] {
                _ = chflags(dir.appendingPathComponent(name).path, 0)
            }
            _ = chflags(dir.path, 0)
            try? fm.removeItem(at: dir)
        }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        let before = try XCTUnwrap(StoreRepair.spaceCount(at: storeURL), "precondition: live store is readable")
        XCTAssertEqual(before, 2)

        StoreRepair.snapshot(at: storeURL, stamp: "1700002000-1.0.0")
        let snapshotName = "store.sqlite.snapshot-1700002000-1.0.0.bak"
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: dir.appendingPathComponent(snapshotName).path),
            "precondition: the snapshot to restore from must exist"
        )

        // Lock the live main file so the apply step's own removeItem fails.
        XCTAssertEqual(
            chflags(storeURL.path, UInt32(UF_IMMUTABLE)), 0,
            "precondition: chflags uchg must succeed on this filesystem, or this test cannot exercise the bug"
        )
        defer { _ = chflags(storeURL.path, 0) }

        defaults.set(snapshotName, forKey: DefaultsKey.pendingRestore)
        let result = StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults)

        XCTAssertFalse(
            result,
            "a removeItem failure during apply must be reported as failure, not masked by a stale-but-readable store"
        )
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must still be cleared")
        // Reading (unlike removing or writing) is unaffected by `uchg`, so this
        // is safe to check before the flag is cleared by the `defer` above.
        XCTAssertEqual(
            StoreRepair.spaceCount(at: storeURL), before,
            "the store must still hold its original content -- the apply must not have silently done nothing while reporting success"
        )
    }

    /// A live store that will not open is one of the main situations this picker
    /// exists to rescue, so a restore over one has to go through. The aside copy
    /// of an unreadable store is itself unreadable -- a faithful copy of a
    /// corrupt file is a corrupt file -- so gating the restore on the ASIDE
    /// being readable refused exactly the case the feature was built for. And it
    /// refused it on every launch forever, because the pending key is cleared
    /// before the file work: the user picks a backup, the app restarts, nothing
    /// happens, and there is nothing left to retry.
    @MainActor
    func testApplyPendingRestoreWorksWhenTheLiveStoreCannotBeRead() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-unreadable-live-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        StoreRepair.snapshot(at: storeURL, stamp: "1700003000-1.0.0")
        let snapshotName = "store.sqlite.snapshot-1700003000-1.0.0.bak"
        XCTAssertEqual(
            StoreInventory.readContent(at: dir.appendingPathComponent(snapshotName))?.spaces, 3,
            "precondition: the chosen backup must be readable and hold the data"
        )

        // Now make the live store unopenable, which is what the user reaches for
        // the picker to escape.
        try "not a database".write(to: storeURL, atomically: true, encoding: .utf8)
        XCTAssertNil(
            StoreInventory.readContent(at: storeURL),
            "precondition: the live store must not be readable"
        )

        defaults.set(snapshotName, forKey: DefaultsKey.pendingRestore)
        XCTAssertTrue(
            StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults),
            "a restore over an unreadable live store must go through -- refusing it strands the user on the store they asked to escape"
        )
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 3, "the chosen backup must be in place")
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must be cleared")

        // The unreadable store is still kept, byte for byte: a corrupt copy is
        // exactly the way back to what the user had, so it is worth keeping even
        // though nothing can read it.
        let asides = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.sqlite.prepick-") && $0.hasSuffix(".bak") }
        XCTAssertEqual(asides.count, 1, "the unreadable store must still have been set aside")
        XCTAssertEqual(
            try String(contentsOf: dir.appendingPathComponent(asides[0]), encoding: .utf8),
            "not a database",
            "the aside must be a byte-for-byte copy of what was replaced"
        )
    }

    /// The restore must stop when the aside copy fails. No
    /// `FileManager` seam is needed to reach it -- a containing directory the
    /// process cannot write to blocks every copy into it while leaving the store
    /// perfectly readable (reads need only `r-x`). Nothing may touch the live
    /// store once the way back could not be written.
    ///
    /// Scope, measured rather than assumed: this is a scenario guard, not a
    /// test of the aside gate in isolation. An unwritable directory also stops
    /// the apply step's own copy, so the closing "did the result read?" gate
    /// reaches the same refusal on its own -- removing both aside checks leaves
    /// this test green. The discriminating case is
    /// `testApplyPendingRestoreRefusesWhenOnlyTheAsidesWALFailsToCopy` below,
    /// where the directory stays writable and only the aside is incomplete.
    @MainActor
    func testApplyPendingRestoreRefusesWhenTheAsideCannotBeWritten() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-aside-fail-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer {
            _ = chmod(dir.path, 0o700)
            try? FileManager.default.removeItem(at: dir)
        }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        // A 2-space backup and a 1-space live store, so a restore that wrongly
        // went ahead would be visible in the count afterward.
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        StoreRepair.snapshot(at: storeURL, stamp: "1700004000-1.0.0")
        let snapshotName = "store.sqlite.snapshot-1700004000-1.0.0.bak"
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 1)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: storeURL.path + "-wal"),
            "precondition: no -wal sibling, so the store stays readable through a read-only directory"
        )
        XCTAssertEqual(StoreRepair.spaceCount(at: storeURL), 1, "precondition: live store thinned out")

        // Read and traverse, but not write: the aside copy cannot land.
        XCTAssertEqual(chmod(dir.path, 0o500), 0, "precondition: chmod must succeed on this filesystem")
        XCTAssertNotEqual(
            access(dir.path, W_OK), 0,
            "precondition: the directory must be unwritable, or this test cannot make the aside copy fail"
        )

        defaults.set(snapshotName, forKey: DefaultsKey.pendingRestore)
        XCTAssertFalse(
            StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults),
            "an aside copy that could not be written must stop the restore"
        )
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must still be cleared")
        XCTAssertEqual(
            StoreRepair.spaceCount(at: storeURL), 1,
            "with no way back written, the live store must still hold exactly what it held"
        )
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasPrefix("store.sqlite.prepick-") }
                .isEmpty,
            "nothing could be written, so no aside may be left claiming otherwise"
        )
    }

    /// The subtle half of Finding 1, and the reason the aside step must keep
    /// `copyTriple`'s result instead of only re-reading the aside afterward: a
    /// copy that fails on the `-wal` alone leaves an aside with no `-wal`
    /// sibling, and `openReadOnly` applies its `immutable=1` fallback precisely
    /// BECAUSE no `-wal` is there. So the aside reads fine while missing the
    /// committed-but-uncheckpointed rows the live `-wal` holds, a readability
    /// check waves it through, and the apply then deletes that `-wal` -- real
    /// data loss, of exactly the kind the finding was about.
    @MainActor
    func testApplyPendingRestoreRefusesWhenOnlyTheAsidesWALFailsToCopy() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-aside-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        let walURL = URL(fileURLWithPath: storeURL.path + "-wal")
        defer {
            _ = chmod(walURL.path, 0o600)
            try? FileManager.default.removeItem(at: dir)
        }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 2)
        StoreRepair.snapshot(at: storeURL, stamp: "1700005000-1.0.0")
        let snapshotName = "store.sqlite.snapshot-1700005000-1.0.0.bak"
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")
        try ModelFixtures.insertSpaces(storeURL, count: 1)
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + suffix))
        }

        // Stand in for the partial `ENOSPC`: a `-wal` beside the live store that
        // the copy will attempt and fail on, while the main file copies fine.
        try "rows only this -wal knows about".write(to: walURL, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(walURL.path, 0o000), 0, "precondition: chmod must succeed on this filesystem")
        XCTAssertNotEqual(
            access(walURL.path, R_OK), 0,
            "precondition: the -wal must be unreadable, or its copy cannot be made to fail"
        )
        let liveBytesBefore = try Data(contentsOf: storeURL)

        defaults.set(snapshotName, forKey: DefaultsKey.pendingRestore)
        XCTAssertFalse(
            StoreRepair.applyPendingRestore(at: storeURL, defaults: defaults),
            "an aside missing a suffix that failed to copy is not a way back, so the restore must stop"
        )
        XCTAssertNil(defaults.string(forKey: DefaultsKey.pendingRestore), "the key must still be cleared")
        XCTAssertEqual(
            try Data(contentsOf: storeURL), liveBytesBefore,
            "the live store must be untouched, byte for byte"
        )
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: walURL.path),
            "the live -wal must survive: its committed rows were never captured by the aside"
        )

        // The half-written aside reads fine, which is the whole point: a
        // readability check on it cannot catch this, only the copy's own result.
        let asides = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("store.sqlite.prepick-") && $0.hasSuffix(".bak") }
        XCTAssertEqual(asides.count, 1, "the main file did copy, so one aside primary exists")
        let asideURL = dir.appendingPathComponent(asides[0])
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: asideURL.path + "-wal"),
            "the -wal copy is the one that failed, so the aside has no -wal sibling"
        )
        XCTAssertNotNil(
            StoreInventory.readContent(at: asideURL),
            "the incomplete aside still READS -- pinning why readability is the wrong predicate here"
        )
    }

    /// A store thinned below its record, with a fuller backup present, must
    /// produce an offer whose preselected candidate is that backup.
    @MainActor
    func testEvaluateStoreRecoveryOffersTheFullestBackup() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-evaluate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let storeURL = dir.appendingPathComponent("store.sqlite")
        defer { try? FileManager.default.removeItem(at: dir) }

        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 4)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.5.11+20")
        _ = try SQLiteHelpers.run(storeURL, "DELETE FROM ZSPACE;")

        let live = StoreInventory.readContent(at: storeURL)
        let candidates = StoreInventory.candidates(for: storeURL, liveContent: live)
        let best = StoreRecoveryPolicy.best(among: candidates)
        let record = StoreContent(spaces: 4, services: 0, links: 0, spaceNames: [], serviceLabels: [])

        XCTAssertEqual(
            StoreRecoveryPolicy.offer(
                liveContent: live,
                liveMatchesUntouchedSeed: live?.looksLikeUntouchedSeed ?? false,
                best: best,
                record: record,
                declinedKeys: []
            ),
            .belowRecord
        )
        XCTAssertEqual(
            StoreRecoveryPolicy.preselection(
                among: candidates,
                liveContent: live,
                liveMatchesUntouchedSeed: live?.looksLikeUntouchedSeed ?? false
            )?.content?.spaces,
            4,
            "the 4-space snapshot must be preselected over an emptied live store"
        )
    }

    /// Pins the five independent guards that protect content history. A store
    /// that lost all its spaces but kept its services is the
    /// partial-loss shape that matters most here: it is not `isEmpty`, so only
    /// the offer-outstanding and restore-scheduled guards stop it from being
    /// recorded over while an offer (or an already-accepted pick) about that
    /// very loss is still live.
    @MainActor
    func testShouldRecordContentGuardsNilEmptyFallbackOutstandingOfferAndScheduledRestore() {
        let partialLoss = StoreContent(spaces: 0, services: 5, links: 5, spaceNames: [], serviceLabels: [])
        let empty = StoreContent(spaces: 0, services: 0, links: 0, spaceNames: [], serviceLabels: [])

        XCTAssertFalse(
            StoreRecoveryCoordinator.shouldRecordContent(nil, offerOutstanding: false, isInMemoryFallback: false, restoreScheduled: false),
            "unreadable (nil) content is unknown, never recorded as if it were empty"
        )
        XCTAssertFalse(
            StoreRecoveryCoordinator.shouldRecordContent(empty, offerOutstanding: false, isInMemoryFallback: false, restoreScheduled: false),
            "an empty store must never overwrite the record"
        )
        XCTAssertFalse(
            StoreRecoveryCoordinator.shouldRecordContent(partialLoss, offerOutstanding: true, isInMemoryFallback: false, restoreScheduled: false),
            "a partial-loss store with an offer still outstanding must not be recorded over"
        )
        XCTAssertTrue(
            StoreRecoveryCoordinator.shouldRecordContent(partialLoss, offerOutstanding: false, isInMemoryFallback: false, restoreScheduled: false),
            "the same partial-loss store, once no offer is outstanding (including right after a decline), must record normally"
        )
        XCTAssertFalse(
            StoreRecoveryCoordinator.shouldRecordContent(partialLoss, offerOutstanding: false, isInMemoryFallback: true, restoreScheduled: false),
            "the in-memory-fallback container is a throwaway; its content must never be recorded"
        )
        XCTAssertFalse(
            StoreRecoveryCoordinator.shouldRecordContent(partialLoss, offerOutstanding: false, isInMemoryFallback: false, restoreScheduled: true),
            "a restore waiting for the next launch must preserve the evidence of loss"
        )
    }

    @MainActor
    func testCoordinatorMapsLaunchOutcomeToBannerAndCleanupSafety() throws {
        let container = try makeRecoveryContainer()
        let storeURL = URL(fileURLWithPath: "/tmp/blatta-recovery/default.store")

        let clean = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .openedClean,
            wasDamagedAtLaunch: false
        )
        XCTAssertNil(clean.banner)
        XCTAssertTrue(clean.isSafeToReclaim)

        let damaged = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .openedClean,
            wasDamagedAtLaunch: true
        )
        XCTAssertFalse(damaged.isSafeToReclaim)

        let restored = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .restoredFromSnapshot(version: "1.0", takenAt: nil),
            wasDamagedAtLaunch: false
        )
        XCTAssertEqual(restored.banner?.isDismissible, true)
        XCTAssertFalse(restored.isSafeToReclaim)
        restored.dismissBanner()
        XCTAssertNil(restored.banner)

        let fallback = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .inMemoryFallback(reason: "test"),
            wasDamagedAtLaunch: false
        )
        XCTAssertEqual(fallback.banner?.folderURL, storeURL.deletingLastPathComponent())
        XCTAssertEqual(fallback.banner?.isDismissible, false)
        XCTAssertFalse(fallback.isSafeToReclaim)
        fallback.dismissBanner()
        XCTAssertNotNil(fallback.banner, "an active temporary-storage warning must stay visible")
    }

    @MainActor
    func testCoordinatorReadsTheStoreFileInsteadOfTemporaryContainerDuringFallback() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("blatta-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("default.store")
        try ModelFixtures.makePopulatedStore(at: storeURL, spaces: 3)
        StoreRepair.snapshot(at: storeURL, stamp: "1700000000-1.0")
        try SQLiteHelpers.run(
            storeURL,
            "DELETE FROM ZSPACE WHERE Z_PK NOT IN (SELECT Z_PK FROM ZSPACE LIMIT 1);"
        )

        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(
            StoreRecoveryPolicy.encodeRecord(StoreContent(
                spaces: 3,
                services: 0,
                links: 0,
                spaceNames: [],
                serviceLabels: []
            )),
            forKey: DefaultsKey.lastKnownContent
        )
        let container = try makeRecoveryContainer()
        let coordinator = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .inMemoryFallback(reason: "test"),
            wasDamagedAtLaunch: false,
            defaults: defaults
        )

        coordinator.evaluateOffer()

        let live = try XCTUnwrap(coordinator.candidates.first { $0.kind == .live })
        XCTAssertEqual(live.content?.spaces, 1)
        XCTAssertEqual(coordinator.offer, .belowRecord)
        XCTAssertEqual(
            StoreRecoveryPolicy.best(among: coordinator.candidates)?.content?.spaces,
            3
        )
        XCTAssertNil(
            coordinator.preselectedCandidate,
            "a readable live store with user data must require an explicit choice"
        )

        coordinator.declineOffer()
        XCTAssertNil(coordinator.offer)
        XCTAssertEqual(
            defaults.stringArray(forKey: DefaultsKey.declinedRestores)?.count,
            1
        )
        coordinator.evaluateOffer()
        XCTAssertNil(coordinator.offer, "the same declined pairing must stay dismissed")
    }

    @MainActor
    func testCoordinatorArmsAndQuitsOnceAfterValidRestoreChoice() throws {
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try makeRecoveryContainer()
        let storeURL = URL(fileURLWithPath: "/tmp/blatta-recovery/default.store")
        var armCount = 0
        var quitCount = 0
        let coordinator = StoreRecoveryCoordinator(
            context: container.mainContext,
            storeURL: storeURL,
            outcome: .openedClean,
            wasDamagedAtLaunch: false,
            defaults: defaults,
            armRelaunch: {
                armCount += 1
                return true
            },
            quit: { quitCount += 1 }
        )
        let name = "default.store.snapshot-1700000000-1.0.bak"
        let candidate = StoreCandidate(
            url: storeURL.deletingLastPathComponent().appendingPathComponent(name),
            kind: .snapshot(version: "1.0"),
            takenAt: nil,
            content: StoreContent(
                spaces: 2,
                services: 3,
                links: 3,
                spaceNames: [],
                serviceLabels: []
            ),
            isDamaged: false
        )

        XCTAssertTrue(coordinator.chooseRestore(candidate))
        XCTAssertEqual(armCount, 1)
        XCTAssertTrue(coordinator.isRestartArmed)
        XCTAssertEqual(defaults.string(forKey: DefaultsKey.pendingRestore), name)

        coordinator.quitForScheduledRestore()
        coordinator.quitForScheduledRestore()

        XCTAssertEqual(quitCount, 1)
        XCTAssertFalse(coordinator.isRestartArmed)
    }

    /// The filename a choice writes must be one the launch path will accept.
    /// This is the seam between the picker and `applyPendingRestore`, and a
    /// mismatch here would silently do nothing on the next launch.
    func testChosenCandidateNameSurvivesValidation() {
        let storeURL = URL(fileURLWithPath: "/tmp/whatever/default.store")
        let cases: [(name: String, kind: StoreCandidate.Kind)] = [
            ("default.store.snapshot-1700000000-1.5.11+20.bak", .snapshot(version: "1.5.11+20")),
            ("default.store.prerestore-1700000500.bak", .prerestore),
            ("default.store.corrupt-1700000600.bak", .corrupt),
            ("default.store.prepick-1700000700.bak", .prepick),
        ]
        for (name, kind) in cases {
            let candidate = StoreCandidate(
                url: storeURL.deletingLastPathComponent().appendingPathComponent(name),
                kind: kind,
                takenAt: nil,
                content: StoreContent(spaces: 1, services: 1, links: 1, spaceNames: [], serviceLabels: []),
                isDamaged: false
            )
            XCTAssertEqual(
                StoreRecoveryPolicy.validatedRestoreName(
                    candidate.url.lastPathComponent,
                    storeName: storeURL.lastPathComponent
                ),
                name,
                "a candidate the picker can show must be one the launch path accepts"
            )
            XCTAssertTrue(
                candidate.isRestorable,
                "every candidate this test claims the picker can show must actually be restorable"
            )
        }
    }

    /// A quit requested while a sheet is attached is refused by AppKit and
    /// dropped, not deferred. The picker hit this for real: it quit from inside
    /// its own sheet, so the app stayed running, the relaunch poller expired,
    /// and the restore only landed when the user next opened Blatta by hand.
    /// The rule below is what keeps the quit waiting for the sheet to go.
    func testWaitsForAnAttachedSheetBeforeQuitting() {
        XCTAssertTrue(
            AppRelauncher.shouldWaitForSheet(sheetAttached: true, attempt: 0),
            "a quit through an attached sheet is dropped, so it has to wait"
        )
        XCTAssertTrue(AppRelauncher.shouldWaitForSheet(sheetAttached: true, attempt: 1))
    }

    /// Nothing in the way means quit now: waiting on every restart would add a
    /// delay to the one path this feature exists for.
    func testQuitsImmediatelyWithNoSheetAttached() {
        XCTAssertFalse(AppRelauncher.shouldWaitForSheet(sheetAttached: false, attempt: 0))
        XCTAssertFalse(
            AppRelauncher.shouldWaitForSheet(sheetAttached: false, attempt: 99),
            "no sheet is no sheet, whatever the attempt count"
        )
    }

    /// The wait is bounded. A sheet that never closes must not strand a restore
    /// the user already picked and that is already written to disk; past the
    /// bound Blatta quits anyway and lets AppKit decide.
    func testStopsWaitingForASheetThatNeverCloses() {
        XCTAssertFalse(
            AppRelauncher.shouldWaitForSheet(sheetAttached: true, attempt: 1_000),
            "an unbounded wait would leave the app up with a restore pending"
        )
    }

    /// A restorable candidate whose filename belongs to this store must write
    /// exactly the name the launch path will look for.
    func testScheduleRestoreWritesValidNameForRestorableCandidate() {
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let storeURL = URL(fileURLWithPath: "/tmp/whatever/default.store")
        let name = "default.store.snapshot-1700000000-1.5.11+20.bak"
        let candidate = StoreCandidate(
            url: storeURL.deletingLastPathComponent().appendingPathComponent(name),
            kind: .snapshot(version: "1.5.11+20"),
            takenAt: nil,
            content: StoreContent(spaces: 2, services: 3, links: 3, spaceNames: [], serviceLabels: []),
            isDamaged: false
        )

        XCTAssertTrue(StoreRecoveryCoordinator.scheduleRestore(candidate, storeName: storeURL.lastPathComponent, defaults: defaults))
        XCTAssertEqual(
            defaults.string(forKey: DefaultsKey.pendingRestore),
            name,
            "the written key must be exactly what applyPendingRestore validates against"
        )
    }

    /// A non-restorable candidate (here: damaged) must write nothing at all —
    /// not merely return false. A partial write that later gets overwritten by
    /// coincidence would hide this bug, so the key's absence is asserted
    /// directly rather than inferred from the return value.
    func testScheduleRestoreWritesNothingForNonRestorableCandidate() {
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let storeURL = URL(fileURLWithPath: "/tmp/whatever/default.store")
        let name = "default.store.corrupt-1700000600.bak"
        let damagedCandidate = StoreCandidate(
            url: storeURL.deletingLastPathComponent().appendingPathComponent(name),
            kind: .corrupt,
            takenAt: nil,
            content: StoreContent(spaces: 1, services: 1, links: 1, spaceNames: [], serviceLabels: []),
            isDamaged: true
        )

        XCTAssertFalse(StoreRecoveryCoordinator.scheduleRestore(damagedCandidate, storeName: storeURL.lastPathComponent, defaults: defaults))
        XCTAssertNil(
            defaults.string(forKey: DefaultsKey.pendingRestore),
            "a damaged candidate must not schedule a restore"
        )
    }

    /// A candidate whose filename `validatedRestoreName` rejects (wrong store
    /// prefix here) must also write nothing, even though `isRestorable` itself
    /// only looks at damage/content/liveness and would pass it.
    func testScheduleRestoreWritesNothingForFilenameValidationFailure() {
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let storeURL = URL(fileURLWithPath: "/tmp/whatever/default.store")
        let wrongStoreName = "other.store.snapshot-1700000000-1.5.11+20.bak"
        let candidate = StoreCandidate(
            url: storeURL.deletingLastPathComponent().appendingPathComponent(wrongStoreName),
            kind: .snapshot(version: "1.5.11+20"),
            takenAt: nil,
            content: StoreContent(spaces: 2, services: 3, links: 3, spaceNames: [], serviceLabels: []),
            isDamaged: false
        )

        XCTAssertFalse(StoreRecoveryCoordinator.scheduleRestore(candidate, storeName: storeURL.lastPathComponent, defaults: defaults))
        XCTAssertNil(
            defaults.string(forKey: DefaultsKey.pendingRestore),
            "a filename that doesn't belong to this store must not schedule a restore"
        )
    }

    @MainActor
    private func makeRecoveryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    // MARK: - Picker row labels (StoreCandidate.displayTitle / displayDetail)

    static let labelDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    func labelCandidate(
        kind: StoreCandidate.Kind,
        takenAt: Date? = Date(timeIntervalSince1970: 1_700_000_000),
        content: StoreContent?,
        isDamaged: Bool = false
    ) -> StoreCandidate {
        StoreCandidate(
            url: URL(fileURLWithPath: "/tmp/labels/default.store"),
            kind: kind,
            takenAt: takenAt,
            content: content,
            isDamaged: isDamaged
        )
    }

    /// `displayTitle` is exhaustive over every `Kind`, including both shapes of
    /// `.snapshot` (a parsed version, and a name that didn't parse one).
    func testDisplayTitleCoversEveryKind() {
        let some = StoreContent(spaces: 1, services: 1, links: 1, spaceNames: [], serviceLabels: [])
        XCTAssertEqual(labelCandidate(kind: .live, content: some).displayTitle, "Your data now")
        XCTAssertEqual(labelCandidate(kind: .snapshot(version: "1.5.11+20"), content: some).displayTitle, "Backup from before 1.5.11+20")
        XCTAssertEqual(labelCandidate(kind: .snapshot(version: nil), content: some).displayTitle, "Backup from before an update")
        XCTAssertEqual(labelCandidate(kind: .prerestore, content: some).displayTitle, "Backup from an earlier restore")
        XCTAssertEqual(labelCandidate(kind: .corrupt, content: some).displayTitle, "Backup from before a repair")
        XCTAssertEqual(labelCandidate(kind: .prepick, content: some).displayTitle, "Your data before you restored a backup")
    }

    /// A backup's detail line pluralizes spaces/services independently and
    /// leads with the filename-parsed date.
    func testDisplayDetailPluralizesCountsAndLeadsWithDate() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let when = Self.labelDateFormatter.string(from: stamp)

        let singular = labelCandidate(
            kind: .snapshot(version: "1.5.11+20"),
            takenAt: stamp,
            content: StoreContent(spaces: 1, services: 1, links: 1, spaceNames: [], serviceLabels: [])
        )
        XCTAssertEqual(singular.displayDetail, "\(when) — 1 workspace, 1 service")

        let plural = labelCandidate(
            kind: .snapshot(version: "1.5.11+20"),
            takenAt: stamp,
            content: StoreContent(spaces: 3, services: 4, links: 4, spaceNames: [], serviceLabels: [])
        )
        XCTAssertEqual(plural.displayDetail, "\(when) — 3 workspaces, 4 services")
    }

    /// A backup with no parseable stamp reads "date unknown" rather than
    /// omitting the date clause outright.
    func testDisplayDetailUnknownDateFallsBackToDateUnknown() {
        let candidate = labelCandidate(
            kind: .prerestore,
            takenAt: nil,
            content: StoreContent(spaces: 2, services: 5, links: 5, spaceNames: [], serviceLabels: [])
        )
        XCTAssertEqual(candidate.displayDetail, "date unknown — 2 workspaces, 5 services")
    }

    /// A backup that is empty but readable — all-zero
    /// content — is still restorable, so its detail line must say exactly what
    /// it holds, not something that reads like "can't be read". This string is
    /// the only thing telling a user they are about to restore over good data
    /// with literally nothing, and it also pins the empty-vs-unreadable
    /// distinction: this must never collapse into the nil-content case above.
    func testDisplayDetailZeroContentBackupReadsZeroSpacesZeroServices() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let when = Self.labelDateFormatter.string(from: stamp)
        let candidate = labelCandidate(
            kind: .snapshot(version: "1.5.11+20"),
            takenAt: stamp,
            content: StoreContent(spaces: 0, services: 0, links: 0, spaceNames: [], serviceLabels: [])
        )
        XCTAssertEqual(candidate.displayDetail, "\(when) — 0 workspaces, 0 services")
    }

    /// An unreadable backup (`content == nil`, which the real candidate
    /// builder always pairs with `isDamaged == true`) reads "can't be read"
    /// with no separate damaged marker appended — the marker only applies
    /// when there IS a count to attach it to, so the two can never double up.
    func testDisplayDetailNilContentReadsCantBeReadWithoutDoubledDamagedMarker() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let when = Self.labelDateFormatter.string(from: stamp)
        let candidate = labelCandidate(kind: .corrupt, takenAt: stamp, content: nil, isDamaged: true)
        XCTAssertEqual(candidate.displayDetail, "\(when) — can't be read")
    }

    /// A damaged file that could still be read gets the marker exactly once,
    /// after the counts.
    func testDisplayDetailDamagedButReadableAddsMarkerOnce() {
        let stamp = Date(timeIntervalSince1970: 1_700_000_000)
        let when = Self.labelDateFormatter.string(from: stamp)
        let candidate = labelCandidate(
            kind: .snapshot(version: nil),
            takenAt: stamp,
            content: StoreContent(spaces: 1, services: 2, links: 2, spaceNames: [], serviceLabels: []),
            isDamaged: true
        )
        XCTAssertEqual(candidate.displayDetail, "\(when) — 1 workspace, 2 services — damaged")
    }

    /// The live row's `takenAt` is the store file's mtime,
    /// not a real snapshot stamp, and under WAL journaling that can trail the
    /// store's actual last write — showing it invites restoring the wrong
    /// copy. The live row must omit the date and show counts only, with or
    /// without a readable `content`.
    func testDisplayDetailLiveRowOmitsDateRegardlessOfContent() {
        let withContent = labelCandidate(
            kind: .live,
            takenAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: StoreContent(spaces: 3, services: 10, links: 10, spaceNames: [], serviceLabels: [])
        )
        XCTAssertEqual(withContent.displayDetail, "3 workspaces, 10 services")

        let unreadable = labelCandidate(
            kind: .live,
            takenAt: Date(timeIntervalSince1970: 1_700_000_000),
            content: nil
        )
        XCTAssertEqual(unreadable.displayDetail, "can't be read")
    }

    // MARK: - Moving the store out of the shared default path

    /// Stands in for the store another app leaves at the shared path. Modelled
    /// on the real thing: Bartender 6's store has one entity, `WidgetSettings`,
    /// and none of Blatta's tables.
    static func makeForeignStore(at url: URL) throws {
        _ = try SQLiteHelpers.run(url, """
            CREATE TABLE ZWIDGETSETTINGS (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZTITLE VARCHAR);
            """)
    }

    /// The ordinary upgrade: Blatta's own store and its backups move into the
    /// app's folder, and the old path is left clean.
    @MainActor
    func testRelocationMovesOurStoreAndItsBackupsIntoTheAppsFolder() throws {
        let (support, legacy, scoped) = try StoreSandbox.relocationDirectories(label: "relocate-ours")
        defer { try? FileManager.default.removeItem(at: support) }

        try ModelFixtures.makePopulatedStore(at: legacy, spaces: 3)
        StoreRepair.snapshot(at: legacy, stamp: "1700000000-1.0.0")

        XCTAssertEqual(StoreRelocation.resolveStoreURL(legacy: legacy, scoped: scoped), scoped)
        XCTAssertEqual(StoreRepair.spaceCount(at: scoped), 3, "the store's data must arrive intact")
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path), "the old store must not be left behind")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: scoped.path + ".snapshot-1700000000-1.0.0.bak"),
            "backups must follow the store, or the recovery picker loses sight of them"
        )
        XCTAssertNotNil(
            StoreRepair.newestRestorableSnapshot(for: scoped),
            "the moved snapshot must still be found from the new path"
        )
    }

    /// The state this whole change exists to survive: another app's store is
    /// sitting at the shared path. It must be left exactly where it is —
    /// moving or migrating it would destroy that app's data the same way it
    /// destroyed Blatta's — while Blatta's own backups still come along.
    @MainActor
    func testRelocationLeavesAnotherAppsStoreAloneAndTakesOnlyTheBackups() throws {
        let (support, legacy, scoped) = try StoreSandbox.relocationDirectories(label: "relocate-foreign")
        defer { try? FileManager.default.removeItem(at: support) }

        // Build a Blatta store, snapshot it, then replace the live file with a
        // foreign one — precisely what the collision leaves on disk.
        try ModelFixtures.makePopulatedStore(at: legacy, spaces: 4)
        StoreRepair.snapshot(at: legacy, stamp: "1700000000-1.0.0")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: legacy.path + suffix))
        }
        try Self.makeForeignStore(at: legacy)

        XCTAssertEqual(StoreRelocation.resolveStoreURL(legacy: legacy, scoped: scoped), scoped)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path), "the other app's store must be left in place")
        XCTAssertEqual(
            try SQLiteHelpers.run(legacy, "SELECT count(*) FROM sqlite_master WHERE name = 'ZWIDGETSETTINGS';")
                .trimmingCharacters(in: .whitespacesAndNewlines),
            "1",
            "the other app's schema must be untouched"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: scoped.path), "a foreign store must not be adopted as ours")
        XCTAssertNotNil(
            StoreRepair.newestRestorableSnapshot(for: scoped),
            "Blatta's own backups must still move, since they are the only way back"
        )
    }

    /// End-to-end proof that the collision is recoverable: relocate past a
    /// foreign store, then open. The user has had data, there is no live store
    /// at the new path, and the snapshot that moved with it must be restored
    /// rather than seeded over.
    @MainActor
    func testRelocatingPastAForeignStoreThenOpeningRestoresTheUsersData() throws {
        let (support, legacy, scoped) = try StoreSandbox.relocationDirectories(label: "relocate-recover")
        defer { try? FileManager.default.removeItem(at: support) }
        let suite = "blatta-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        try ModelFixtures.makePopulatedStore(at: legacy, spaces: 4)
        StoreRepair.snapshot(at: legacy, stamp: "1700000000-1.0.0")
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: legacy.path + suffix))
        }
        try Self.makeForeignStore(at: legacy)
        defaults.set(true, forKey: DefaultsKey.hasEverHadData)

        let url = StoreRelocation.resolveStoreURL(legacy: legacy, scoped: scoped)
        let config = ModelConfiguration(schema: Self.storeSchema, url: url)
        let (container, outcome) = StoreLoader.load(schema: Self.storeSchema, config: config, defaults: defaults)

        guard case .restoredFromSnapshot = outcome else {
            return XCTFail("expected .restoredFromSnapshot, got \(outcome)")
        }
        XCTAssertEqual(
            try container.mainContext.fetchCount(FetchDescriptor<Space>()), 4,
            "the spaces the other app wiped must come back from the snapshot"
        )
    }

    /// Once moved, the old path is never read again. An older build of Blatta
    /// run in between could leave a store there, and importing it would
    /// overwrite newer data with older.
    @MainActor
    func testRelocationIgnoresTheOldPathOnceTheAppsFolderHasAStore() throws {
        let (support, legacy, scoped) = try StoreSandbox.relocationDirectories(label: "relocate-idempotent")
        defer { try? FileManager.default.removeItem(at: support) }

        try FileManager.default.createDirectory(at: scoped.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ModelFixtures.makePopulatedStore(at: scoped, spaces: 1)
        try ModelFixtures.makePopulatedStore(at: legacy, spaces: 9)

        XCTAssertEqual(StoreRelocation.resolveStoreURL(legacy: legacy, scoped: scoped), scoped)
        XCTAssertEqual(StoreRepair.spaceCount(at: scoped), 1, "the store already in place must win")
        XCTAssertEqual(StoreRepair.spaceCount(at: legacy), 9, "and the old path must be left alone, not consumed")
    }

    // MARK: - Optional link ends

    /// 1.5.13 (the shape Blatta inherited) opens at the current shape with its
    /// links intact, and both ends of every link still resolve.
    ///
    /// This is the stage that relaxes `SpaceServiceLink.space` and `.service` to
    /// optional. Dropping a constraint should carry every row across untouched,
    /// and the assertions below are about the ends specifically, because a
    /// migration that quietly nulled them would leave a store full of links
    /// pointing at nothing.
    @MainActor
    func testMigratesFrom1_5_13PreservingLinkEnds() throws {
        let dir = FileManager.default.temporaryDirectory
            .appending(path: "blatta-migr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "default.store")

        let serviceID = UUID(), spaceID = UUID(), linkID = UUID()

        try autoreleasepool {
            let schema = Schema(versionedSchema: BlattaSchemaV1_5_13.self)
            let config = ModelConfiguration(schema: schema, url: url)
            let container = try ModelContainer(for: schema, configurations: [config])
            let ctx = container.mainContext
            let space = BlattaSchemaV1_5_13.Space(id: spaceID, name: "Work", emoji: "🏢", sortOrder: 3)
            let service = BlattaSchemaV1_5_13.ServiceInstance(id: serviceID, label: "Slack", url: "https://slack.com")
            service.hibernationPolicyRaw = "never"
            service.hibernateAfterMinutes = 42
            let link = BlattaSchemaV1_5_13.SpaceServiceLink(id: linkID, sortOrder: 7, space: space, service: service)
            ctx.insert(space); ctx.insert(service); ctx.insert(link)
            try ctx.save()
        }

        let schema = Schema(versionedSchema: BlattaSchemaVCurrent.self)
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(
            for: schema,
            migrationPlan: BlattaMigrationPlan.self,
            configurations: [config]
        )
        let ctx = container.mainContext

        let link = try XCTUnwrap(try ctx.fetch(FetchDescriptor<SpaceServiceLink>()).first)
        XCTAssertEqual(link.id, linkID)
        XCTAssertEqual(link.sortOrder, 7)
        XCTAssertEqual(link.space?.id, spaceID, "the migration must not drop the link's space")
        XCTAssertEqual(link.service?.id, serviceID, "the migration must not drop the link's service")
        XCTAssertNotNil(link.liveEnds, "both ends must still resolve after the migration")

        let service = try XCTUnwrap(try ctx.fetch(FetchDescriptor<ServiceInstance>()).first)
        XCTAssertEqual(service.hibernationPolicyRaw, "never")
        XCTAssertEqual(service.hibernateAfterMinutes, 42)
        XCTAssertEqual(service.spaceLinks.count, 1, "the inverse must survive too")
    }

    /// Deleting either end of a link must not trap, on any OS.
    ///
    /// `Space.serviceLinks` and `ServiceInstance.spaceLinks` both cascade, so a
    /// delete has to clear the link's reference first. While those references
    /// were non-optional there was nothing to clear them to, and macOS 15
    /// trapped —
    ///
    ///   Cannot remove Blatta.Space from relationship space on
    ///   Blatta.SpaceServiceLink because an appropriate default value is not
    ///   configured
    ///
    /// — so deleting a workspace killed the app for anyone below macOS 26. This
    /// covers both ends and both orders, since the trap fired on whichever end
    /// went first.
    @MainActor
    func testDeletingEitherEndOfALinkNeverTraps() throws {
        let schema = Self.storeSchema

        // Hold each container: `mainContext` does not keep its container alive,
        // and a released container leaves the context pointing at nothing.
        var containers: [ModelContainer] = []
        func freshContext() throws -> ModelContext {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            let container = try ModelContainer(for: schema, configurations: [config])
            containers.append(container)
            return container.mainContext
        }

        // Workspace first, then the service it orphaned — AppState.deleteSpace.
        let a = try freshContext()
        let spaceA = Space(name: "A", emoji: "🅰️", sortOrder: 0)
        let serviceA = ServiceInstance(label: "a", url: "https://a.example", catalogEntryID: "a")
        a.insert(spaceA); a.insert(serviceA)
        a.insert(SpaceServiceLink(sortOrder: 0, space: spaceA, service: serviceA))
        try a.save()
        a.delete(spaceA)
        try a.save()
        XCTAssertTrue(
            try a.fetch(FetchDescriptor<SpaceServiceLink>()).isEmpty,
            "the workspace's cascade must take the link"
        )
        a.delete(serviceA)
        try a.save()

        // Service first, then the workspace — the rail's deleteService.
        let b = try freshContext()
        let spaceB = Space(name: "B", emoji: "🅱️", sortOrder: 0)
        let serviceB = ServiceInstance(label: "b", url: "https://b.example", catalogEntryID: "b")
        b.insert(spaceB); b.insert(serviceB)
        b.insert(SpaceServiceLink(sortOrder: 0, space: spaceB, service: serviceB))
        try b.save()
        b.delete(serviceB)
        try b.save()
        XCTAssertTrue(
            try b.fetch(FetchDescriptor<SpaceServiceLink>()).isEmpty,
            "the service's cascade must take the link"
        )

        // Both in one batch, which is the shape that trapped first.
        let c = try freshContext()
        let spaceC = Space(name: "C", emoji: "🇨", sortOrder: 0)
        let serviceC = ServiceInstance(label: "c", url: "https://c.example", catalogEntryID: "c")
        c.insert(spaceC); c.insert(serviceC)
        c.insert(SpaceServiceLink(sortOrder: 0, space: spaceC, service: serviceC))
        try c.save()
        c.delete(serviceC)
        c.delete(spaceC)
        try c.save()
        XCTAssertTrue(try c.fetch(FetchDescriptor<SpaceServiceLink>()).isEmpty)

        XCTAssertEqual(containers.count, 3)
    }
}
