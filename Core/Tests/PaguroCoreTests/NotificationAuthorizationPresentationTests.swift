import XCTest
@testable import PaguroCore

final class NotificationAuthorizationPresentationTests: XCTestCase {
    func testAuthorizedStateShowsBannersAndNoWarning() {
        XCTAssertTrue(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .authorized)
        )
        XCTAssertNil(NotificationAuthorizationPresentation.warning(for: .authorized))
    }

    func testUnreadPermissionShowsNoWarning() {
        XCTAssertFalse(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .unknown)
        )
        XCTAssertNil(NotificationAuthorizationPresentation.warning(for: .unknown))
    }

    func testDeniedPermissionWarnsAndOffersTheSettingsAction() throws {
        let warning = try XCTUnwrap(
            NotificationAuthorizationPresentation.warning(for: .denied)
        )

        XCTAssertFalse(warning.title.isEmpty)
        XCTAssertFalse(warning.message.isEmpty)
        XCTAssertEqual(warning.actionTitle, "Open Notification Settings")
        XCTAssertFalse(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .denied)
        )
    }

    func testUndeterminedPermissionWarns() throws {
        let warning = try XCTUnwrap(
            NotificationAuthorizationPresentation.warning(for: .notDetermined)
        )

        XCTAssertFalse(warning.message.isEmpty)
        XCTAssertFalse(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .notDetermined)
        )
    }

    func testProvisionalPermissionWarnsAboutQuietDelivery() throws {
        let warning = try XCTUnwrap(
            NotificationAuthorizationPresentation.warning(for: .provisional)
        )

        XCTAssertTrue(warning.title.contains("quietly"))
        XCTAssertFalse(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .provisional)
        )
    }

    /// A refused request and a refusal by the user need different words: one
    /// asks the user to change a setting, the other explains that macOS never
    /// asked and names the remedy.
    func testAFailedRequestWarnsDifferentlyFromARefusal() throws {
        let unavailable = try XCTUnwrap(
            NotificationAuthorizationPresentation.warning(for: .unavailable)
        )
        let denied = try XCTUnwrap(
            NotificationAuthorizationPresentation.warning(for: .denied)
        )

        XCTAssertNotEqual(unavailable.title, denied.title)
        XCTAssertNotEqual(unavailable.message, denied.message)
        XCTAssertTrue(unavailable.message.contains("Applications folder"))
        XCTAssertFalse(
            NotificationAuthorizationPresentation.showsSystemBanners(for: .unavailable)
        )
    }

    func testEveryUnauthorizedStateExceptUnknownHasAWarning() {
        for state in NotificationAuthorizationState.allCases {
            let warning = NotificationAuthorizationPresentation.warning(for: state)
            switch state {
            case .authorized, .unknown:
                XCTAssertNil(warning, "\(state) must not warn")
            case .notDetermined, .denied, .provisional, .unavailable:
                XCTAssertNotNil(warning, "\(state) must warn")
            }
        }
    }

    /// Every warning must name an action. A row that only reports a problem
    /// leaves the user where they started.
    func testEveryWarningOffersAnAction() {
        for state in NotificationAuthorizationState.allCases {
            guard let warning = NotificationAuthorizationPresentation.warning(for: state)
            else { continue }
            XCTAssertFalse(warning.actionTitle.isEmpty, "\(state) needs an action")
            XCTAssertFalse(warning.title.isEmpty, "\(state) needs a title")
            XCTAssertFalse(warning.message.isEmpty, "\(state) needs a message")
        }
    }

    func testSettingsURLOpensTheNotificationPane() {
        XCTAssertEqual(
            NotificationAuthorizationPresentation.systemSettingsURLString,
            "x-apple.systempreferences:com.apple.preference.notifications"
        )
    }
}
