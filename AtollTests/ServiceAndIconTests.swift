import XCTest
import AppKit
@testable import Atoll

final class ServiceAndIconTests: XCTestCase {
    func testServiceInstanceCreation() {
        let service = ServiceInstance(
            label: "Test Gmail",
            url: "https://mail.google.com",
            catalogEntryID: "gmail"
        )
        XCTAssertEqual(service.label, "Test Gmail")
        XCTAssertEqual(service.url, "https://mail.google.com")
        XCTAssertFalse(service.isMuted)
        XCTAssertNotNil(service.dataStoreIdentifier)
    }

    func testSpaceCreation() {
        let space = Space(name: "Work", emoji: "🏢", sortOrder: 0)
        XCTAssertEqual(space.name, "Work")
        XCTAssertEqual(space.emoji, "🏢")
        XCTAssertEqual(space.sortOrder, 0)
        XCTAssertTrue(space.serviceLinks.isEmpty)
    }

    @MainActor
    func testWorkspaceMuteCascadesToItsServices() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let space = Space(name: "Work", emoji: "🏢")
        let service = ServiceInstance(label: "Slack", url: "https://app.slack.com")
        context.insert(space)
        context.insert(service)
        ModelFixtures.link(service, to: space, sortOrder: 0, in: context)
        try context.save()

