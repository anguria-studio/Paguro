#if !APP_STORE
import Foundation
import PaguroCore
import XCTest
@testable import Paguro

@MainActor
final class FirefoxAddonClientTests: XCTestCase {
    func testDiscoveryReadsMetadataOnlyAndExplicitFetchVerifiesPackage() async throws {
        guard #available(macOS 15.4, *) else { throw XCTSkip("Requires the extension ZIP fixture") }
        let package = try BrowserExtensionFixture.package()
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/\(package.slug)/")
        let url = URL(string: "https://addons.mozilla.org/update.xpi")!
        let metadata = try JSONSerialization.data(withJSONObject: [
            "slug": package.slug, "type": "extension", "is_disabled": false,
            "current_version": ["version": package.version, "file": ["url": url.absoluteString,
                "hash": "sha256:\(package.sha256)", "size": package.data.count, "status": "public"]]
        ])
        let log = AddonReads(values: [source.metadataURL: metadata, url: package.data])
        let client = FirefoxAddonClient { url, _ in try await log.read(url) }
        let release = try await client.latest(source)
        XCTAssertEqual(release.sha256, package.sha256)
        var requests = await log.requests
        XCTAssertEqual(requests, [source.metadataURL])
        let fetched = try await client.fetch(source)
        XCTAssertEqual(fetched.data, package.data)
        requests = await log.requests
        XCTAssertEqual(requests, [source.metadataURL, source.metadataURL, url])
    }

    func testUntrustedUnavailableAndOversizedMetadataCannotAdvertiseAnUpdate() async throws {
        let source = try FirefoxAddonSource(link: "https://addons.mozilla.org/firefox/addon/probe/")
        let file: [String: Any] = ["url": "https://addons.mozilla.org/update.xpi", "hash": "sha256:" + String(repeating: "a", count: 64), "size": 123, "status": "public"]
        let valid: [String: Any] = ["slug": "probe", "type": "extension", "is_disabled": false,
            "current_version": ["version": "2", "file": file]]
        var invalid: [[String: Any]] = []
        for change: [String: Any] in [["slug": "other"], ["type": "theme"], ["is_disabled": true]] {
            invalid.append(valid.merging(change) { _, new in new })
        }
        for change: [String: Any] in [["url": "https://evil.example/update.xpi"], ["status": "disabled"],
            ["hash": "sha256:" + String(repeating: "z", count: 64)], ["size": 0], ["size": 67_108_865]] {
            invalid.append(valid.merging(["current_version": ["version": "2", "file": file.merging(change) { _, new in new }]]) { _, new in new })
        }
        for object in invalid {
            let data = try JSONSerialization.data(withJSONObject: object)
            let client = FirefoxAddonClient { _, _ in data }
            do { _ = try await client.latest(source); XCTFail("Unsafe metadata must be rejected") } catch { }
        }
        let oversized = Data(repeating: 32, count: 2 * 1_024 * 1_024 + 1)
        let client = FirefoxAddonClient { _, _ in oversized }
        do { _ = try await client.latest(source); XCTFail("Metadata must be bounded") } catch { }
    }
}

private actor AddonReads {
    let values: [URL: Data]
    var requests: [URL] = []
    init(values: [URL: Data]) { self.values = values }
    func read(_ url: URL) throws -> Data {
        requests.append(url)
        guard let value = values[url] else { throw URLError(.badURL) }
        return value
    }
}
#endif
