import Foundation
import XCTest
@testable import PaguroCore

final class BrowserExtensionLibraryTests: XCTestCase {
    func testOldLibraryLoadsWithStandardIdentityAndNewVersionKeepsProfiles() throws {
        let account = UUID()
        let library = BrowserExtensionLibrary(records: [record(account)])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        object["version"] = 1
        object.removeValue(forKey: "profiles")
        let restored = try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(restored, library)
        let selected = BrowserExtensionLibrary(records: library.records, profiles: [account.uuidString: .firefox])
        XCTAssertEqual(try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONEncoder().encode(selected)), selected)
    }

    func testInvalidProfilesAndSchemaAreRejected() throws {
        let account = UUID()
        let valid = BrowserExtensionLibrary(records: [record(account)], profiles: [account.uuidString: .firefox])
        let data = try JSONEncoder().encode(valid)
        for change: [String: Any] in [["version": 4], ["version": 1],
            ["profiles": [account.uuidString: "unknown"]], ["profiles": ["invalid": "firefox"]],
            ["profiles": [UUID().uuidString: "firefox"]], ["profiles": [account.uuidString: "standard"]]] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object.merge(change) { _, new in new }
            XCTAssertThrowsError(try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONSerialization.data(withJSONObject: object)))
        }
    }

    func testRemovingLastAssignmentRemovesItsProfile() {
        let account = UUID()
        var library = BrowserExtensionLibrary(records: [record(account)], profiles: [account.uuidString: .firefox])
        library.records[0].serviceIDs = []
        XCTAssertFalse(library.isValid)
        library.removeUnassignedProfiles()
        XCTAssertTrue(library.isValid)
        XCTAssertTrue(library.profiles.isEmpty)
    }

    func testProfileUsesSameGeneratedIdentityAndPreservesStandardPreference() {
        XCTAssertEqual(ExtensionRuntimeProfile.firefox.applicationNameForUserAgent, "Firefox/143.0")
        XCTAssertNil(ExtensionRuntimeProfile.firefox.customUserAgent(defaultValue: "Mobile preference"))
        XCTAssertNil(ExtensionRuntimeProfile.standard.applicationNameForUserAgent)
        XCTAssertEqual(ExtensionRuntimeProfile.standard.customUserAgent(defaultValue: "Mobile preference"), "Mobile preference")
    }

    private func record(_ account: UUID) -> BrowserExtensionRecord {
        BrowserExtensionRecord(slug: "probe", name: "Probe", version: "1", sha256: String(repeating: "a", count: 64), permissions: [], serviceIDs: [account])
    }
}
