import Foundation
import SQLite3
import SwiftData
@testable import Atoll

enum ModelFixtures {
    enum FixtureError: Error, CustomStringConvertible {
        case storeNeverSettled(String, String)

        var description: String {
            switch self {
            case let .storeNeverSettled(name, detail):
                return "Fixture store \(name) never became available: \(detail)"
            }
        }
    }

    static var storeSchema: Schema {
        Schema(versionedSchema: AtollSchemaVCurrent.self)
    }

    static func service(label: String, catalogID: String?) -> ServiceInstance {
        ServiceInstance(label: label, url: "https://example.com", catalogEntryID: catalogID)
    }

    static func groupingContainer() throws -> ModelContainer {
        try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    @discardableResult
    static func link(
        _ service: ServiceInstance,
        to space: Space,
        sortOrder: Int,
        in context: ModelContext
    ) -> SpaceServiceLink {
        let link = SpaceServiceLink(sortOrder: sortOrder, space: space, service: service)
        context.insert(link)
        return link
    }

    /// Creates a populated store and waits until raw SQLite can use it safely.
    @MainActor
    static func makePopulatedStore(at url: URL, spaces: Int) throws {
        try writeFixture(at: url, spaces: spaces)
        try settleStore(at: url)
    }

    @MainActor
    private static func writeFixture(at url: URL, spaces: Int) throws {
        let schema = storeSchema
        let config = ModelConfiguration(schema: schema, url: url)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = container.mainContext
        for index in 0..<spaces {
            context.insert(Space(name: "S\(index)", emoji: "🏠", sortOrder: index))
        }
        try context.save()
    }

    /// Waits for SwiftData to release the store, then folds its WAL into it.
    private static func settleStore(at url: URL, timeout: TimeInterval = 10) throws {
        let deadline = Date().addingTimeInterval(timeout)
        var lastDetail = "not attempted"

        repeat {
            var database: OpaquePointer?
            if sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
               let database {
                sqlite3_busy_timeout(database, 250)
                let lockResult = sqlite3_exec(database, "BEGIN EXCLUSIVE; COMMIT;", nil, nil, nil)
                if lockResult == SQLITE_OK {
                    sqlite3_exec(database, "PRAGMA wal_checkpoint(TRUNCATE);", nil, nil, nil)
                    sqlite3_close(database)
                    return
                }
                lastDetail = "BEGIN EXCLUSIVE returned \(lockResult)"
                sqlite3_close(database)
            } else {
                lastDetail = "Could not open the store for writing"
                if let database {
                    sqlite3_close(database)
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline

        throw FixtureError.storeNeverSettled(url.lastPathComponent, lastDetail)
    }

    static func insertSpaces(_ url: URL, count: Int) throws {
        let entity = try SQLiteHelpers.run(url, "SELECT Z_ENT FROM ZSPACE LIMIT 1;")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let entityID = entity.isEmpty ? "1" : entity
        for index in 0..<count {
            _ = try SQLiteHelpers.run(url, """
                INSERT INTO ZSPACE (Z_PK, Z_ENT, Z_OPT, ZNAME, ZEMOJI, ZSORTORDER)
                VALUES (\(1000 + index), \(entityID), 1, 'S\(index)', '🏠', \(index));
                """)
        }
    }

    static func insertSeedShape(_ url: URL) throws {
        let spaceEntity = try SQLiteHelpers.run(
            url,
            "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Space';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let serviceEntity = try SQLiteHelpers.run(
            url,
            "SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'ServiceInstance';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)

        for (index, entry) in DefaultSeed.spaces.enumerated() {
            _ = try SQLiteHelpers.run(url, """
                INSERT INTO ZSPACE (Z_PK, Z_ENT, Z_OPT, ZNAME, ZEMOJI, ZSORTORDER)
                VALUES (\(2000 + index), \(spaceEntity.isEmpty ? "1" : spaceEntity), 1, '\(entry.name)', '\(entry.emoji)', \(index));
                """)
        }
        for (index, label) in DefaultSeed.allServiceLabels.enumerated() {
            _ = try SQLiteHelpers.run(url, """
                INSERT INTO ZSERVICEINSTANCE (Z_PK, Z_ENT, Z_OPT, ZLABEL, ZURL)
                VALUES (\(3000 + index), \(serviceEntity.isEmpty ? "2" : serviceEntity), 1, '\(label)', 'https://example.com');
                """)
        }
    }

    static func copyStoreTriple(from source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        for suffix in ["", "-wal", "-shm"] {
            let sourceFile = URL(fileURLWithPath: source.path + suffix)
            guard fileManager.fileExists(atPath: sourceFile.path) else { continue }
            let destinationFile = URL(fileURLWithPath: destination.path + suffix)
            try fileManager.copyItem(at: sourceFile, to: destinationFile)
        }
    }
}
