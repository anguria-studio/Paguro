import Foundation
import XCTest
@testable import PaguroCore

final class ExtensionUpdatePolicyTests: XCTestCase {
    func testFirefoxVersionOrderingHandlesNumericPartsAndPrereleases() {
        let ordered = ["1.-1", "1", "1.1a", "1.1aa", "1.1ab", "1.1b", "1.1c", "1.1pre",
                       "1.1pre1a", "1.1pre1aa", "1.1pre1b", "1.1pre1", "1.1pre2", "1.1pre10", "1.1.-1", "1.1", "1.10", "1.*", "1.*.1", "2.0"]
        for pair in zip(ordered, ordered.dropFirst()) {
            XCTAssertEqual(FirefoxExtensionVersion.compare(pair.0, pair.1), .orderedAscending, "\(pair)")
            XCTAssertEqual(FirefoxExtensionVersion.compare(pair.1, pair.0), .orderedDescending)
        }
        for pair in [("1", "1.0.0"), ("1.1", "1.1.00"), ("1.0+", "1.1pre"), ("1.1pre", "1.1pre0")] {
            XCTAssertEqual(FirefoxExtensionVersion.compare(pair.0, pair.1), .orderedSame)
        }
        for invalid in ["", "1\n2", "1 2", "一", String(repeating: "1", count: 129), "2147483648", "2147483647+", "1.-"] {
            XCTAssertNil(FirefoxExtensionVersion.compare(invalid, "1"))
        }
    }

    func testUpdatesRequireMatchingIdentityChangedBytesAndAHigherVersion() {
        let record = record()
        XCTAssertTrue(ExtensionUpdatePolicy.isUpdate(release("2"), for: record))
        for version in ["1", "1.0.0", "0.9", "1pre1"] {
            XCTAssertFalse(ExtensionUpdatePolicy.isUpdate(release(version), for: record))
        }
        XCTAssertFalse(ExtensionUpdatePolicy.isUpdate(release("2", slug: "other"), for: record))
        XCTAssertFalse(ExtensionUpdatePolicy.isUpdate(release("2", hash: record.sha256), for: record))
    }

    func testDailyCooldownHandlesFailuresClockChangesAndReplacementPackages() {
        let now = Date(timeIntervalSince1970: 10_000_000)
        let record = record()
        let entry = ExtensionUpdateCheck(installedSHA256: record.sha256, checkedAt: now, available: nil)
        XCTAssertTrue(ExtensionUpdatePolicy.shouldCheck(record, entry: nil, now: now))
        XCTAssertFalse(ExtensionUpdatePolicy.shouldCheck(record, entry: entry, now: now.addingTimeInterval(86_399)))
        XCTAssertTrue(ExtensionUpdatePolicy.shouldCheck(record, entry: entry, now: now.addingTimeInterval(86_400)))
        XCTAssertTrue(ExtensionUpdatePolicy.shouldCheck(record, entry: entry, now: now.addingTimeInterval(-1)))
        let old = ExtensionUpdateCheck(installedSHA256: String(repeating: "c", count: 64), checkedAt: now, available: nil)
        XCTAssertTrue(ExtensionUpdatePolicy.shouldCheck(record, entry: old, now: now))
    }

    func testStateValidationRoundTripAndPruning() throws {
        let record = record()
        var state = ExtensionUpdateChecks()
        state.entries[record.id.uuidString] = ExtensionUpdateCheck(installedSHA256: record.sha256,
            checkedAt: Date(timeIntervalSince1970: 1), available: release("2"))
        XCTAssertTrue(state.isValid)
        XCTAssertEqual(try JSONDecoder().decode(ExtensionUpdateChecks.self, from: JSONEncoder().encode(state)), state)
        state.prune(for: [])
        XCTAssertTrue(state.entries.isEmpty)
        state.version = 2
        XCTAssertFalse(state.isValid)
        state.version = 1
        state.entries["invalid"] = ExtensionUpdateCheck(installedSHA256: record.sha256, checkedAt: .now, available: nil)
        XCTAssertFalse(state.isValid)
        XCTAssertFalse(release("2", hash: "bad").isValid)
    }

    private func record() -> BrowserExtensionRecord {
        BrowserExtensionRecord(slug: "probe", name: "Probe", version: "1", sha256: String(repeating: "a", count: 64), permissions: [], serviceIDs: [UUID()])
    }
    private func release(_ version: String, slug: String = "probe", hash: String = String(repeating: "b", count: 64)) -> FirefoxAddonRelease {
        FirefoxAddonRelease(slug: slug, version: version, sha256: hash,
            downloadURL: URL(string: "https://addons.mozilla.org/file.xpi")!, size: 123)
    }
}
