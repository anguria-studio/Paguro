#if !APP_STORE
import Foundation
import PaguroCore
import WebKit
import XCTest
@testable import Paguro

@MainActor
final class BrowserExtensionUpdateTests: XCTestCase {
    func testMetadataOnlyCheckPersistsAndReviewStillRequiresApproval() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        let original = try XCTUnwrap(fixture.manager.records.first)
        var reloads = 0
        fixture.manager.onAssignmentsChanged = { _ in reloads += 1 }
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        XCTAssertEqual(fixture.manager.availableUpdates[original.id]?.version, "2.0")
        XCTAssertEqual(fixture.manager.records, [original])
        XCTAssertNil(fixture.manager.preview)
        XCTAssertEqual(reloads, 0)
        var counts = await fixture.source.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertEqual(counts.1, 0, "Background discovery must not download an executable package")
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertEqual(restored.availableUpdates[original.id]?.version, "2.0")
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        counts = await fixture.source.counts()
        XCTAssertEqual(counts.0, 1, "The daily cooldown must survive successful checks")
        fixture.manager.reviewUpdate(original.id)
        for _ in 0..<200 {
            if !fixture.manager.isBusy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertEqual(fixture.manager.preview?.package.version, "2.0")
        XCTAssertEqual(fixture.manager.records, [original])
        XCTAssertEqual(reloads, 0)
        counts = await fixture.source.counts()
        XCTAssertEqual(counts.1, 1)
        XCTAssertTrue(fixture.manager.installPreview(serviceIDs: original.serviceIDs))
        XCTAssertEqual(fixture.manager.records.first?.id, original.id)
        XCTAssertEqual(fixture.manager.records.first?.version, "2.0")
        XCTAssertEqual(fixture.manager.records.first?.serviceIDs, original.serviceIDs)
        XCTAssertTrue(fixture.manager.availableUpdates.isEmpty)
        XCTAssertEqual(reloads, 1)
    }