        XCTAssertFalse(service.isEffectivelyMuted)
        space.isMuted = true
        XCTAssertTrue(service.isEffectivelyMuted)
        space.isMuted = false
        XCTAssertFalse(service.isEffectivelyMuted)
    }

    func testServiceCatalogParsing() throws {
        let json = """
        [{"id":"gmail","name":"Gmail","url":"https://mail.google.com","icon":"gmail-icon","category":"Email","badgeJS":null,"userAgent":null,"description":"Google email"}]
        """

        let entries = try JSONDecoder().decode([ServiceCatalogEntry].self, from: Data(json.utf8))
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, "gmail")
        XCTAssertEqual(entries[0].category, "Email")
    }

    @MainActor
    func testBadgeCountExtraction() {
        XCTAssertEqual(NotificationManager.extractBadgeCount(from: "Inbox (5) - Gmail"), 5)
        XCTAssertEqual(NotificationManager.extractBadgeCount(from: "(12) Slack"), 12)
        XCTAssertEqual(NotificationManager.extractBadgeCount(from: "No badges here"), 0)
    }

    @MainActor
    func testCustomServiceInputValidation() {
        XCTAssertEqual(
            AddServiceSheet.validatedCustomServiceInput(label: "  Docs  ", url: " HTTPS://example.com/app "),
            .valid(label: "Docs", url: "https://example.com/app")
        )
        XCTAssertEqual(
            AddServiceSheet.validatedCustomServiceInput(label: "   ", url: "https://example.com"),
            .invalid("Label can't be empty")
        )
        XCTAssertEqual(
            AddServiceSheet.validatedCustomServiceInput(label: "Broken", url: "https://"),
            .invalid("URL must include a host")
        )
        XCTAssertEqual(
            AddServiceSheet.validatedCustomServiceInput(label: "FTP", url: "ftp://example.com"),
            .invalid("URL must start with https:// or http://")
        )
    }

    func testFaviconParserHandlesAttributeOrderAndRelativeURLs() {
        let html = """
        <html><head>
            <link href="icons/favicon-32.png" rel="icon" sizes="16x16 32x32">
            <link sizes="180x180" rel="apple-touch-icon" href="/apple-touch-icon.png">
            <link rel="stylesheet" href="/site.css">
        </head></html>
        """
        let links = FaviconFetcher.parseIconLinks(
            from: html,
            baseURL: URL(string: "https://example.com/app/page")!
        )

        XCTAssertEqual(
            links,
            [
                .init(url: "https://example.com/app/icons/favicon-32.png", size: 32),
                .init(url: "https://example.com/apple-touch-icon.png", size: 180),
            ]
        )
    }

    func testFaviconParserFindsManifestAndResolvesItsIcons() {
        let html = """
        <html><head>
            <link href="../app.webmanifest" rel="manifest">
        </head></html>
        """
        let pageURL = URL(string: "https://example.com/products/mail/index.html")!
        XCTAssertEqual(
            FaviconFetcher.parseManifestURLs(from: html, baseURL: pageURL),
            [URL(string: "https://example.com/products/app.webmanifest")!]
        )

        let manifest = """
        {
          "icons": [
            {"src":"icons/icon-192.png","sizes":"192x192","purpose":"any"},
            {"src":"/brand.svg","sizes":"any"},
            {"src":"mono.svg","sizes":"512x512","purpose":"monochrome"}
          ]
        }
        """.data(using: .utf8)!

        XCTAssertEqual(
            FaviconFetcher.parseManifestIconLinks(
                from: manifest,
                manifestURL: URL(string: "https://example.com/products/app.webmanifest")!
            ),
            [
                .init(url: "https://example.com/products/icons/icon-192.png", size: 192),
                .init(url: "https://example.com/brand.svg", size: 4096),
            ]
        )
    }

    @MainActor
    func testServiceIconImageProcessorNormalizesAndLimitsDimensions() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 512,
            pixelsHigh: 256,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bitmapFormat: [],
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        let source = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let normalized = try ServiceIconImageProcessor.normalizedPNG(from: source)
        let result = try XCTUnwrap(NSBitmapImageRep(data: normalized))

        XCTAssertEqual([UInt8](normalized.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
        XCTAssertEqual(result.pixelsWide, 256)
        XCTAssertEqual(result.pixelsHigh, 128)
    }

    @MainActor
    func testServiceIconImageProcessorRejectsUnsafeInput() {
        XCTAssertThrowsError(
            try ServiceIconImageProcessor.normalizedPNG(from: Data([0, 1, 2, 3]))
        )
        XCTAssertThrowsError(
            try ServiceIconImageProcessor.normalizedPNG(
                from: Data(count: ServiceIconImageProcessor.maximumInputBytes + 1)
            )
        )
    }

    func testIsFetchableIconURLRejectsPrivateAndNonWebTargets() {
        // Public https host is fetchable.
        XCTAssertTrue(FaviconFetcher.isFetchableIconURL(URL(string: "https://example.com/i.png")!))
        // Non-web schemes never fetch.
        XCTAssertFalse(FaviconFetcher.isFetchableIconURL(URL(string: "file:///etc/passwd")!))
        XCTAssertFalse(FaviconFetcher.isFetchableIconURL(URL(string: "data:image/png;base64,AAAA")!))
        // Literal private / loopback / link-local IPs are blocked (SSRF).
        XCTAssertFalse(FaviconFetcher.isFetchableIconURL(URL(string: "http://127.0.0.1/i.png")!))
        XCTAssertFalse(FaviconFetcher.isFetchableIconURL(URL(string: "http://10.0.0.5/i.png")!))
        XCTAssertFalse(FaviconFetcher.isFetchableIconURL(URL(string: "http://169.254.169.254/latest")!))
    }

    func testIsLikelyPrivateHostHeuristic() {
        // Public FQDNs pass through (may go to Google, may be fetched).
        XCTAssertFalse(FaviconFetcher.isLikelyPrivateHost("example.com"))
        XCTAssertFalse(FaviconFetcher.isLikelyPrivateHost("mail.google.com"))
        // Intranet shapes are treated as private without a DNS lookup.
        XCTAssertTrue(FaviconFetcher.isLikelyPrivateHost("localhost"))
        XCTAssertTrue(FaviconFetcher.isLikelyPrivateHost("intranet"))          // single label
        XCTAssertTrue(FaviconFetcher.isLikelyPrivateHost("mail.corp"))         // private TLD
        XCTAssertTrue(FaviconFetcher.isLikelyPrivateHost("nas.local"))
        XCTAssertTrue(FaviconFetcher.isLikelyPrivateHost("192.168.1.10"))      // literal private IP
    }

}
