import SwiftData
import WebKit
import XCTest
import PaguroCore
@testable import Paguro

final class WebViewPoolActivationTests: XCTestCase {
    private enum Event: Equatable {
        case softHibernated(UUID)
        case activated(UUID)
    }

    @MainActor
    func testActivationCallbackReceivesTheRegisteredLiveWebView() {
        let pool = makePool()
        defer { pool.shutdown() }
        let service = ServiceInstance(label: "Mail", url: "about:blank")
        var callbackValues: [(UUID, WKWebView)] = []
        pool.onServiceActivated = { callbackValues.append(($0, $1)) }

        let webView = pool.webView(for: service)

        XCTAssertEqual(callbackValues.count, 1)
        XCTAssertEqual(callbackValues.first?.0, service.id)
        XCTAssertTrue(callbackValues.first?.1 === webView)
        XCTAssertTrue(pool.liveWebView(for: service.id) === webView)
        XCTAssertEqual(pool.activeServiceID, service.id)

        let sameWebView = pool.webView(for: service)
        XCTAssertTrue(sameWebView === webView)
        XCTAssertEqual(callbackValues.count, 2)
        XCTAssertTrue(callbackValues.last?.1 === webView)
    }

    @MainActor
    func testSwitchAndDeactivationReportLifecycleInOrder() {
        let pool = makePool()
        defer { pool.shutdown() }
        let first = ServiceInstance(label: "First", url: "about:blank")
        let second = ServiceInstance(label: "Second", url: "about:blank")
        var events: [Event] = []
        pool.onServiceSoftHibernated = { serviceID in
            events.append(Event.softHibernated(serviceID))
        }
        pool.onServiceActivated = { serviceID, _ in
            events.append(Event.activated(serviceID))
        }

        _ = pool.webView(for: first)
        events.removeAll()
        _ = pool.webView(for: second)

        XCTAssertEqual(events, [
            .softHibernated(first.id),
            .activated(second.id),
        ])

        events.removeAll()
        pool.deactivateCurrentService()
        XCTAssertEqual(events, [.softHibernated(second.id)])
        XCTAssertNil(pool.activeServiceID)
    }

    @MainActor
    func testShutdownRejectsLaterPreloads() async throws {
        let container = try ModelFixtures.groupingContainer()
        let service = ServiceInstance(label: "Mail", url: "about:blank")
        container.mainContext.insert(service)
        try container.mainContext.save()
        let pool = makePool()

        pool.shutdown()
        pool.preload(service)
        await pool.preloadAll([service], delayBetween: .zero)

        XCTAssertEqual(pool.loadedCount, 0)
    }

