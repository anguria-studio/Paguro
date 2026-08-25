import XCTest
@testable import AtollCore

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

    func testOnlyWebAddressesAreAccepted() {
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "file:///tmp/icon.png", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "ftp://example.com/icon.png", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "https://", fallbackURL: ""))
        XCTAssertNil(ServiceIconSource.normalizedURL(from: "https://user@example.com", fallbackURL: ""))
    }
}
