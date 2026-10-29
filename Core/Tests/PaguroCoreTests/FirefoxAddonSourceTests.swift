import XCTest
@testable import PaguroCore

final class FirefoxAddonSourceTests: XCTestCase {
    func testOfficialListingWithOrWithoutLocale() throws {
        for link in ["https://addons.mozilla.org/firefox/addon/darkreader/",
                     "https://addons.mozilla.org/en-US/firefox/addon/darkreader",
                     " https://addons.mozilla.org/it/firefox/addon/darkreader/?utm_source=test#reviews "] {
            let source = try FirefoxAddonSource(link: link)
            XCTAssertEqual(source.slug, "darkreader")
            XCTAssertEqual(source.metadataURL.absoluteString, "https://addons.mozilla.org/api/v5/addons/addon/darkreader/")
            XCTAssertEqual(source.listingURL.absoluteString, "https://addons.mozilla.org/firefox/addon/darkreader/")
        }
    }

    func testUntrustedOrAmbiguousLinksAreRejected() {
        for link in ["http://addons.mozilla.org/firefox/addon/test/",
                     "https://addons.mozilla.org.evil.test/firefox/addon/test/",
                     "https://user@addons.mozilla.org/firefox/addon/test/",
                     "https://addons.mozilla.org:8443/firefox/addon/test/",
                     "https://addons.mozilla.org/firefox/addon/%2e%2e/",
                     "https://addons.mozilla.org/firefox/addon/../",
                     "https://addons.mozilla.org/firefox/addon/name/reviews/",
                     "https://addons.mozilla.org//firefox/addon/test/",
                     "https://addons.mozilla.org/firefox/addon//",
                     "https://chromewebstore.google.com/detail/test/abcdefgh",
                     "file:///tmp/extension.zip", "javascript:alert(1)", String(repeating: "a", count: 2_049)] {
            XCTAssertThrowsError(try FirefoxAddonSource(link: link), link)
        }
    }

    func testDownloadHostsCannotEscapeMozilla() {
        for link in ["https://addons.mozilla.org/file.xpi", "https://addons.cdn.mozilla.net/file.xpi"] {
            XCTAssertTrue(FirefoxAddonSource.isTrustedDownloadURL(URL(string: link)!))
        }
        for link in ["https://example.com/file.xpi", "http://addons.mozilla.org/file.xpi",
                     "https://addons.cdn.mozilla.net.evil.test/file.xpi",
                     "https://user:pass@addons.mozilla.org/file.xpi", "https://addons.mozilla.org:8443/file.xpi"] {
            XCTAssertFalse(FirefoxAddonSource.isTrustedDownloadURL(URL(string: link)!))
        }
    }

    func testRecordCannotConstructAnUnsafePackagePath() throws {
        let record = BrowserExtensionRecord(slug: "test", name: "Test", version: "1.0",
            sha256: String(repeating: "a", count: 64), permissions: ["storage"], serviceIDs: [UUID()])
        XCTAssertTrue(record.isValid)
        XCTAssertEqual(try JSONDecoder().decode(BrowserExtensionRecord.self, from: JSONEncoder().encode(record)), record)
        let unsafe = BrowserExtensionRecord(slug: "test", name: "Test", version: "1.0",
            sha256: "../../escape", permissions: [], serviceIDs: [])
        XCTAssertFalse(unsafe.isValid)
    }
}
