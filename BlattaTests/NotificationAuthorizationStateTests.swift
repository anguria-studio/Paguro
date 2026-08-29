import BlattaCore
import UserNotifications
import XCTest
@testable import Blatta

/// Covers the boundary that maps `UNAuthorizationStatus` into `BlattaCore`,
/// and the launch flow that must prompt on a fresh install.
@MainActor
final class NotificationAuthorizationStateTests: XCTestCase {
    func testANewManagerHasNotReadThePermission() {
        let manager = makeManager()

        XCTAssertEqual(manager.authorizationState, .unknown)
        XCTAssertNil(
            NotificationAuthorizationPresentation.warning(
                for: manager.authorizationState
            )
        )
    }

    func testEveryPlatformStatusMapsToACoreState() {
        XCTAssertEqual(NotificationManager.state(for: .notDetermined), .notDetermined)
        XCTAssertEqual(NotificationManager.state(for: .denied), .denied)
        XCTAssertEqual(NotificationManager.state(for: .authorized), .authorized)
        XCTAssertEqual(NotificationManager.state(for: .provisional), .provisional)
    }

    // MARK: - First launch

    /// The bug the user hit: no prompt ever appeared. A fresh install reports
    /// `notDetermined`, so the launch must call macOS and let it ask.
    func testAFreshInstallAsksMacOSToPrompt() async {
        let manager = makeManager()
        var requestCount = 0
        manager.readAuthorizationStatus = { .notDetermined }
        manager.performAuthorizationRequest = {
            requestCount += 1
            return true
        }

        manager.startAuthorization()
        await waitUntil { requestCount > 0 }

        XCTAssertEqual(requestCount, 1, "a fresh install must show the prompt")
    }

    func testAGrantedPromptEndsInTheAuthorizedState() async {
        let manager = makeManager()
        var reported = UNAuthorizationStatus.notDetermined
        manager.readAuthorizationStatus = { reported }
        manager.performAuthorizationRequest = {
            reported = .authorized
            return true
        }

        manager.startAuthorization()
        await drain(manager, until: .authorized)

        XCTAssertEqual(manager.authorizationState, .authorized)
        XCTAssertNil(
            NotificationAuthorizationPresentation.warning(for: manager.authorizationState)
        )
    }

    func testAnAlreadyGrantedPermissionAsksNothing() async {
        let manager = makeManager()
        var requestCount = 0
        manager.readAuthorizationStatus = { .authorized }
        manager.performAuthorizationRequest = {
            requestCount += 1
            return true
        }

        manager.startAuthorization()
        await drain(manager, until: .authorized)

        XCTAssertEqual(requestCount, 0)
    }

    // MARK: - Refusal versus failure

    /// The user pressed "Don't Allow". macOS returns normally with
    /// `granted: false`, so this is a real refusal that Blatta respects.
    func testAUserRefusalBecomesTheDeniedState() async {
        let manager = makeManager()
        var reported = UNAuthorizationStatus.notDetermined
        manager.readAuthorizationStatus = { reported }
        manager.performAuthorizationRequest = {
            reported = .denied
            return false
        }

        manager.startAuthorization()
        await drain(manager, until: .denied)

        XCTAssertEqual(manager.authorizationState, .denied)
    }

    /// The failure the user actually hit: macOS threw `UNErrorDomain` code 1
    /// and reported `denied` afterwards. That reported value describes the
    /// platform, not the user, so it must not become a refusal.
    func testAThrownRequestBecomesUnavailableNotDenied() async {
        let manager = makeManager()
        manager.readAuthorizationStatus = { .denied }
        manager.performAuthorizationRequest = {
            throw NSError(domain: UNErrorDomain, code: 1)
        }

        manager.startAuthorization()
        await drain(manager, until: .unavailable)

        XCTAssertEqual(manager.authorizationState, .unavailable)
    }

    /// A stored refusal reports `denied` at launch, and an unregistered app
    /// reports `denied` at launch too. Blatta must ask in both cases, because
    /// only the request outcome separates them. macOS shows no prompt for the
    /// stored refusal, so the request costs the user nothing.
    func testAReportedDenialStillAsksSoTheTwoCasesSeparate() async {
        let manager = makeManager()
        var requestCount = 0
        manager.readAuthorizationStatus = { .denied }
        manager.performAuthorizationRequest = {
            requestCount += 1
            return false
        }

        manager.startAuthorization()
        await drain(manager, until: .denied)

        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(manager.authorizationState, .denied)
    }

    func testTheRequestRunsOnceForEachLaunch() async {
        let manager = makeManager()
        var requestCount = 0
        manager.readAuthorizationStatus = { .notDetermined }
        manager.performAuthorizationRequest = {
            requestCount += 1
            return false
        }

        manager.startAuthorization()
        manager.startAuthorization()
        manager.startAuthorization()
        await waitUntil { requestCount > 0 }
        // Give a second and third request the turns it would need to appear.
        for _ in 0..<50 { await Task.yield() }

        XCTAssertEqual(requestCount, 1)
    }

    // MARK: - Refresh

    /// macOS keeps reporting `denied` for an app it never registered. An
    /// activation refresh must not turn that into a refusal by the user.
    func testARefreshKeepsUnavailableWhileMacOSReportsDenied() async {
        let manager = makeManager()
        manager.readAuthorizationStatus = { .denied }
        manager.performAuthorizationRequest = {
            throw NSError(domain: UNErrorDomain, code: 1)
        }

        manager.startAuthorization()
        await drain(manager, until: .unavailable)

        manager.refreshAuthorizationState()
        for _ in 0..<20 { await Task.yield() }

        XCTAssertEqual(manager.authorizationState, .unavailable)
    }

    /// The user opened System Settings and granted the permission — exactly
    /// the manual fix that worked. Returning to Blatta must clear the warning.
    func testARefreshClearsUnavailableOnceThePermissionArrives() async {
        let manager = makeManager()
        var reported = UNAuthorizationStatus.denied
        manager.readAuthorizationStatus = { reported }
        manager.performAuthorizationRequest = {
            throw NSError(domain: UNErrorDomain, code: 1)
        }

        manager.startAuthorization()
        await drain(manager, until: .unavailable)

        reported = .authorized
        manager.refreshAuthorizationState()
        await drain(manager, until: .authorized)

        XCTAssertEqual(manager.authorizationState, .authorized)
        XCTAssertNil(
            NotificationAuthorizationPresentation.warning(for: manager.authorizationState)
        )
    }

    // MARK: - Helpers

    private func makeManager() -> NotificationManager {
        NotificationManager(badgeManager: BadgeManager())
    }

    private func drain(
        _ manager: NotificationManager,
        until state: NotificationAuthorizationState
    ) async {
        await waitUntil { manager.authorizationState == state }
    }

    /// The launch flow reads the permission, decides, and then asks — three
    /// suspension points. Wait for the condition rather than a turn count.
    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
        }
    }
}
