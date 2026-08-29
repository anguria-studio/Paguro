import XCTest
@testable import BlattaCore

final class NotificationAuthorizationPolicyTests: XCTestCase {
    // MARK: - Asking

    func testAFreshInstallAsksForThePermission() {
        XCTAssertTrue(NotificationAuthorizationPolicy.shouldRequest(for: .notDetermined))
    }

    func testAnUnreadPermissionAsks() {
        XCTAssertTrue(NotificationAuthorizationPolicy.shouldRequest(for: .unknown))
    }

    /// The request under a stored refusal shows no prompt. It is the only way
    /// to separate that refusal from an app that macOS never registered.
    func testAStoredRefusalStillAsksOncePerStart() {
        XCTAssertTrue(NotificationAuthorizationPolicy.shouldRequest(for: .denied))
    }

    func testAFailedRequestAsksAgainAtTheNextStart() {
        XCTAssertTrue(NotificationAuthorizationPolicy.shouldRequest(for: .unavailable))
    }

    func testAGrantedPermissionAsksNothing() {
        XCTAssertFalse(NotificationAuthorizationPolicy.shouldRequest(for: .authorized))
        XCTAssertFalse(NotificationAuthorizationPolicy.shouldRequest(for: .provisional))
    }

    // MARK: - Request outcome

    func testACompletedRequestTakesTheReportedPermission() {
        XCTAssertEqual(
            NotificationAuthorizationPolicy.state(after: .completed, reportedState: .authorized),
            .authorized
        )
        XCTAssertEqual(
            NotificationAuthorizationPolicy.state(after: .completed, reportedState: .denied),
            .denied
        )
        XCTAssertEqual(
            NotificationAuthorizationPolicy.state(after: .completed, reportedState: .provisional),
            .provisional
        )
    }

    /// The reported permission after a refused request is `denied`. That value
    /// describes the platform, not the user, so it must not become a refusal.
    func testAFailedRequestNeverBecomesARefusal() {
        XCTAssertEqual(
            NotificationAuthorizationPolicy.state(after: .failed, reportedState: .denied),
            .unavailable
        )
        XCTAssertEqual(
            NotificationAuthorizationPolicy.state(after: .failed, reportedState: .notDetermined),
            .unavailable
        )
    }

    // MARK: - Activation refresh

    func testARefreshKeepsUnavailableWhileMacOSKeepsReportingDenied() {
        XCTAssertEqual(
            NotificationAuthorizationPolicy.merge(current: .unavailable, reported: .denied),
            .unavailable
        )
        XCTAssertEqual(
            NotificationAuthorizationPolicy.merge(current: .unavailable, reported: .notDetermined),
            .unavailable
        )
    }

    /// The user opens System Settings and grants the permission. The next
    /// activation must clear the warning.
    func testARefreshLeavesUnavailableWhenThePermissionArrives() {
        XCTAssertEqual(
            NotificationAuthorizationPolicy.merge(current: .unavailable, reported: .authorized),
            .authorized
        )
        XCTAssertEqual(
            NotificationAuthorizationPolicy.merge(current: .unavailable, reported: .provisional),
            .provisional
        )
    }

    func testARefreshFromAnyOtherStateTakesTheReportedPermission() {
        for current in NotificationAuthorizationState.allCases where current != .unavailable {
            XCTAssertEqual(
                NotificationAuthorizationPolicy.merge(current: current, reported: .denied),
                .denied,
                "\(current) must accept a fresh read"
            )
        }
    }

    // MARK: - Restart contract

    func testMacOSRemembersARefusalAndForgetsAFailure() {
        XCTAssertTrue(NotificationAuthorizationPolicy.survivesRestart(.denied))
        XCTAssertFalse(NotificationAuthorizationPolicy.survivesRestart(.unavailable))
    }

    /// Every state that a restart forgets must ask again, or the retry rule
    /// has a hole.
    func testEveryForgottenStateAsksAgain() {
        for state in NotificationAuthorizationState.allCases
        where !NotificationAuthorizationPolicy.survivesRestart(state) {
            XCTAssertTrue(
                NotificationAuthorizationPolicy.shouldRequest(for: state),
                "\(state) must ask again"
            )
        }
    }
}
