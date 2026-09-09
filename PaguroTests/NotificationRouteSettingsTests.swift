import Foundation
import XCTest
@testable import Paguro

@MainActor
final class NotificationRouteSettingsTests: XCTestCase {
    func testFreshSettingsKeepSystemNotificationsAndDisableIslandAlerts() throws {
        let defaults = try makeDefaults()

        let settings = NotificationRouteSettings(defaults: defaults)

        XCTAssertTrue(settings.isSystemRouteEnabled)
        XCTAssertFalse(settings.isIslandRouteEnabled)
    }

    func testSettingsPersistBothRoutes() throws {
        let defaults = try makeDefaults()
        let settings = NotificationRouteSettings(defaults: defaults)

        settings.setSystemRouteEnabled(false)
        settings.setIslandRouteEnabled(true)

        let restored = NotificationRouteSettings(defaults: defaults)
        XCTAssertFalse(restored.isSystemRouteEnabled)
        XCTAssertTrue(restored.isIslandRouteEnabled)
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "NotificationRouteSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}
