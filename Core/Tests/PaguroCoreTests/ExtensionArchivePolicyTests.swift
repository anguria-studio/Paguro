import XCTest
@testable import PaguroCore

final class ExtensionArchivePolicyTests: XCTestCase {
    func testMinimalArchiveAndDirectoriesPass() throws {
        try ExtensionArchivePolicy.validate(archive(["manifest.json", "icons/", "icons/icon.png"]))
    }

    func testTraversalAbsolutePathsAndDuplicateNamesAreRejected() {
        for path in ["../escape", "/absolute", "folder/../../escape", "folder\\escape",
                     "C:/escape", "folder//escape", "./escape", "bad\0name", "MANIFEST.JSON"] {
            XCTAssertThrowsError(try ExtensionArchivePolicy.validate(archive(["manifest.json", path])), path)
        }
    }

    func testLinksEncryptionAndExpansionBombAreRejected() {
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(archive(["manifest.json"], mode: 0o120777)))
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(archive(["manifest.json"], flags: 1)))
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(archive(["manifest.json"], expanded: 257 * 1_024 * 1_024)))
    }

    func testTruncatedAndMalformedInputsNeverPass() {
        let valid = archive(["manifest.json"])
        for size in 0..<valid.count {
            XCTAssertThrowsError(try ExtensionArchivePolicy.validate(valid.prefix(size)), "length \(size)")
        }
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(archive(["other.json"])))
        var mismatch = valid
        mismatch[30] = 88
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(mismatch))
        var badOffset = valid
        let central = 30 + "manifest.json".utf8.count
        for i in (central + 42)..<(central + 46) { badOffset[i] = 255 }
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(badOffset))
        XCTAssertThrowsError(try ExtensionArchivePolicy.validate(valid + Data([0])))
    }

    private func archive(_ names: [String], mode: Int = 0o100644, flags: Int = 0, expanded: Int = 0) -> Data {
        var local = Data()
        var central = Data()
        for name in names {
            let offset = local.count
            let bytes = Data(name.utf8)
            local.appendLE(0x04034b50, bytes: 4)
            for field in [20, flags, 0, 0, 0] { local.appendLE(field, bytes: 2) }
            for field in [0, 0, expanded] { local.appendLE(field, bytes: 4) }
            local.appendLE(bytes.count, bytes: 2)
            local.appendLE(0, bytes: 2)
            local.append(bytes)
            central.appendLE(0x02014b50, bytes: 4)
            for field in [0x0314, 20, flags, 0, 0, 0] { central.appendLE(field, bytes: 2) }
            for field in [0, 0, expanded] { central.appendLE(field, bytes: 4) }
            for field in [bytes.count, 0, 0, 0, 0] { central.appendLE(field, bytes: 2) }
            central.appendLE(mode << 16, bytes: 4)
            central.appendLE(offset, bytes: 4)
            central.append(bytes)
        }
        var result = local + central
        result.appendLE(0x06054b50, bytes: 4)
        for field in [0, 0, names.count, names.count] { result.appendLE(field, bytes: 2) }
        result.appendLE(central.count, bytes: 4)
        result.appendLE(local.count, bytes: 4)
        result.appendLE(0, bytes: 2)
        return result
    }
}

private extension Data {
    mutating func appendLE(_ value: Int, bytes: Int) {
        for i in 0..<bytes { append(UInt8(truncatingIfNeeded: value >> (i * 8))) }
    }
}
