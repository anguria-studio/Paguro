#if !APP_STORE
import Foundation
import XCTest
@testable import Paguro

final class ExtensionComparisonPackageTests: XCTestCase {
    @MainActor
    func testEnvelopeRemovalPreservesArchiveBytes() throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires WebKit extensions") }
        let package = try BrowserExtensionFixture.package()
        let header = Data([67, 114, 50, 52, 3, 0, 0, 0, 4, 0, 0, 0, 1, 2, 3, 4])
        XCTAssertEqual(try ExtensionComparisonPackage.archive(from: header + package.data), package.data)
    }

    func testMalformedEnvelopesAndUnsafeArchiveAreRejected() {
        let samples: [[UInt8]] = [[], [67, 114, 50, 52],
            [67, 114, 50, 52, 2, 0, 0, 0, 0, 0, 0, 0, 1],
            [67, 114, 50, 52, 3, 0, 0, 0, 255, 255, 255, 255, 1],
            [67, 114, 50, 52, 3, 0, 0, 0, 4, 0, 0, 0, 1],
            [67, 114, 50, 52, 3, 0, 0, 0, 0, 0, 0, 0, 1]]
        for bytes in samples { XCTAssertThrowsError(try ExtensionComparisonPackage.archive(from: Data(bytes))) }
    }

    func testResearchDownloadsStayOnNamedGoogleHosts() throws {
        for value in ["https://clients2.google.com/service/update2/crx", "https://clients2.googleusercontent.com/crx/blobs/file.crx"] {
            XCTAssertTrue(ExtensionComparisonPackage.isDownloadURL(try XCTUnwrap(URL(string: value))))
        }
        for value in ["http://clients2.google.com/file", "https://clients2.google.com.evil.test/file",
                      "https://evil.test/file", "https://user@clients2.google.com/file", "https://clients2.google.com:444/file"] {
            XCTAssertFalse(ExtensionComparisonPackage.isDownloadURL(try XCTUnwrap(URL(string: value))))
        }
    }
}
#endif
