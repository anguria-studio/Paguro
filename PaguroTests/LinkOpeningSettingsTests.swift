import Foundation
import XCTest
@testable import Paguro

@MainActor
final class LinkOpeningSettingsTests: XCTestCase {
    func testDefaultPersistenceAndLiveOverrides() throws {
        let suite = "LinkOpeningSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = LinkOpeningSettings(defaults: defaults)
        XCTAssertFalse(settings.opensInPaguro(serviceOverride: nil))
        settings.setOpensInPaguro(true)
        XCTAssertTrue(settings.opensInPaguro(serviceOverride: nil))
        XCTAssertFalse(settings.opensInPaguro(serviceOverride: false))
        XCTAssertTrue(LinkOpeningSettings(defaults: defaults).opensInPaguro)
        settings.setOpensInPaguro(false)
        XCTAssertFalse(settings.opensInPaguro(serviceOverride: nil))
        XCTAssertTrue(settings.opensInPaguro(serviceOverride: true))
        XCTAssertFalse(LinkOpeningSettings(defaults: defaults).opensInPaguro)
    }
}
