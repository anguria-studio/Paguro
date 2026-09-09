import XCTest
import SwiftData
@testable import Paguro

final class WebsiteDataReclaimerTests: XCTestCase {
    func testWebsiteDataStoreDirectoryIsScopedToBundle() {
        let directory = WebsiteDataReclaimer.websiteDataStoreDirectory(
            bundleID: "com.example.App"
        )

        XCTAssertEqual(directory?.lastPathComponent, "WebsiteDataStore")
        XCTAssertEqual(directory?.deletingLastPathComponent().lastPathComponent, "com.example.App")
        XCTAssertNil(WebsiteDataReclaimer.websiteDataStoreDirectory(bundleID: nil))
        XCTAssertNil(WebsiteDataReclaimer.websiteDataStoreDirectory(bundleID: ""))
    }

    @MainActor
    func testCleanupRetriesAndRemovesOnlySuccessfulTombstone() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let identifier = UUID()
        var attempts = 0
        let reclaimer = WebsiteDataReclaimer(
            context: fixture.container.mainContext,
            dataStoreManager: DataStoreManager(),
            isSafeToReclaim: true,
            defaults: fixture.defaults,
            backoff: [.zero, .zero],
            removeDataStore: { received in
                XCTAssertEqual(received, identifier)
                attempts += 1
                if attempts == 1 { throw RemovalError.busy }
            }
        )
        reclaimer.markOrphaned(identifier)

        reclaimer.cleanUpOrphanedDataStores()
        await reclaimer.waitForPendingRemovals()

        XCTAssertEqual(attempts, 2)
        XCTAssertNil(
            fixture.defaults.array(forKey: DefaultsKey.orphanedDataStoreIdentifiers)
        )
        reclaimer.shutdown()
    }

    @MainActor
    func testOrphanReapUsesLiveLinksAndTombstonesAfterSave() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let context = fixture.container.mainContext
        let space = Space(name: "Work", emoji: "💼")
        let linked = ServiceInstance(label: "Linked", url: "https://linked.example")
        let orphan = ServiceInstance(label: "Orphan", url: "https://orphan.example")
        let link = SpaceServiceLink(sortOrder: 0, space: space, service: linked)
        context.insert(space)
        context.insert(linked)
        context.insert(orphan)
        context.insert(link)
        try context.save()
        let orphanDataStoreIdentifier = orphan.dataStoreIdentifier

        let reclaimer = WebsiteDataReclaimer(
            context: context,
            dataStoreManager: DataStoreManager(),
            isSafeToReclaim: true,
            defaults: fixture.defaults,
            backoff: [.seconds(60)],
            removeDataStore: { _ in XCTFail("shutdown should cancel before removal") }
        )

        reclaimer.reapOrphanedServices()

        XCTAssertEqual(
            Set(try context.fetch(FetchDescriptor<ServiceInstance>()).map(\.id)),
            [linked.id]
        )
        XCTAssertEqual(
            fixture.defaults.stringArray(
                forKey: DefaultsKey.orphanedDataStoreIdentifiers
            ),
            [orphanDataStoreIdentifier.uuidString]
        )
        reclaimer.shutdown()
    }

    @MainActor
    func testUnsafeLaunchDoesNotReapAnOrphan() throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let context = fixture.container.mainContext
        let orphan = ServiceInstance(label: "Keep", url: "https://keep.example")
        context.insert(orphan)
        try context.save()

        let reclaimer = WebsiteDataReclaimer(
            context: context,
            dataStoreManager: DataStoreManager(),
            isSafeToReclaim: false,
            defaults: fixture.defaults,
            backoff: [.zero],
            removeDataStore: { _ in XCTFail("an unsafe launch must not remove data") }
        )

        reclaimer.reapOrphanedServices()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<ServiceInstance>()), 1)
        XCTAssertNil(
            fixture.defaults.array(forKey: DefaultsKey.orphanedDataStoreIdentifiers)
        )
        reclaimer.shutdown()
    }

    @MainActor
    private func makeFixture() throws -> (
        container: ModelContainer,
        defaults: UserDefaults,
        suite: String
    ) {
        let container = try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let suite = "paguro-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (container, defaults, suite)
    }

    private enum RemovalError: Error {
        case busy
    }
}
