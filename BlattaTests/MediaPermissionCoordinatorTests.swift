import XCTest
import SwiftData
import BlattaCore
@testable import Blatta

final class MediaPermissionCoordinatorTests: XCTestCase {
    func testServicePolicyAccessorsDefaultToAskAndRoundTrip() {
        let service = ServiceInstance(label: "S", url: "https://s.example")
        XCTAssertEqual(service.cameraPolicy, .ask)
        XCTAssertEqual(service.microphonePolicy, .ask)
        XCTAssertNil(service.cameraPolicyRaw)
        XCTAssertNil(service.microphonePolicyRaw)

        service.cameraPolicy = .allow
        service.microphonePolicy = .deny

        XCTAssertEqual(service.cameraPolicyRaw, "allow")
        XCTAssertEqual(service.microphonePolicyRaw, "deny")
        XCTAssertEqual(service.cameraPolicy, .allow)
        XCTAssertEqual(service.microphonePolicy, .deny)
    }

    func testCatalogMarksFirstPartyCallVendors() {
        let entries = ServiceCatalog.shared.entries
        func firstParty(_ id: String) -> Bool? {
            entries.first { $0.id == id }?.firstParty
        }

        for id in ["messenger", "teams", "facebook", "whatsapp", "google-meet", "google-chat"] {
            XCTAssertEqual(firstParty(id), true, "\(id) should be first-party")
        }
        XCTAssertNotEqual(firstParty("discord"), true)
        XCTAssertNotEqual(firstParty("slack"), true)
    }

    @MainActor
    func testPromptCopyNamesTheRealRequester() {
        let own = MediaPermissionCoordinator.Request(
            id: UUID(),
            serviceLabel: "Slack",
            originHost: nil,
            cameraAsked: false,
            microphoneAsked: true
        )
        XCTAssertEqual(own.title, "Allow Slack to use your microphone?")
        XCTAssertTrue(own.message.hasPrefix("Slack wants to use your microphone"))

        let foreign = MediaPermissionCoordinator.Request(
            id: UUID(),
            serviceLabel: "Messenger",
            originHost: "messenger.com",
            cameraAsked: true,
            microphoneAsked: true
        )
        XCTAssertEqual(foreign.title, "Allow messenger.com to use your camera and microphone?")
        XCTAssertTrue(foreign.message.hasPrefix("messenger.com, opened by Messenger"))
    }

    @MainActor
    func testQueuePresentsOneRequestAndDrainsOneService() async throws {
        let fixture = try makeFixture()
        defer {
            fixture.coordinator.shutdown()
            fixture.pool.shutdown()
        }
        let firstServiceID = UUID()
        let secondServiceID = UUID()

        let first = Task { @MainActor in
            await fixture.coordinator.requestDecision(
                serviceID: firstServiceID,
                serviceLabel: "First",
                originHost: nil,
                fields: MediaPermissionFields(camera: true, microphone: false)
            )
        }
        await waitForPendingRequest(in: fixture.coordinator)
        XCTAssertEqual(fixture.coordinator.pendingRequest?.serviceLabel, "First")

        let second = Task { @MainActor in
            await fixture.coordinator.requestDecision(
                serviceID: secondServiceID,
                serviceLabel: "Second",
                originHost: nil,
                fields: MediaPermissionFields(camera: false, microphone: true)
            )
        }
        await Task.yield()
        XCTAssertEqual(fixture.coordinator.pendingRequest?.serviceLabel, "First")

        fixture.coordinator.denyRequests(for: firstServiceID)
        let firstResult = await first.value
        XCTAssertFalse(firstResult)
        await waitForPendingRequest(in: fixture.coordinator, label: "Second")

        let secondRequest = try XCTUnwrap(fixture.coordinator.pendingRequest)
        fixture.coordinator.answerRequest(secondRequest.id, allow: true)
        let secondResult = await second.value
        XCTAssertTrue(secondResult)
        XCTAssertNil(fixture.coordinator.pendingRequest)
    }

    @MainActor
    func testDefaultPoliciesPersistThroughPreferencesStore() throws {
        let fixture = try makeFixture()
        defer {
            fixture.coordinator.shutdown()
            fixture.pool.shutdown()
        }

        fixture.coordinator.setDefaultCameraPolicy(.allow)
        fixture.coordinator.setDefaultMicrophonePolicy(.deny)

        XCTAssertEqual(fixture.coordinator.defaultCameraPolicy, .allow)
        XCTAssertEqual(fixture.coordinator.defaultMicrophonePolicy, .deny)
        let preferences = try XCTUnwrap(
            fixture.container.mainContext.fetch(FetchDescriptor<AppPreferences>()).first
        )
        XCTAssertEqual(preferences.defaultCameraPolicyRaw, MediaPermissionPolicy.allow.rawValue)
        XCTAssertEqual(preferences.defaultMicrophonePolicyRaw, MediaPermissionPolicy.deny.rawValue)
    }

    @MainActor
    func testPresenceOfferPersistsAndSignalsARebuild() throws {
        let fixture = try makeFixture()
        defer {
            fixture.coordinator.shutdown()
            fixture.pool.shutdown()
        }
        let service = ServiceInstance(
            label: "Teams",
            url: "https://teams.microsoft.com",
            catalogEntryID: "teams"
        )
        fixture.container.mainContext.insert(service)
        try fixture.container.mainContext.save()
        var rebuildCount = 0
        fixture.coordinator.start(
            isLocked: { false },
            onWebViewRebuilt: { rebuildCount += 1 }
        )

        fixture.coordinator.offerPresenceActivationIfNeeded(
            serviceID: service.id,
            catalogEntryID: service.catalogEntryID
        )
        XCTAssertEqual(fixture.coordinator.presencePrompt?.serviceLabel, "Teams")

        fixture.coordinator.answerPresencePrompt(service.id, enable: true)

        XCTAssertNil(fixture.coordinator.presencePrompt)
        XCTAssertEqual(service.stayActiveInBackground, true)
        XCTAssertEqual(rebuildCount, 1)
    }

    @MainActor
    private func makeFixture() throws -> (
        coordinator: MediaPermissionCoordinator,
        pool: WebViewPool,
        container: ModelContainer
    ) {
        let container = try ModelContainer(
            for: ServiceInstance.self,
            Space.self,
            SpaceServiceLink.self,
            AppPreferences.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let preferencesStore = PreferencesStore(context: container.mainContext)
        let pool = WebViewPool(
            dataStoreManager: DataStoreManager(),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
        let coordinator = MediaPermissionCoordinator(
            context: container.mainContext,
            preferencesStore: preferencesStore,
            webViewPool: pool
        )
        return (coordinator, pool, container)
    }

    @MainActor
    private func waitForPendingRequest(
        in coordinator: MediaPermissionCoordinator,
        label: String? = nil
    ) async {
        for _ in 0..<20 {
            if let request = coordinator.pendingRequest,
               label == nil || request.serviceLabel == label {
                return
            }
            await Task.yield()
        }
    }
}