    func testCooldownSurvivesRestartAndAllowsTheNextDailyCheck() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        let source = fixture.source
        let restored = BrowserExtensionManager(directory: fixture.directory, fetchRelease: { try await source.latest($0) })
        defer { restored.shutdown() }
        try await restored.restore()
        restored.checkForUpdates()
        try await wait(restored)
        var counts = await source.counts()
        XCTAssertEqual(counts.0, 1)
        let last = try XCTUnwrap(restored.updateChecks.entries.values.first?.checkedAt)
        restored.now = { last.addingTimeInterval(ExtensionUpdatePolicy.checkInterval) }
        restored.checkForUpdates()
        try await wait(restored)
        counts = await source.counts()
        XCTAssertEqual(counts.0, 2)
    }

    func testFailureKeepsKnownUpdateAndThrottlesRetries() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        let available = fixture.manager.availableUpdates
        await fixture.source.fail()
        fixture.manager.checkForUpdates(force: true)
        try await wait(fixture.manager)
        XCTAssertEqual(fixture.manager.availableUpdates, available)
        XCTAssertFalse(fixture.manager.updateCheckErrors.isEmpty)
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        let counts = await fixture.source.counts()
        XCTAssertEqual(counts.0, 2)
    }

    func testLockAndShutdownRejectLateNetworkResults() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        for stop in [false, true] {
            let fixture = try await makeFixture()
            defer { fixture.close() }
            await fixture.source.pause()
            fixture.manager.checkForUpdates()
            for _ in 0..<200 {
                if await fixture.source.counts().0 == 1 { break }
                try await Task.sleep(for: .milliseconds(5))
            }
            if stop { fixture.manager.shutdown() } else { fixture.manager.setLocked(true) }
            await fixture.source.resume()
            try await Task.sleep(for: .milliseconds(50))
            XCTAssertTrue(fixture.manager.availableUpdates.isEmpty)
            XCTAssertFalse(fixture.manager.isCheckingUpdates)
            XCTAssertNil(fixture.manager.updateWork)
            XCTAssertNil(fixture.manager.updateMonitor)
        }
    }

    func testRemovalRejectsAnOutstandingUpdateAndPrunesCache() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        await fixture.source.pause()
        fixture.manager.checkForUpdates()
        for _ in 0..<200 {
            if await fixture.source.counts().0 == 1 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        fixture.manager.remove(try XCTUnwrap(fixture.manager.records.first?.id))
        await fixture.source.resume()
        try await wait(fixture.manager)
        XCTAssertTrue(fixture.manager.records.isEmpty)
        XCTAssertTrue(fixture.manager.availableUpdates.isEmpty)
        XCTAssertTrue(fixture.manager.updateChecks.entries.isEmpty)
    }

    func testAutomaticChecksStartAfterRestoreAndCanBeDisabledDurably() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        fixture.manager.start()
        for _ in 0..<300 {
            if await fixture.source.counts().0 == 1, !fixture.manager.isBusy, !fixture.manager.isCheckingUpdates { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let counts = await fixture.source.counts()
        XCTAssertEqual(counts.0, 1)
        XCTAssertNotNil(fixture.manager.updateMonitor)
        fixture.manager.setAutomaticUpdateChecks(false)
        XCTAssertNil(fixture.manager.updateMonitor)
        XCTAssertFalse(fixture.manager.automaticUpdateChecksEnabled)
        fixture.manager.updateChecks.entries = [:]
        fixture.manager.refreshUpdateChecks()
        XCTAssertNil(fixture.manager.updateWork, "Library changes must respect disabled automatic checks")
        fixture.manager.checkForUpdates(force: true)
        try await wait(fixture.manager)
        let manualCounts = await fixture.source.counts()
        XCTAssertEqual(manualCounts.0, 2, "An explicit check remains available when automatic checks are disabled")
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertFalse(restored.automaticUpdateChecksEnabled)
        XCTAssertNotNil(restored.availableUpdates.values.first)
    }

    func testCorruptUpdateStatePausesChecksWithoutBlockingInstalledPackages() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        try Data("invalid".utf8).write(to: fixture.manager.updateStateURL)
        let restored = BrowserExtensionManager(directory: fixture.directory)
        defer { restored.shutdown() }
        try await restored.restore()
        XCTAssertEqual(restored.records, fixture.manager.records)
        XCTAssertTrue(restored.failures.isEmpty)
        XCTAssertFalse(restored.automaticUpdateChecksEnabled)
        XCTAssertNotNil(restored.errorMessage)
    }

    func testDiskFailureDoesNotRepeatChecksInMemoryOrApplyUnsavedPreferences() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let fixture = try await makeFixture()
        defer { fixture.close() }
        try FileManager.default.removeItem(at: fixture.manager.updateStateURL)
        try FileManager.default.createDirectory(at: fixture.manager.updateStateURL, withIntermediateDirectories: false)
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        XCTAssertFalse(fixture.manager.updateCheckErrors.isEmpty)
        fixture.manager.checkForUpdates()
        try await wait(fixture.manager)
        let counts = await fixture.source.counts()
        XCTAssertEqual(counts.0, 1)
        fixture.manager.setAutomaticUpdateChecks(false)
        XCTAssertTrue(fixture.manager.automaticUpdateChecksEnabled, "A failed preference save must not apply the toggle")
    }

    @available(macOS 15.4, *)
    private func wait(_ manager: BrowserExtensionManager) async throws {
        for _ in 0..<300 {
            if !manager.isCheckingUpdates { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The bounded update check did not finish")
    }

    @available(macOS 15.4, *)
    private func makeFixture() async throws -> Fixture {
        let original = try BrowserExtensionFixture.package()
        let update = try BrowserExtensionFixture.package(version: "2.0")
        let source = UpdateSource(package: update)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let manager = BrowserExtensionManager(directory: directory, fetchRelease: { try await source.latest($0) },
            fetchPackage: { try await source.download($0) })
        try await manager.restore()
        let service = UUID()
        manager.assignableServiceIDs = { [service] }
        try await manager.prepare(original)
        XCTAssertTrue(manager.installPreview(serviceIDs: [service]))
        return Fixture(manager: manager, source: source, directory: directory)
    }

    @available(macOS 15.4, *)
    @MainActor private struct Fixture {
        let manager: BrowserExtensionManager
        let source: UpdateSource
        let directory: URL
        func close() { manager.shutdown(); try? FileManager.default.removeItem(at: directory) }
    }
}

private actor UpdateSource {
    let package: FirefoxAddonPackage
    var checks = 0
    var downloads = 0
    var failed = false
    var paused = false
    var pending: CheckedContinuation<Void, Never>?
    init(package: FirefoxAddonPackage) { self.package = package }
    func counts() -> (Int, Int) { (checks, downloads) }
    func fail() { failed = true }
    func pause() { paused = true }
    func resume() { paused = false; pending?.resume(); pending = nil }
    func latest(_ source: FirefoxAddonSource) async throws -> FirefoxAddonRelease {
        checks += 1
        if paused { await withCheckedContinuation { pending = $0 } }
        if failed { throw URLError(.notConnectedToInternet) }
        return FirefoxAddonRelease(slug: package.slug, version: package.version, sha256: package.sha256,
            downloadURL: URL(string: "https://addons.mozilla.org/update.xpi")!, size: package.data.count)
    }
    func download(_ source: FirefoxAddonSource) -> FirefoxAddonPackage { downloads += 1; return package }
}
#endif
