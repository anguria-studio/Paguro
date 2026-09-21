import Foundation
import XCTest
@testable import Paguro

@MainActor
final class PasskeyNoticeControllerTests: XCTestCase {
    private func withDefaults(_ body: (UserDefaults) -> Void) {
        let suite = "PasskeyNoticeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        body(defaults)
    }

    func testSeenStateSurvivesRelaunchWithoutAnyServiceRecords() {
        withDefaults { defaults in
            let first = PasskeyNoticeController(defaults: defaults, hasLegacySeenNotice: false)
            first.present(isLocked: false, passkeysSupported: false)
            XCTAssertTrue(first.state.isVisible)
            let relaunched = PasskeyNoticeController(defaults: defaults, hasLegacySeenNotice: false)
            relaunched.present(isLocked: false, passkeysSupported: false)
            XCTAssertFalse(relaunched.state.isVisible)
        }
    }

    func testLegacySeenStateMigratesToTheAppOnce() {
        withDefaults { defaults in
            let migrated = PasskeyNoticeController(defaults: defaults, hasLegacySeenNotice: true)
            migrated.present(isLocked: false, passkeysSupported: false)
            XCTAssertFalse(migrated.state.isVisible)
            XCTAssertTrue(defaults.bool(forKey: DefaultsKey.passkeyNoticeSeen))
        }
    }

    func testLockDoesNotPersistAnUnseenNotice() {
        withDefaults { defaults in
            let controller = PasskeyNoticeController(defaults: defaults, hasLegacySeenNotice: false)
            controller.present(isLocked: true, passkeysSupported: false)
            XCTAssertFalse(defaults.bool(forKey: DefaultsKey.passkeyNoticeSeen))
        }
    }

    func testASeparatePreviewDoesNotInheritTheNormalSeenState() {
        withDefaults { normal in
            let controller = PasskeyNoticeController(defaults: normal, hasLegacySeenNotice: false)
            controller.present(isLocked: false, passkeysSupported: false)
            withDefaults { preview in
                let fresh = PasskeyNoticeController(defaults: preview, hasLegacySeenNotice: false)
                fresh.present(isLocked: false, passkeysSupported: false)
                XCTAssertTrue(fresh.state.isVisible)
            }
        }
    }
}
