import XCTest
import SwiftData
import Observation
import BlattaCore
@testable import Blatta

final class PreferencesStoreTests: XCTestCase {
    @MainActor
    func testTypedSettersPersistOnePreferencesRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let store = PreferencesStore(context: context)
        let spaceID = UUID()
        let serviceID = UUID()

        XCTAssertTrue(store.setAppPresenceMode(.menuBar))
        XCTAssertTrue(store.setShowBadgeCountInDock(false))
        XCTAssertTrue(store.setAutoDismissCookieBanners(true))
        XCTAssertTrue(store.setWindowSelection(spaceID: spaceID, serviceID: serviceID))
        XCTAssertTrue(store.setDefaultZoom(1.25))
        XCTAssertTrue(store.setQuietHours(enabled: true, startMinutes: 1_200, endMinutes: 360))
        XCTAssertTrue(store.setAppLockEnabled(true))
        XCTAssertTrue(store.setLockOnLaunch(false))
        XCTAssertTrue(store.setLockOnSleep(false))
        XCTAssertTrue(store.setRailLayout(.topBars))
        XCTAssertTrue(store.setAppearanceMode(.dark))
        XCTAssertTrue(store.setContentBlockingEnabled(false))
        XCTAssertTrue(store.setAnnoyanceBlockingEnabled(true))
        XCTAssertTrue(store.setDefaultMediaPolicies(camera: .allow, microphone: .deny))
        XCTAssertTrue(store.setGoogleFaviconFallbackEnabled(true))
        XCTAssertTrue(store.setAutoHibernateIdleEnabled(true))
        XCTAssertTrue(store.setAutoHibernateIdleMinutes(500))

        let rows = try context.fetch(FetchDescriptor<AppPreferences>())
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.appPresenceMode, .menuBar)
        XCTAssertFalse(row.showBadgeCountInDock)
        XCTAssertTrue(row.autoDismissCookieBanners)
        XCTAssertEqual(row.selectedSpaceID, spaceID)
        XCTAssertEqual(row.selectedServiceID, serviceID)
        XCTAssertEqual(row.defaultZoom, 1.25)
        XCTAssertEqual(row.scheduledDNDEnabled, true)
        XCTAssertEqual(row.dndStartMinutes, 1_200)
        XCTAssertEqual(row.dndEndMinutes, 360)
        XCTAssertEqual(row.appLockEnabled, true)
        XCTAssertEqual(row.lockOnLaunch, false)
        XCTAssertEqual(row.lockOnSleep, false)
        XCTAssertEqual(row.railLayoutRaw, RailLayout.topBars.rawValue)
        XCTAssertEqual(row.appearanceModeRaw, AppearanceMode.dark.rawValue)
        XCTAssertEqual(row.contentBlockingEnabled, false)
        XCTAssertEqual(row.annoyanceBlockingEnabled, true)
        XCTAssertEqual(row.defaultCameraPolicyRaw, MediaPermissionPolicy.allow.rawValue)
        XCTAssertEqual(row.defaultMicrophonePolicyRaw, MediaPermissionPolicy.deny.rawValue)
        XCTAssertEqual(row.googleFaviconFallbackEnabled, true)
        XCTAssertEqual(row.autoHibernateIdleEnabled, true)
        XCTAssertEqual(row.autoHibernateIdleMinutes, 120)
    }

    @MainActor
    func testStoreLoadsAndResolvesTheExistingRow() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let row = AppPreferences(
            appPresenceMode: .dock,
            showBadgeCountInDock: false,
            autoDismissCookieBanners: true,
            defaultZoom: 0.9,
            scheduledDNDEnabled: true,
            dndStartMinutes: 1_380,
            dndEndMinutes: 480,
            appLockEnabled: true,
            lockOnLaunch: false,
            lockOnSleep: false,
            railLayoutRaw: RailLayout.retiredHybridRawValue,
            appearanceModeRaw: AppearanceMode.light.rawValue,
            contentBlockingEnabled: false,
            annoyanceBlockingEnabled: true,
            defaultCameraPolicyRaw: MediaPermissionPolicy.allow.rawValue,
            defaultMicrophonePolicyRaw: "invalid",
            googleFaviconFallbackEnabled: true,
            autoHibernateIdleEnabled: true,
            autoHibernateIdleMinutes: 0
        )
        context.insert(row)
        try context.save()

        let store = PreferencesStore(context: context)

        XCTAssertEqual(store.appPresenceMode, .dock)
        XCTAssertFalse(store.showBadgeCountInDock)
        XCTAssertTrue(store.autoDismissCookieBanners)
        XCTAssertEqual(store.defaultZoom, 0.9)
        XCTAssertTrue(store.scheduledDNDEnabled)
        XCTAssertEqual(store.dndStartMinutes, 1_380)
        XCTAssertEqual(store.dndEndMinutes, 480)
        XCTAssertTrue(store.appLockEnabled)
        XCTAssertFalse(store.lockOnLaunch)
        XCTAssertFalse(store.lockOnSleep)
        XCTAssertEqual(store.railLayout, .workspacesLeft)
        XCTAssertEqual(store.appearanceMode, .light)
        XCTAssertFalse(store.contentBlockingEnabled)
        XCTAssertTrue(store.annoyanceBlockingEnabled)
        XCTAssertEqual(store.defaultCameraPolicy, .allow)
        XCTAssertEqual(store.defaultMicrophonePolicy, .ask)
        XCTAssertTrue(store.googleFaviconFallbackEnabled)
        XCTAssertTrue(store.autoHibernateIdleEnabled)
        XCTAssertEqual(store.autoHibernateIdleMinutes, 1)
    }

    @MainActor
    func testResolvedReadsParticipateInObservation() throws {
        let container = try makeContainer()
        let store = PreferencesStore(context: container.mainContext)
        let change = expectation(description: "Preference observation changed")
        withObservationTracking {
            _ = store.googleFaviconFallbackEnabled
        } onChange: {
            change.fulfill()
        }

        XCTAssertTrue(store.setGoogleFaviconFallbackEnabled(true))
        wait(for: [change], timeout: 1)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
