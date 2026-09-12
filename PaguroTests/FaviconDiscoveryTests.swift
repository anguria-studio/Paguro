import XCTest
@testable import Paguro

final class FaviconDiscoveryTests: XCTestCase {
    func testPageDeclaredAppleIconWinsOverTheRootIcon() async {
        let page = "https://example.com/tools/mail/"
        let declared = "https://example.com/tools/mail/apple-icon.png"
        let source = FaviconResponses([
            page: Data("<link rel='apple-touch-icon' href='apple-icon.png' sizes='180x180'>".utf8),
            declared: png(1),
            "https://example.com/apple-touch-icon.png": png(2),
        ])
        let fetcher = FaviconFetcher(load: { await source.load($0) })
        let result = await fetcher.fetchFavicon(for: page)
        XCTAssertEqual(result, png(1))
        let requests = await source.requests
        XCTAssertEqual(requests, [page, declared])
    }

    func testDeclaredManifestIconWinsOverRootFallback() async {
        let page = "https://example.com/app/"
        let source = FaviconResponses([
            page: Data("<link rel='manifest' href='site.webmanifest'>".utf8),
            page + "site.webmanifest": Data(#"{"icons":[{"src":"logo.png","sizes":"192x192"}]}"#.utf8),
            page + "logo.png": png(1),
            "https://example.com/apple-touch-icon.png": png(2),
        ])
        let fetcher = FaviconFetcher(load: { await source.load($0) })
        let result = await fetcher.fetchFavicon(for: page)
        XCTAssertEqual(result, png(1))
    }

    func testMissingDeclaredIconsFallBackToTheOriginIncludingItsPort() async {
        let page = "https://example.com:8443/app/"
        let source = FaviconResponses([
            page: Data("<link rel='icon' href='missing.png'>".utf8),
            "https://example.com:8443/apple-touch-icon.png": png(2),
        ])
        let fetcher = FaviconFetcher(load: { await source.load($0) })
        let result = await fetcher.fetchFavicon(for: page)
        XCTAssertEqual(result, png(2))
        let requests = await source.requests
        XCTAssertEqual(requests, [page, page + "missing.png", "https://example.com:8443/apple-touch-icon.png"])
    }

    func testDeclaredPrivateURLsAreStillRejected() async {
        let page = "https://example.com/app/"
        let source = FaviconResponses([
            page: Data("<link rel='icon' href='http://127.0.0.1/logo.png'><link rel='manifest' href='http://10.0.0.1/private.json'>".utf8),
            "https://example.com/apple-touch-icon.png": png(2),
        ])
        let fetcher = FaviconFetcher(load: { await source.load($0) })
        let result = await fetcher.fetchFavicon(for: page)
        XCTAssertEqual(result, png(2))
        let requests = await source.requests
        XCTAssertEqual(requests, [page, "https://example.com/apple-touch-icon.png"])
    }

    private func png(_ marker: UInt8) -> Data { Data([0x89, 0x50, 0x4E, 0x47, marker]) }
}

private actor FaviconResponses {
    let responses: [String: Data]
    var requests: [String] = []
    init(_ responses: [String: Data]) { self.responses = responses }
    func load(_ url: URL) -> Data? {
        requests.append(url.absoluteString)
        return responses[url.absoluteString]
    }
}
