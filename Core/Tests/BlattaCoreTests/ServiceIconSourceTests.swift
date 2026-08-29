import XCTest
@testable import BlattaCore

final class ServiceIconSourceTests: XCTestCase {
    func testBlankSourceUsesTheServiceAddress() {
        XCTAssertEqual(
            ServiceIconSource.normalizedURL(
                from: "  ",
                fallbackURL: " https://example.com/app "
            )?.absoluteString,
            "https://example.com/app"
        )
    }

    func testHostWithoutSchemeUsesHTTPS() {
        XCTAssertEqual(
            ServiceIconSource.normalizedURL(
                from: "icons.example.com/brand.png",
                fallbackURL: ""
            )?.absoluteString,
            "https://icons.example.com/brand.png"
        )
        XCTAssertEqual(
            ServiceIconSource.normalizedURL(
                from: "icons.example.com:8443/brand.png",
                fallbackURL: ""
            )?.absoluteString,
            "https://icons.example.com:8443/brand.png"
        )
    }

    func testIPv6HostWithoutSchemeUsesHTTPS() {
        XCTAssertEqual(
            ServiceIconSource.normalizedURL(
                from: "[2001:db8::1]/brand.png",
                fallbackURL: ""
            )?.absoluteString,
            "https://[2001:db8::1]/brand.png"
        )
    }

    func testWebSchemeIsCaseInsensitiveAndCanonicalized() {
        XCTAssertEqual(
            ServiceIconSource.normalizedURL(
                from: "HTTPS://EXAMPLE.COM/brand.png",
                fallbackURL: ""
            )?.absoluteString,
            "https://EXAMPLE.COM/brand.png"
        )
    }

    func testOnlyWebAddressesAreAccepted() {
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "file:///tmp/icon.png", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "ftp://example.com/icon.png", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "javascript:alert(1)", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "data:image/png;base64,AAAA", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "https://", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "https://user@example.com", fallbackURL: ""))
    }
}