    /// The pool limit is separate from idle hibernation, so a full pool must
    /// release the least recently used service on its own. Every exemption must
    /// survive that sweep, and the capacity callback must name the one service
    /// that the sweep released.
    @MainActor
    func testCapacitySweepReleasesTheLeastRecentUnprotectedService() async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        // Twelve ordinary services plus four protected ones is one over the
        // limit, so the sweep must release exactly one of them.
        let store = UUID()
        let ordinary = (0..<(WebViewPoolCapacity.maxLoaded - 3)).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        let keepLoaded = Self.poolService(
            label: "Keep Loaded",
            store: store,
            hibernationPolicyRaw: HibernationPolicy.never.rawValue
        )
        let chat = Self.poolService(label: "Chat", store: store, catalogEntryID: "slack")
        let pinned = Self.poolService(label: "Pinned", store: store)
        let active = Self.poolService(label: "Active", store: store)
        for item in ordinary + [keepLoaded, chat, pinned, active] {
            context.insert(item)
        }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }
        pool.isNotificationCritical = { $0 == chat.id }
        pool.pin(pinned.id)

        // Least recent first, so the expected victim is the oldest ordinary one.
        for item in ordinary + [keepLoaded, chat, pinned] {
            pool.preload(item)
        }
        _ = pool.webView(for: active)
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded + 1)

        // Each preload and activation also starts its own sweep. Wait for the
        // pool to settle instead of racing those tasks.
        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertEqual(evicted, [ordinary[0].id], "only the least recent unprotected service is released")
        XCTAssertTrue(pool.isHibernated(ordinary[0].id))
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded)

        for spared in [keepLoaded, chat, pinned, active] {
            XCTAssertFalse(pool.isHibernated(spared.id), "\(spared.label) must survive the capacity sweep")
            XCTAssertTrue(pool.hasWebView(for: spared.id), "\(spared.label) must keep its live web view")
        }
        for survivor in ordinary.dropFirst() {
            XCTAssertFalse(pool.isHibernated(survivor.id), "\(survivor.label) is not the least recent service")
        }
    }

    /// The sweep stops at the limit instead of reclaiming everything it can, so
    /// a second pass over a pool that is already at the limit releases nothing.
    @MainActor
    func testASweepAtTheLimitReleasesNothing() async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        let store = UUID()
        let services = (0..<WebViewPoolCapacity.maxLoaded).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        for item in services { context.insert(item) }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }
        for item in services { pool.preload(item) }

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertTrue(evicted.isEmpty)
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded)
    }

    // MARK: - Call protection (ATL-302)

    /// A call must keep its service loaded. The capacity sweep releases the
    /// least recently used service, so a protected least-recent service is the
    /// strongest test of the guard: it must stay live, and the sweep must take
    /// the next candidate instead.
    @MainActor
    func testCapacitySweepSparesAnActiveMicrophone() async throws {
        try await assertCapacitySweepSparesTheLeastRecentService { pool, serviceID in
            pool.setMediaCaptureState(
                WebViewPool.MediaCaptureState(micActive: true),
                for: serviceID
            )
        }
    }

    @MainActor
    func testCapacitySweepSparesAnActiveCamera() async throws {
        try await assertCapacitySweepSparesTheLeastRecentService { pool, serviceID in
            pool.setMediaCaptureState(
                WebViewPool.MediaCaptureState(cameraActive: true),
                for: serviceID
            )
        }
    }

    /// A muted microphone still holds the device, so the page is still in a
    /// call. `isCapturing` includes it, and the sweep must respect that.
    @MainActor
    func testCapacitySweepSparesAMutedMicrophone() async throws {
        try await assertCapacitySweepSparesTheLeastRecentService { pool, serviceID in
            pool.setMediaCaptureState(
                WebViewPool.MediaCaptureState(micMuted: true),
                for: serviceID
            )
        }
    }

    /// The call probe covers a call that holds no local device, such as a page
    /// that only receives audio and video.
    @MainActor
    func testCapacitySweepSparesAReportedCall() async throws {
        try await assertCapacitySweepSparesTheLeastRecentService { pool, serviceID in
            pool.callDetectionProbe = { $0 == serviceID }
        }
    }

    /// The guard is not permanent. The service becomes a candidate again after
    /// its call ends, so the pool does not keep a stale exemption.
    @MainActor
    func testAServiceBecomesEligibleAgainAfterCaptureEnds() async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        let store = UUID()
        let services = (0...(WebViewPoolCapacity.maxLoaded + 1)).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        for item in services { context.insert(item) }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }

        pool.preload(services[0])
        pool.setMediaCaptureState(
            WebViewPool.MediaCaptureState(micActive: true),
            for: services[0].id
        )
        for item in services.dropFirst().dropLast() { pool.preload(item) }

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)
        XCTAssertEqual(evicted, [services[1].id], "the call keeps the least recent service loaded")

        // The call ends, and one more service pushes the pool over its limit
        // again. The service that the call protected is now the least recent
        // candidate, so the sweep must release it.
        pool.setMediaCaptureState(nil, for: services[0].id)
        pool.preload(services[services.count - 1])

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertEqual(evicted, [services[1].id, services[0].id])
        XCTAssertTrue(pool.isHibernated(services[0].id))
    }

    /// The idle sweep reads its candidates from the pool, so the guard must
    /// remove a capturing service from that list as well.
    @MainActor
    func testIdleCandidatesExcludeACapturingService() throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        let store = UUID()
        let calling = Self.poolService(label: "Meeting", store: store)
        let idle = Self.poolService(label: "Notes", store: store)
        context.insert(calling)
        context.insert(idle)
        try context.save()

        pool.preload(calling)
        pool.preload(idle)
        pool.setMediaCaptureState(
            WebViewPool.MediaCaptureState(micActive: true, micMuted: false),
            for: calling.id
        )

        let candidates = pool.idleCandidates(now: Date()).map(\.id)
        XCTAssertEqual(candidates, [idle.id])
    }

    /// Fills the pool one service past its limit, protects the least recently
    /// used service with `protect`, and proves that the sweep spared it and
    /// released the next candidate.
    ///
    /// Every preload starts a sweep of its own, so the protection is applied
    /// before the pool goes over its limit.
    @MainActor
    private func assertCapacitySweepSparesTheLeastRecentService(
        file: StaticString = #filePath,
        line: UInt = #line,
        protect: (WebViewPool, UUID) -> Void
    ) async throws {
        let container = try ModelFixtures.groupingContainer()
        let context = container.mainContext
        let pool = makePool()
        defer { pool.shutdown() }

        let store = UUID()
        let services = (0...WebViewPoolCapacity.maxLoaded).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        for item in services { context.insert(item) }
        try context.save()

        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }

        pool.preload(services[0])
        protect(pool, services[0].id)
        for item in services.dropFirst() { pool.preload(item) }
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded + 1, file: file, line: line)

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertEqual(
            evicted,
            [services[1].id],
            "the sweep releases the next candidate instead",
            file: file,
            line: line
        )
        XCTAssertFalse(
            pool.isHibernated(services[0].id),
            "a call keeps the least recently used service loaded",
            file: file,
            line: line
        )
        XCTAssertTrue(pool.hasWebView(for: services[0].id), file: file, line: line)
        XCTAssertTrue(pool.isHibernated(services[1].id), file: file, line: line)
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded, file: file, line: line)
    }

    // MARK: - Background audio (ATL-315)

    /// The exit condition: music or a voice message that the user started keeps
    /// playing after a switch to another service.
    @MainActor
    func testAPlayingServiceIsNotSuspendedOnASwitch() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], false)
    }

    /// The other half of the same rule: a silent service still goes quiet, so
    /// the exemption costs nothing for an ordinary switch.
    @MainActor
    func testAPausedServiceIsSuspendedOnASwitch() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .paused }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// A background page must not keep itself awake by autoplay. Playback that
    /// starts after the switch earns no exemption, so the poll grants nothing.
    @MainActor
    func testPlaybackThatStartsInTheBackgroundEarnsNoExemption() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .paused }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        pool.playbackStateProbe = { _ in .playing }
        let keepsPolling = await pool.pollBackgroundAudio()

        XCTAssertFalse(keepsPolling)
        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// The exemption ends after the grace period, and the normal background
    /// suspension applies again. The clock is injected, so the test does not
    /// wait for it.
    @MainActor
    func testTheExemptionExpiresAfterTheGracePeriod() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        let clock = MutableClock()
        pool.backgroundAudioClock = { clock.now }
        pool.playbackStateProbe = { _ in .playing }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))

        // A gap between two tracks must not end the exemption.
        pool.playbackStateProbe = { _ in .paused }
        clock.advance(BackgroundAudioExemptions.gracePeriod - 1)
        let insideTheGracePeriod = await pool.pollBackgroundAudio()
        XCTAssertTrue(insideTheGracePeriod)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], false)

        clock.advance(1)
        let afterTheGracePeriod = await pool.pollBackgroundAudio()
        XCTAssertFalse(afterTheGracePeriod)
        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// Playback that continues keeps the exemption, however long it runs.
    @MainActor
    func testAPlayingServiceKeepsTheExemptionPastTheGracePeriod() async throws {
        let (pool, services, _) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        let clock = MutableClock()
        pool.backgroundAudioClock = { clock.now }
        pool.playbackStateProbe = { _ in .playing }

        _ = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        for _ in 0..<5 {
            clock.advance(BackgroundAudioExemptions.gracePeriod - 1)
            let keepsPolling = await pool.pollBackgroundAudio()
            XCTAssertTrue(keepsPolling)
        }

        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))
    }

    /// Mute silences the service, so it ends the exemption. Clearing mute does
    /// not bring it back: that matches the existing rule that clearing mute
    /// does not wake a background view.
    @MainActor
    func testMuteRevokesTheExemption() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }
        let mutedIDs = MutableSet()
        pool.isMediaMuted = { mutedIDs.contains($0) }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))

        mutedIDs.insert(services[0].id)
        pool.refreshMediaPlayback()

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)

        mutedIDs.remove(services[0].id)
        pool.refreshMediaPlayback()

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// Pause Audio is the stop action. It ends the exemption, so the service
    /// follows the normal background rule again.
    @MainActor
    func testPauseAudioRevokesTheExemption() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))

        pool.pauseBackgroundAudio(for: services[0].id)

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// A service back on the screen no longer needs the exemption, and the next
    /// switch away from it decides again.
    @MainActor
    func testReturningToTheServiceEndsTheExemption() async throws {
        let (pool, services, _) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }

        _ = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))

        _ = pool.webView(for: services[0])

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
    }

    /// The idle sweep reads its candidates from the pool, so a service that
    /// keeps playing audio must not appear in that list.
    @MainActor
    func testIdleCandidatesExcludeAServicePlayingAudio() async throws {
        let (pool, services, _) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }

        _ = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        // The second service is the active one, which the gate already blocks,
        // so an empty list proves that the audio blocked the first one.
        XCTAssertTrue(pool.idleCandidates(now: Date()).isEmpty)

        pool.pauseBackgroundAudio(for: services[0].id)
        XCTAssertEqual(pool.idleCandidates(now: Date()).map(\.id), [services[0].id])
    }

    /// The capacity sweep releases the least recently used service. A service
    /// that plays audio is protected like a capturing one, so the sweep takes
    /// the next candidate instead.
    @MainActor
    func testTheCapacitySweepSparesAServicePlayingAudio() async throws {
        let (pool, services, _) = try makeAudioFixture(
            count: WebViewPoolCapacity.maxLoaded + 1
        )
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in .playing }
        var evicted: [UUID] = []
        pool.onServiceEvictedForCapacity = { evicted.append($0) }

        // The first service plays and then leaves the screen. It is the least
        // recently used service from here on.
        _ = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)
        XCTAssertTrue(pool.isPlayingBackgroundAudio(services[0].id))

        for item in services.dropFirst(2) { pool.preload(item) }
        XCTAssertEqual(pool.loadedCount, WebViewPoolCapacity.maxLoaded + 1)

        await pool.evictIfNeeded()
        try await waitForLoadedCountToSettle(pool)

        XCTAssertEqual(evicted, [services[2].id], "the sweep takes the next candidate")
        XCTAssertFalse(pool.isHibernated(services[0].id))
        XCTAssertTrue(pool.hasWebView(for: services[0].id))
        XCTAssertTrue(pool.isHibernated(services[2].id))
    }

    /// Nothing plays on an ordinary page, so nothing changes for it: no
    /// exemption, no poll, and the normal suspension on a switch.
    @MainActor
    func testAServiceThatPlaysNothingKeepsTheOldBehavior() async throws {
        let (pool, services, suspension) = try makeAudioFixture(count: 2)
        defer { pool.shutdown() }
        pool.playbackStateProbe = { _ in WKMediaPlaybackState.none }

        let leaving = pool.webView(for: services[0])
        _ = pool.webView(for: services[1])
        await pool.resolveBackgroundAudio(for: services[0].id)

        XCTAssertFalse(pool.isPlayingBackgroundAudio(services[0].id))
        let keepsPolling = await pool.pollBackgroundAudio()
        XCTAssertFalse(keepsPolling)
        XCTAssertEqual(suspension.value[ObjectIdentifier(leaving)], true)
    }

    /// Holds the container of the audio fixture. A service model reads from its
    /// container, so the container must outlive every service the test uses.
    private var audioFixtureContainer: ModelContainer?

    /// Builds a pool, a set of services in one container, and a recorder for
    /// the suspension writes, so each audio test states only its own rule.
    ///
    /// The recorder replaces the WebKit write, so no test depends on a real
    /// media element.
    @MainActor
    private func makeAudioFixture(
        count: Int
    ) throws -> (WebViewPool, [ServiceInstance], SuspensionRecorder) {
        let container = try ModelFixtures.groupingContainer()
        audioFixtureContainer = container
        let context = container.mainContext
        let store = UUID()
        let services = (0..<count).map {
            Self.poolService(label: "Service \($0)", store: store)
        }
        for item in services { context.insert(item) }
        try context.save()

        let pool = makePool()
        let recorder = SuspensionRecorder()
        pool.writeMediaSuspension = { webView, suspended in
            recorder.record(ObjectIdentifier(webView), suspended)
        }
        return (pool, services, recorder)
    }

    /// The last suspension value written for each web view.
    @MainActor
    final class SuspensionRecorder {
        private(set) var value: [ObjectIdentifier: Bool] = [:]

        func record(_ webView: ObjectIdentifier, _ suspended: Bool) {
            value[webView] = suspended
        }
    }

    /// A clock the test moves by hand, so the grace period needs no waiting.
    @MainActor
    final class MutableClock {
        private(set) var now = Date(timeIntervalSince1970: 1_000_000)

        func advance(_ seconds: TimeInterval) {
            now = now.addingTimeInterval(seconds)
        }
    }

    /// Mute that the test changes between two reads of the pool.
    @MainActor
    final class MutableSet {
        private var ids: Set<UUID> = []

        func contains(_ id: UUID) -> Bool { ids.contains(id) }
        func insert(_ id: UUID) { ids.insert(id) }
        func remove(_ id: UUID) { ids.remove(id) }
    }

    /// A capacity test needs many services at the same time. They share one
    /// WebKit data-store identifier, so the test makes one store instead of one
    /// for each service. The pool keys every rule on the service id, so the
    /// shared store changes no result here.
    private static func poolService(
        label: String,
        store: UUID,
        catalogEntryID: String? = nil,
        hibernationPolicyRaw: String? = nil
    ) -> ServiceInstance {
        ServiceInstance(
            label: label,
            url: "about:blank",
            catalogEntryID: catalogEntryID,
            dataStoreIdentifier: store,
            hibernationPolicyRaw: hibernationPolicyRaw
        )
    }

    /// Waits until the pool holds no more views than its limit.
    @MainActor
    private func waitForLoadedCountToSettle(
        _ pool: WebViewPool,
        timeout: Duration = .seconds(10)
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while pool.loadedCount > WebViewPoolCapacity.maxLoaded, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertLessThanOrEqual(
            pool.loadedCount,
            WebViewPoolCapacity.maxLoaded,
            "the capacity sweep must bring the pool back to its limit"
        )
    }

    @MainActor
    private func makePool() -> WebViewPool {
        WebViewPool(
            dataStoreManager: DataStoreManager(),
            userScriptManager: UserScriptManager(),
            contentBlocker: ContentBlockerManager()
        )
    }
}
