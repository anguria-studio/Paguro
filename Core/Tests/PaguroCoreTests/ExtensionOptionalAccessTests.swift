import Foundation
import XCTest
@testable import PaguroCore

final class ExtensionOptionalAccessTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)

    func testChoicesReplaceOppositeDecisionsAndRoundTrip() throws {
        var access = ExtensionOptionalAccess(packageSHA256: digest)
        access.record(permissions: ["clipboardWrite"], origins: ["https://optional.example/*"], allowed: true)
        XCTAssertTrue(access.isValid)
        access.record(permissions: ["clipboardWrite"], origins: [], allowed: false)
        XCTAssertTrue(access.permissions.isEmpty)
        XCTAssertEqual(access.deniedPermissions, ["clipboardWrite"])
        XCTAssertEqual(try JSONDecoder().decode(ExtensionOptionalAccess.self, from: JSONEncoder().encode(access)), access)
    }

    func testInvalidAndConflictingChoicesAreRejected() {
        var access = ExtensionOptionalAccess(packageSHA256: digest)
        access.permissions = ["storage"]
        access.deniedPermissions = ["storage"]
        XCTAssertFalse(access.isValid)
        for value in ["", "bad\npermission", String(repeating: "a", count: 2_049)] {
            access.permissions = [value]
            access.deniedPermissions = []
            XCTAssertFalse(access.isValid)
        }
        access.permissions = Set((0...1_024).map { "api\($0)" })
        XCTAssertFalse(access.isValid)
    }

    func testOnlyAssignedAccountsAndTheSamePackageCanKeepChoices() throws {
        let account = UUID(), id = UUID()
        let record = BrowserExtensionRecord(id: id, slug: "probe", name: "Probe", version: "1", sha256: digest, permissions: [], serviceIDs: [account])
        var access = ExtensionOptionalAccess(packageSHA256: digest)
        access.origins = ["https://optional.example/*"]
        let key = id.uuidString, service = account.uuidString
        var library = BrowserExtensionLibrary(records: [record], optionalAccess: [key: [service: access]])
        XCTAssertTrue(library.isValid)
        XCTAssertEqual(try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONEncoder().encode(library)), library)
        library.records[0].serviceIDs = []
        XCTAssertFalse(library.isValid)
        library.removeUnassignedAccess()
        XCTAssertTrue(library.optionalAccess.isEmpty)
        library.records = [record]
        var changed = ExtensionOptionalAccess(packageSHA256: String(repeating: "b", count: 64))
        changed.permissions = ["clipboardWrite"]
        library.optionalAccess = [key: [service: changed]]
        XCTAssertFalse(library.isValid)
        library.removeUnassignedAccess()
        XCTAssertTrue(library.optionalAccess.isEmpty)
        library.optionalAccess = [key: [UUID().uuidString: access]]
        XCTAssertFalse(library.isValid)
        library.optionalAccess = ["invalid": [service: access]]
        XCTAssertFalse(library.isValid)
    }

    func testOldSchemasMigrateWithoutOptionalAccessAndRejectInjectedChoices() throws {
        let account = UUID()
        let record = BrowserExtensionRecord(slug: "probe", name: "Probe", version: "1", sha256: digest, permissions: [], serviceIDs: [account])
        var access = ExtensionOptionalAccess(packageSHA256: digest)
        access.permissions = ["clipboardWrite"]
        let library = BrowserExtensionLibrary(records: [record], optionalAccess: [record.id.uuidString: [account.uuidString: access]])
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(library)) as? [String: Any])
        for version in [1, 2] {
            object["version"] = version
            XCTAssertThrowsError(try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONSerialization.data(withJSONObject: object)))
        }
        object.removeValue(forKey: "optionalAccess")
        let old = try JSONDecoder().decode(BrowserExtensionLibrary.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertTrue(old.optionalAccess.isEmpty)
    }
}
